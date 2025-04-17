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
      final_agent_event = nil # Define here for scope

      # --- Pre-check: Get Session ---
      session = session_service.get_session(session_id: session_id)
      unless session
        msg = "Session not found: #{session_id}"
        logger.error(msg)
        # Create and attempt to log an error event *even if session isn't found*
        # The service might handle this case (e.g., log to central log).
        error_event = ADK::Event.new(role: :agent, content: msg)
        session_service.append_event(session_id: session_id, event: error_event) rescue nil # Best effort
        return error_event # Return the event itself
      end

      # --- Pre-check: Agent Running? ---
      unless running?
        msg = "Agent '#{name}' runtime is not active (stopped)."
        logger.error(msg)
        error_event = ADK::Event.new(role: :agent, content: msg)
        session_service.append_event(session_id: session_id, event: error_event)
        return error_event
      end

      logger.info("Agent '#{name}' starting task in session '#{session_id}': #{user_input}")

      # --- Task Processing Block ---
      begin
        # 1. Record User Event
        # State Change: User input typically doesn't change session state directly, so no delta.
        user_event = ADK::Event.new(role: :user, content: user_input)
        session_service.append_event(session_id: session_id, event: user_event)

        # 2. Plan Execution
        plan = []
        # TODO: Pass session history/state to planner if needed for context
        # plan = planner.plan(task: user_input, history: session.events, state: session.state_to_h)
        plan = planner.plan(user_input) # Returns Array of Hashes or empty Array

        # 3. Execute Plan (Logs events internally)
        # Returns Hash or Array<Hash> or Error Hash
        # Note: execute_plan now calls execute_step which uses append_event internally
        execution_result = execute_plan(plan, session_id, session_service)

        # 4. Determine Final Agent Response based on execution result
        final_content = nil
        # --- State Change: Define delta hash if needed ---
        # state_changes_from_task = {} # Example: { user_preference: 'blue' }

        if execution_result.is_a?(Hash) && execution_result[:status] == :error
          # Handle planning error or single-step execution error
          final_content = "Error during processing: #{execution_result[:error_message]}"
          logger.error("Agent '#{name}' task failed. Reason: #{final_content}")
        elsif execution_result.is_a?(Array)
          # Multi-step: Use the last step's result
          last_step = execution_result.last
          if last_step && last_step[:status] == :success
            final_content = last_step[:result]
            # Handle nested result from AgentTool if necessary
            if final_content.is_a?(Hash) && final_content[:status] == :success && final_content.key?(:result)
              final_content = final_content[:result]
            end
            logger.info("Agent '#{name}' task completed with multiple steps.")
          else
            final_content = "Task processing completed with error on last step: #{last_step&.dig(:error_message)}"
            logger.warn("Agent '#{name}' task completed with error. Last step msg: #{last_step&.dig(:error_message)}")
          end
        elsif execution_result.is_a?(Hash) && execution_result[:status] == :success # Single successful step
          final_content = execution_result[:result]
          if final_content.is_a?(Hash) && final_content[:status] == :success && final_content.key?(:result)
            final_content = final_content[:result]
          end
          logger.info("Agent '#{name}' task completed successfully.")
        else
          final_content = "Task finished with unexpected execution result: #{execution_result.inspect}"
          logger.error(final_content)
        end

        # Ensure final content is string/serializable for the event
        final_content = final_content.to_s unless final_content.is_a?(String) || final_content.is_a?(Hash) || final_content.is_a?(Array) # etc.

        # 5. Record Final Agent Event (potentially with state changes)
        final_agent_event = ADK::Event.new(
          role: :agent,
          content: final_content
          # state_delta: state_changes_from_task # Pass the delta if any state changes occurred
        )
        session_service.append_event(session_id: session_id, event: final_agent_event)
      rescue StandardError => e
        # Catch errors during the overall run_task flow (e.g., planner errors not caught internally)
        logger.error("Critical error during run_task for agent '#{name}': #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        error_event_content = "An internal error occurred during task processing: #{e.message}"
        # Create and log agent error event
        final_agent_event = ADK::Event.new(role: :agent, content: error_event_content)
        session_service.append_event(session_id: session_id, event: final_agent_event) rescue nil # Best effort log
      end

      # 6. Return the final agent event itself (even if it's an error event)
      final_agent_event
    end # end run_task

    private

    # --- REFACTORED: execute_plan uses new append_event via execute_step ---
    # Executes a plan, logging tool request/result events via the session service.
    # @param plan [Array<Hash>] Plan from the planner.
    # @param session_id [String] The current session ID.
    # @param session_service [Object] The session service instance.
    # @return [Hash, Array<Hash>] Result hash or array of hashes from steps. Returns error hash on planning issues.
    def execute_plan(plan, session_id, session_service)
      unless plan.is_a?(Array)
        msg = "Invalid plan received from planner (not an Array)."
        logger.error("#{msg} Plan: #{plan.inspect}")
        return { status: :error, error_message: msg } # Return error hash for invalid plan structure
      end
      if plan.empty?
        msg = "I cannot fulfill this request with the available tools (empty plan)."
        logger.warn(msg)
        # Return error hash for empty plan, run_task will wrap this in an event
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
          # Placeholder logic - adapt as needed based on placeholder format
          injection_value = nil
          if value.is_a?(String) && value.match?(/\[Result from step \d+\]|\[Result from previous step\]/i)
            if previous_step_result_hash && previous_step_result_hash[:status] == :success
              prev_result = previous_step_result_hash[:result]
              # Handle nested results if previous step was AgentTool
              if prev_result.is_a?(Hash) && prev_result[:status] == :success && prev_result.key?(:result)
                injection_value = prev_result[:result]
                logger.debug("Injecting nested result...")
              elsif previous_step_result_hash.key?(:result) # Handle direct results
                injection_value = prev_result
                logger.debug("Injecting direct result...")
              else # Previous step succeeded but had no :result key? Log warning.
                logger.warn("Cannot inject: Previous successful step missing :result key. Prev Hash: #{previous_step_result_hash.inspect}")
                value # Keep original placeholder
              end

            else # Previous step failed or was nil
              logger.warn("Cannot inject: Previous step failed or absent. Prev Hash: #{previous_step_result_hash.inspect}")
              value # Keep original placeholder
            end
            injection_value || value # Use injection if found, otherwise keep original
          else
            value # Not a placeholder string, keep original value
          end
        end
        step_with_injected_params = step.merge(params: current_params)
        logger.debug("  Params after potential injection: #{current_params.inspect}")
        # --- End Input Injection Logic ---

        # --- Execute Step (Calls append_event internally for tool events) ---
        current_result_hash = execute_step(step_with_injected_params, session_id, session_service)
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

    # --- REFACTORED: execute_step uses new append_event signature ---
    # Executes a single step, logging :tool_request and :tool_result events via session service.
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

      # 1. Log Tool Request Event (No state delta typically for requests)
      request_event = ADK::Event.new(role: :tool_request, tool_name: tool_name, content: params)
      session_service.append_event(session_id: session_id, event: request_event)

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
      # --- State Change: Tool results *could* potentially update state ---
      # Example: If a tool finds user's location, it might want to store it.
      # For now, assume tools don't modify session state unless explicitly designed to.
      # state_delta_from_tool = result_hash.delete(:state_delta) # If tool could return this key
      result_event = ADK::Event.new(
        role: :tool_result,
        tool_name: tool_name,
        content: result_hash # Log the entire result hash as content
        # state_delta: state_delta_from_tool # Add delta if tool provided it
      )
      session_service.append_event(session_id: session_id, event: result_event)

      # 4. Return the result hash from the tool execution (without state_delta if it was extracted)
      result_hash
    end # end execute_step

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
