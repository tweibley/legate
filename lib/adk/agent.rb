# File: lib/adk/agent.rb
# frozen_string_literal: true

require 'logger'
require 'concurrent'
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
    end

    # Adds a tool instance.
    def add_tool(tool)
      # ... (logic remains the same) ...
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
    # @param session_service [ADK::SessionService::InMemory, Object] The service used to manage sessions.
    # @return [ADK::Event] The final :agent event containing the response.
    # @return [Hash] An error hash { status: :error, error_message: ... } if a critical error occurs.
    def run_task(session_id:, user_input:, session_service:)
      # 1. Retrieve Session
      session = session_service.get_session(session_id: session_id)
      unless session
        msg = "Session not found: #{session_id}"
        logger.error(msg)
        error_event = ADK::Event.new(role: :agent, content: msg)
        session_service.add_event_and_update_state(session_id: session_id, event: error_event) rescue nil
        return error_event
      end

      # Ensure agent runtime state is active (distinct from session)
      unless running?
        msg = "Agent '#{name}' runtime is not active (stopped)."
        logger.error(msg)
        error_event = ADK::Event.new(role: :agent, content: msg)
        session_service.add_event_and_update_state(session_id: session_id, event: error_event) rescue nil
        return error_event
      end

      logger.info("Agent '#{name}' starting task in session '#{session_id}': #{user_input}")

      # 2. Record User Event
      user_event = ADK::Event.new(role: :user, content: user_input)
      session_service.add_event_and_update_state(session_id: session_id, event: user_event)

      # 3. Plan Execution
      plan = []
      final_agent_event = nil
      begin
        # TODO: Pass session history/state to planner if needed for context
        # plan = planner.plan(task: user_input, history: session.events, state: session.state_to_h)
        plan = planner.plan(user_input) # Returns Array of Hashes or empty Array

        # 4. Execute Plan (Logs events internally)
        execution_result = execute_plan(plan, session_id, session_service) # Returns Hash or Array<Hash> or Error Hash

        # 5. Determine Final Agent Response based on execution result
        final_content = nil
        if execution_result.is_a?(Hash) && execution_result[:status] == :error
          # Handle planning error or single-step execution error
          final_content = "Error during processing: #{execution_result[:error_message]}"
          logger.error("Agent '#{name}' task failed. Reason: #{final_content}")
        elsif execution_result.is_a?(Array)
          # Multi-step: Check last step's status
          last_step_result = execution_result.last
          if last_step_result && last_step_result[:status] == :success && last_step_result.key?(:result)
            # Use result of last successful step as final content
            final_content = last_step_result[:result]
            # Handle nested result from AgentTool if necessary
            if final_content.is_a?(Hash) && final_content[:status] == :success && final_content.key?(:result)
              final_content = final_content[:result]
            end
          elsif last_step_result && last_step_result[:status] == :error
            final_content = "Completed plan with error on last step: #{last_step_result[:error_message]}"
            logger.warn("Agent '#{name}' task completed with error. Last step msg: #{last_step_result[:error_message]}")
          else
            # Plan completed, but last step might not have a standard result
            final_content = "Task processing completed. Final step result: #{last_step_result.inspect}"
            logger.info("Agent '#{name}' task completed. Final step result: #{last_step_result.inspect}")
          end
        elsif execution_result.is_a?(Hash) && execution_result[:status] == :success # Single successful step
          final_content = execution_result[:result]
          # Handle nested result from AgentTool if necessary
          if final_content.is_a?(Hash) && final_content[:status] == :success && final_content.key?(:result)
            final_content = final_content[:result]
          end
          logger.info("Agent '#{name}' task completed successfully.")
        else
          # Should not happen if execute_plan returns correctly
          final_content = "Task finished with unexpected execution result: #{execution_result.inspect}"
          logger.error(final_content)
        end

        # Ensure final content is a string for the event (or handle other types?)
        final_content = final_content.to_s unless final_content.is_a?(String)

        # 6. Record Agent Event
        final_agent_event = ADK::Event.new(role: :agent, content: final_content)
        session_service.add_event_and_update_state(session_id: session_id, event: final_agent_event)

        # 7. Return the final agent event itself
        final_agent_event
      rescue StandardError => e
        # Catch errors during the overall run_task flow (e.g., planner errors not caught internally)
        logger.error("Critical error during run_task for agent '#{name}': #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        error_event_content = "An internal error occurred during task processing: #{e.message}"
        # Create and log agent error event
        error_event = ADK::Event.new(role: :agent, content: error_event_content)
        session_service.add_event_and_update_state(session_id: session_id, event: error_event) rescue nil
        error_event
      end
    end # end run_task

    private

    # --- REFACTORED: execute_plan needs session context ---
    # Executes a plan, logging tool request/result events.
    # @param plan [Array<Hash>] Plan from the planner.
    # @param session_id [String] The current session ID.
    # @param session_service [Object] The session service instance.
    # @return [Hash, Array<Hash>] Result hash or array of hashes from steps.
    def execute_plan(plan, session_id, session_service)
      # ... (Plan validation logic remains the same) ...
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

        # --- Input Injection Logic (Updated for nested results) ---
        current_params = step[:params].dup
        current_params.transform_values! do |value|
          injection_value = nil
          if value.is_a?(String) && value.match?(/\[Result from step \d+\]|\[Result from previous step\]/i)
            if previous_step_result_hash && previous_step_result_hash[:status] == :success
              prev_result = previous_step_result_hash[:result]
              if prev_result.is_a?(Hash) && prev_result[:status] == :success && prev_result.key?(:result)
                injection_value = prev_result[:result]
                logger.debug("Injecting nested result...")
              elsif previous_step_result_hash.key?(:result)
                injection_value = prev_result
                logger.debug("Injecting direct result...")
              else logger.warn("Cannot inject: Prev success no :result"); value; end
            else logger.warn("Cannot inject: Prev failed/absent"); value; end
            injection_value || value
          else value; end
        end
        step_with_injected_params = step.merge(params: current_params)
        logger.debug("  Params after potential injection: #{current_params.inspect}")
        # --- End Input Injection Logic ---

        # --- Execute Step (Pass session info for event logging) ---
        current_result_hash = execute_step(step_with_injected_params, session_id, session_service)
        all_results_hashes << current_result_hash

        # --- Stop on first error --- (RECOMMENDED)
        if current_result_hash[:status] == :error
          logger.warn("Step #{index + 1} failed, stopping plan execution: #{current_result_hash[:error_message]}")
          break # Exit the loop
        end
        # --- End Stop on first error ---

        previous_step_result_hash = current_result_hash
      end

      logger.debug("Plan execution finished. Result hashes collected: #{all_results_hashes.inspect}")

      # Return single hash or array based on *original* plan length
      if plan.length == 1
        all_results_hashes.first || { status: :error, error_message: "Single step plan failed to produce result." } # Handle edge case where loop breaks on first step
      else
        all_results_hashes
      end
    end # end execute_plan

    # --- REFACTORED: execute_step needs session context for events ---
    # Executes a single step, logging :tool_request and :tool_result events.
    # @param step [Hash] A hash like { tool: :symbol, params: {...} }.
    # @param session_id [String] The current session ID.
    # @param session_service [Object] The session service instance.
    # @return [Hash] A standard result hash { status: ..., result/error_message: ... }.
    def execute_step(step, session_id, session_service)
      # --- Basic validation ---
      unless step.is_a?(Hash) && step.key?(:tool) && step.key?(:params)
        msg = "Invalid step format in plan."; logger.error(msg); return { status: :error, error_message: msg }
      end
      tool_name = step[:tool]
      params = step[:params] || {}
      unless tool_name.is_a?(Symbol)
        msg = "Invalid tool name format (not Symbol)."; logger.error(msg); return { status: :error, error_message: msg }
      end
      # --- End basic validation ---

      # 1. Log Tool Request Event
      request_event = ADK::Event.new(role: :tool_request, tool_name: tool_name, content: params)
      session_service.add_event_and_update_state(session_id: session_id, event: request_event)

      # 2. Execute Tool
      result_hash = nil
      begin
        tool = find_tool(tool_name) # Raises ADK::Error if not found
        logger.info("Executing tool '#{tool_name}' with params: #{params.inspect}")
        result_hash = tool.execute(params) # Expects { status: :success/:error, ... }

        # Validate tool's return format
        unless result_hash.is_a?(Hash) && result_hash.key?(:status)
          logger.error("Tool '#{tool_name}' returned invalid hash: #{result_hash.inspect}")
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

      # 3. Log Tool Result Event
      result_event = ADK::Event.new(role: :tool_result, tool_name: tool_name, content: result_hash)
      session_service.add_event_and_update_state(session_id: session_id, event: result_event)

      # 4. Return the result hash from the tool execution
      result_hash
    end # end execute_step

    # --- find_tool remains unchanged ---
    def find_tool(name_symbol)
      # ... (same as before) ...
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
