# File: lib/adk/agent.rb
# frozen_string_literal: true

require 'logger'
require 'concurrent'
require_relative 'tool_context'
require 'sidekiq' # Ensure sidekiq is required if needed here
# Note: Requires are handled by lib/adk.rb

module ADK
  class Error < StandardError; end unless defined?(ADK::Error)

  # Agent class represents an AI agent that can perform tasks using tools and a planner.
  # It operates within the context of a session managed by a SessionService.
  class Agent
    DEFAULT_MODEL = 'gemini-2.0-flash'

    attr_reader :name, :description, :tools, :planner, :logger, :model_name

    # Initializes a new agent instance.
    # Note: Session and Memory are no longer managed directly by the agent instance.
    #
    # @param name [String] The unique name of the agent definition.
    # @param description [String] A description of the agent's purpose.
    # @param model_name [String, nil] The specific LLM model name (optional).
    # @param options [Hash] Additional options:
    # @option options [ADK::Planner] :planner Custom planner instance.
    # @option options [Logger] :logger Custom logger instance.
    def initialize(name:, description:, model_name: nil, **options)
      @name = name
      @description = description
      @model_name = model_name && !model_name.empty? ? model_name : DEFAULT_MODEL
      @tools = []
      @logger = options[:logger] || ADK.logger
      # Planner is still needed per agent instance, configured with its model
      @planner = options[:planner] || ADK::Planner.new(agent: self, logger: @logger, model_name: @model_name)
      # @memory and @session removed
      @state = Concurrent::Map.new # For runtime state ONLY (e.g., running?)
      logger.info("Agent '#{@name}' initialized with model: '#{@model_name}'")

      # Automatically add check_job_status tool if Sidekiq seems configured
      # (Check if the class exists as a proxy for configuration)
      if defined?(Sidekiq)
        unless @tools.any? { |t| t.name == :check_job_status }
          begin
            status_tool_instance = ADK::ToolRegistry.create_instance(:check_job_status)
            if status_tool_instance
              add_tool(status_tool_instance)
              logger.info("Automatically added :check_job_status tool.")
            else
              logger.warn("Could not automatically add :check_job_status tool (not found in registry).")
            end
          rescue => e
            logger.warn("Failed to automatically add :check_job_status tool: #{e.message}")
          end
        end
      end
    end

    # Adds a tool instance.
    def add_tool(tool)
      unless tool.is_a?(ADK::Tool)
        logger.error("Attempted to add invalid tool: #{tool.inspect}")
        return self
      end
      if @tools.any? { |t| t.name == tool.name }
        logger.warn("Tool '#{tool.name}' already added to agent '#{name}'. Skipping.")
      else
        @tools << tool
        logger.debug("Added tool '#{tool.name}' to agent '#{name}'")
      end
      self
    end

    # --- Runtime State Methods (unchanged) ---
    def start
      unless running?
        logger.info("Starting agent runtime state: #{name}")
        @state[:running] = true
      else
        logger.warn("Agent '#{name}' runtime state is already running.")
      end
      self
    end

    def stop
      if running?
        logger.info("Stopping agent runtime state: #{name}")
        @state[:running] = false
      else
        logger.warn("Agent '#{name}' runtime state is already stopped.")
      end
      self
    end

    def running?
      @state[:running] == true
    end
    # --- End Runtime State Methods ---

    # --- REFACTORED: run_task operates within a session context ---
    # Processes user input within the context of a specific session.
    #
    # @param session_id [String] The ID of the session to use/update.
    # @param user_input [String] The user's input/request for this turn.
    # @param session_service [Object] The service used to manage sessions (must respond to #append_event, #get_session).
    # @return [ADK::Event] The final :agent event containing the response.
    # @return [Hash] An error hash { status: :error, error_message: ... } if a critical error occurs (less common now, errors wrap in Events).
    def run_task(session_id:, user_input:, session_service:)
      final_agent_event = nil
      adk_session = nil

      adk_session = session_service.get_session(session_id: session_id)
      unless adk_session
        msg = "Session not found: #{session_id}"
        logger.error(msg)
        error_event = ADK::Event.new(role: :agent, content: { status: :error, error_message: msg })
        session_service.append_event(session_id: session_id, event: error_event) rescue nil
        return error_event
      end

      unless running?
        msg = "Agent '#{name}' runtime is not active (stopped)."
        logger.error(msg)
        error_event = ADK::Event.new(role: :agent, content: { status: :error, error_message: msg })
        session_service.append_event(session_id: session_id, event: error_event)
        return error_event
      end

      logger.info("Agent '#{name}' starting task in session '#{session_id}': #{user_input}")

      begin
        user_event = ADK::Event.new(role: :user, content: user_input)
        session_service.append_event(session_id: session_id, event: user_event)

        plan = planner.plan(user_input)

        execution_result = execute_plan(plan, adk_session, session_service)

        final_content = nil
        # --- Determine Final Agent Response based on execution result ---
        if execution_result.is_a?(Hash) && execution_result[:status] == :error
          final_content = execution_result
          logger.error("Agent '#{name}' task failed. Reason: #{execution_result[:error_message]}")
        elsif execution_result.is_a?(Array)
          last_step = execution_result.last
          if last_step
            # Pass the entire hash from the last step regardless of status (:success, :error, :pending)
            final_content = last_step
            log_level = (last_step[:status] == :error) ? :warn : :info
            logger.send(log_level,
                        "Agent '#{name}' task completed multi-step with final status: #{last_step[:status]}. Last step msg: #{last_step&.dig(:error_message) || last_step&.dig(:message) || last_step&.dig(:result)}")
          else # Empty results array
            final_content = { status: :error, error_message: "Multi-step execution resulted in empty result array." }
            logger.error(final_content[:error_message])
          end
        elsif execution_result.is_a?(Hash) && [:success, :pending].include?(execution_result[:status]) # Single successful or pending step
          final_content = execution_result
          logger.info("Agent '#{name}' task completed with status: #{execution_result[:status]}. Result: #{final_content[:result] || final_content[:message] || final_content[:job_id]}")
        else # Unexpected format
          msg = "Task finished with unexpected execution result: #{execution_result.inspect}"
          final_content = { status: :error, error_message: msg }
          logger.error(msg)
        end

        unless final_content.is_a?(Hash) && final_content.key?(:status)
          final_content = { status: :success, result: final_content.to_s }
        end
        # --- End Determine Final Agent Response based on execution result ---

        final_agent_event = ADK::Event.new(role: :agent, content: final_content)
        session_service.append_event(session_id: session_id, event: final_agent_event)
      rescue StandardError => e
        logger.error("Critical error during run_task for agent '#{name}': #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        error_event_content = { status: :error, error_message: "An internal error occurred: #{e.message}" }
        final_agent_event = ADK::Event.new(role: :agent, content: error_event_content)
        session_service.append_event(session_id: session_id, event: final_agent_event) if adk_session rescue nil
      end

      final_agent_event
    end

    private

    # --- REFACTORED: execute_plan uses session context ---
    # Executes a plan, logging tool request/result events via the session service.
    # @param plan [Array<Hash>] Plan from the planner.
    # @param session [ADK::Session] The current session object.
    # @param session_service [Object] The session service instance.
    # @return [Hash, Array<Hash>] Result hash or array of hashes from steps. Returns error hash on planning issues.
    def execute_plan(plan, session, session_service)
      session_id = session.id

      unless plan.is_a?(Array)
        msg = "Invalid plan received from planner (not an Array)."
        logger.error("#{msg} Plan: #{plan.inspect}")
        return { status: :error, error_message: msg }
      end
      if plan.empty?
        msg = "I cannot fulfill this request with the available tools (empty plan)."
        logger.warn(msg)
        return { status: :error, error_message: msg }
      end

      logger.debug("Executing plan with #{plan.length} step(s) for session '#{session_id}': #{plan.inspect}")
      previous_step_result_hash = nil
      all_results_hashes = []

      plan.each_with_index do |step, index|
        logger.debug("Executing step #{index + 1}/#{plan.length}: #{step.inspect}")
        logger.debug("  Input (result hash from previous step): #{previous_step_result_hash.inspect}")

        # --- Input Injection Logic (Updated for job_id) ---
        current_params = step[:params].dup
        current_params.transform_values! do |value|
          injection_value = nil
          if value.is_a?(String) && value.match?(/\[Result from step \d+\]|\\[Result from previous step\\]/i)
            if previous_step_result_hash && [:success, :pending].include?(previous_step_result_hash[:status])
              # Prioritize :result, then :job_id (was workflow_id), then :message
              if previous_step_result_hash.key?(:result)
                prev_result = previous_step_result_hash[:result]
                if prev_result.is_a?(Hash) && prev_result.key?(:status) && prev_result.key?(:result) # AgentTool nested result
                  injection_value = prev_result[:result]
                  logger.debug("Injecting nested result...")
                else
                  injection_value = prev_result
                  logger.debug("Injecting direct result...")
                end
              elsif previous_step_result_hash.key?(:job_id) # <-- CHANGED from workflow_id
                injection_value = previous_step_result_hash[:job_id]
                logger.debug("Injecting job_id from previous step...")
              elsif previous_step_result_hash.key?(:message)
                injection_value = previous_step_result_hash[:message]
                logger.debug("Injecting message from previous step...")
              else
                logger.warn("Cannot inject: Previous successful/pending step missing usable key (:result, :job_id, :message). Prev Hash: #{previous_step_result_hash.inspect}")
                value
              end
            else
              logger.warn("Cannot inject: Previous step failed or absent. Prev Hash: #{previous_step_result_hash.inspect}")
              value
            end
            injection_value || value # Use injection if found, otherwise keep original
          else
            value # Not a placeholder string, keep original value
          end
        end
        step_with_injected_params = step.merge(params: current_params)
        logger.debug("  Params after potential injection: #{current_params.inspect}")
        # --- End Input Injection Logic ---

        # --- Execute Step (Passes session context) ---
        current_result_hash = execute_step(step_with_injected_params, session, session_service) # <-- Pass session
        all_results_hashes << current_result_hash

        # --- Stop on first error ---
        if current_result_hash[:status] == :error
          logger.warn("Step #{index + 1} failed, stopping plan execution: #{current_result_hash[:error_message]}")
          break # Exit the loop
        end
        # --- End Stop on first error ---

        previous_step_result_hash = current_result_hash
      end

      logger.debug("Plan execution finished. Result hashes collected: #{all_results_hashes.inspect}")

      # Return single hash or array based on *executed* steps length
      # If loop broke early, return array up to that point.
      # If plan was single step, return the single hash.
      if all_results_hashes.length == 1
        all_results_hashes.first
      else
        all_results_hashes # Return all collected results (including potential error hash)
      end
    end # end execute_plan

    # --- REFACTORED: execute_step uses session context and passes it to tools ---
    # Executes a single step, logging :tool_request and :tool_result events via session service.
    # @param step [Hash] A hash like { tool: :symbol, params: {...} }.
    # @param session [ADK::Session] The current session object.
    # @param session_service [Object] The session service instance.
    # @return [Hash] A standard result hash { status: ..., result/error_message/job_id: ... }. <-- Updated return description
    def execute_step(step, session, session_service) # <-- Takes session object now
      session_id = session.id

      # --- Basic validation ---
      unless step.is_a?(Hash) && step[:tool].is_a?(Symbol) && step[:params].is_a?(Hash)
        msg = "Invalid step format received: #{step.inspect}"
        logger.error(msg)
        # Log as tool_result event (even though it failed before tool call)
        error_event = ADK::Event.new(role: :tool_result, tool_name: step[:tool] || :unknown,
                                     content: { status: :error, error_message: msg })
        session_service.append_event(session_id: session_id, event: error_event)
        return error_event.content
      end
      tool_name = step[:tool]
      params = step[:params]

      # 1. Log Tool Request Event (No state delta typically for requests)
      request_event = ADK::Event.new(role: :tool_request, tool_name: tool_name, content: params)
      session_service.append_event(session_id: session_id, event: request_event)

      # 2. Execute Tool <-- MODIFIED Block Start >>
      result_hash = nil
      begin
        tool = find_tool(tool_name) # Raises ADK::Error if not found

        # --- Create ToolContext ---
        tool_context = ADK::ToolContext.new(
          session_id: session.id,
          user_id: session.user_id,
          app_name: session.app_name
        )
        logger.info("Executing tool '#{tool_name}' with params: #{params.inspect} and context: #{tool_context.to_h.inspect}")
        # --- Pass context to execute ---
        result_hash = tool.execute(params, tool_context) # <-- MODIFIED: Pass context

        # Validate tool's return format (including :pending status)
        unless result_hash.is_a?(Hash) && result_hash.key?(:status) && [:success, :error,
                                                                        :pending].include?(result_hash[:status])
          logger.error("Tool '#{tool_name}' returned invalid hash or status: #{result_hash.inspect}")
          result_hash = { status: :error, error_message: "Tool '#{tool_name}' failed to return standard hash format." }
        end
      rescue ADK::Error => e # Tool not found or validation error from tool.execute
        logger.error("ADK::Error executing tool '#{tool_name}': #{e.message}")
        result_hash = { status: :error, error_message: e.message }
      rescue StandardError => e # Unexpected error within tool.execute
        logger.error("Unexpected error executing tool '#{tool_name}': #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        result_hash = { status: :error, error_message: "Internal error executing tool '#{tool_name}': #{e.message}" }
      end
      # --- << MODIFIED Block End >> ---

      # 3. Log Tool Result Event
      result_event = ADK::Event.new(
        role: :tool_result,
        tool_name: tool_name,
        content: result_hash # Log the entire result hash as content
      )
      session_service.append_event(session_id: session_id, event: result_event)

      # 4. Return the result hash from the tool execution
      result_hash
    end

    # --- find_tool remains unchanged ---
    def find_tool(name_symbol)
      found_tool = tools.find { |t| t.name == name_symbol }
      unless found_tool
        logger.error("Tool not found in agent '#{name}' tool list: #{name_symbol}")
        logger.debug("Available tools for agent '#{name}': #{tools.map(&:name).join(', ')}")
        raise ADK::Error, "Tool '#{name_symbol}' not found for this agent."
      end
      found_tool
    end
  end # End Agent class
end # End ADK module
