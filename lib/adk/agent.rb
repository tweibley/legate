# File: lib/adk/agent.rb
# frozen_string_literal: true

require 'logger'
require 'concurrent'
# Note: Requires for Planner, Session, Memory, Tool are handled by lib/adk.rb loading order

module ADK
  # Define Error if not already defined centrally in lib/adk.rb
  class Error < StandardError; end unless defined?(ADK::Error)

  # Agent class represents an AI agent that can perform tasks
  class Agent
    attr_reader :name, :description, :tools, :session, :memory, :planner, :logger

    # ... (initialize, add_tool, start, stop, running? methods remain the same) ...
    def initialize(name:, description:, **options)
      @name = name
      @description = description
      @tools = [] # Initialize as empty; tools are added via add_tool
      @logger = options[:logger] || ADK.logger # Default logger
      @planner = options[:planner] || ADK::Planner.new(agent: self, logger: @logger)
      @memory = options[:memory] || ADK::Memory.new(agent: self)
      @session = options[:session] || ADK::Session.new(agent: self)
      @state = Concurrent::Map.new # For runtime state like :running
    end

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

    def start
      unless running?
        logger.info("Starting agent: #{name}")
        @state[:running] = true
      else
        logger.warn("Agent '#{name}' is already running.")
      end
      self
    end

    def stop
      if running?
        logger.info("Stopping agent: #{name}")
        @state[:running] = false
      else
        logger.warn("Agent '#{name}' is already stopped.")
      end
      self
    end

    def running?
      @state[:running] == true
    end

    # --- MODIFIED: run_task to handle hash/array of hashes ---
    # Process a high-level task.
    # @param task [String] The task description.
    # @return [Hash, Array<Hash>] A hash result for single-step plans,
    #                             an array of hashes for multi-step plans,
    #                             or a single error hash on planning failure.
    def run_task(task)
      unless running?
        msg = "Agent '#{name}' is not running."
        logger.error("Agent '#{name}' cannot run task '#{task}' because it is not running.")
        return { status: :error, error_message: msg } # Return error hash
      end

      logger.info("Agent '#{name}' running task: #{task}")
      begin
        plan = planner.plan(task) # Get plan (potentially multi-step)
        execute_plan(plan) # Execute, result is now hash or array of hashes
      rescue StandardError => e
        logger.error("Error during task execution pipeline for agent '#{name}': #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        # Return error hash
        { status: :error, error_message: "Error during task execution: #{e.message}" }
      end
    end

    private

    # --- MODIFIED: execute_plan to handle/return hashes ---
    # Execute a sequence of steps defined by the planner.
    # @param plan [Array<Hash>] An array of steps.
    # @return [Hash, Array<Hash>] The result hash if plan had 1 step, Array of result hashes if multiple steps.
    #                             Returns a single error hash on planning/execution setup failures.
    def execute_plan(plan)
      unless plan.is_a?(Array)
        msg = "Invalid plan received from planner (not an Array)."
        logger.error("#{msg} Plan: #{plan.inspect}")
        return { status: :error, error_message: msg }
      end
      if plan.empty?
        msg = "I cannot fulfill this request with the available tools (empty plan)."
        logger.warn(msg)
        # It's debatable whether this is an "error" or just an inability.
        # Let's return success=false or a specific status? For now, error hash.
        return { status: :error, error_message: msg }
      end

      logger.debug("Executing plan with #{plan.length} step(s): #{plan.inspect}")
      previous_step_result_hash = nil # Holds the entire result hash of the previous step
      all_results_hashes = [] # Stores result hashes from all steps

      plan.each_with_index do |step, index|
        logger.debug("Executing step #{index + 1}/#{plan.length}: #{step.inspect}")
        logger.debug("  Input (result hash from previous step): #{previous_step_result_hash.inspect}")

        # --- Input Injection Logic (Now uses previous hash) ---
        # Assume for now we inject the value under the :result key if status was :success
        # This requires refinement if tools return different structures or have multiple outputs.
        current_params = step[:params].dup
        current_params.transform_values! do |value|
          if value.is_a?(String) && value.match?(/\[Result from step \d+\]|\[Result from previous step\]/i)
            # Check if previous step succeeded and had a :result key
            if previous_step_result_hash && previous_step_result_hash[:status] == :success && previous_step_result_hash.key?(:result)
              injection_value = previous_step_result_hash[:result]
              logger.debug("  Injecting previous step result '#{injection_value}' into parameter value '#{value}'")
              injection_value # Replace placeholder
            else
              logger.warn("  Cannot inject previous result: Previous step failed, returned no result, or placeholder found inappropriately.")
              # What to do here? Keep placeholder? Raise error? Return error hash?
              # Let's keep the placeholder for now, validation might catch it later.
              value # Keep placeholder if injection impossible
            end
          else
            value # Keep original value
          end
        end
        step_with_injected_params = step.merge(params: current_params)
        logger.debug("  Params after potential injection: #{current_params.inspect}")
        # --- End Input Injection ---

        # Execute the step - execute_step now returns a hash
        current_result_hash = execute_step(step_with_injected_params)
        all_results_hashes << current_result_hash

        # --- Handle Step Failure ---
        # If a step returns status: :error, should we stop the plan?
        # For now, we'll continue, and the error hash becomes input for the next step.
        # More robust error handling could be added here (e.g., stop on error).
        if current_result_hash[:status] == :error
          logger.warn("Step #{index + 1} failed: #{current_result_hash[:error_message]}")
          # Decide whether to halt execution:
          # break # Uncomment this line to stop the plan immediately on step failure
        end

        previous_step_result_hash = current_result_hash # Store hash for the *next* iteration
      end

      logger.debug("Plan execution finished. Result hashes collected: #{all_results_hashes.inspect}")

      # --- Conditional Return Logic (Applied to Hashes) ---
      if plan.length == 1
        single_result_hash = all_results_hashes.first
        logger.debug("Returning single result hash for 1-step plan: #{single_result_hash.inspect}")
        return single_result_hash
      else
        logger.debug("Returning array of result hashes for multi-step plan: #{all_results_hashes.inspect}")
        return all_results_hashes
      end
    end # end execute_plan

    # --- MODIFIED: execute_step to return hash, handle exceptions ---
    # Execute a single step from the plan.
    # @param step [Hash] A hash like { tool: :symbol, params: {...} }
    # @return [Hash] A result hash with :status and (:result or :error_message)
    def execute_step(step)
      unless step.is_a?(Hash) && step.key?(:tool) && step.key?(:params)
        msg = "Invalid step format in plan."
        logger.error("#{msg} Step: #{step.inspect}")
        return { status: :error, error_message: msg }
      end

      tool_name = step[:tool]
      params = step[:params] || {}

      unless tool_name.is_a?(Symbol)
        msg = "Invalid tool name format in plan (not a Symbol)."
        logger.error("#{msg} Name: #{tool_name.inspect}")
        return { status: :error, error_message: msg }
      end

      begin
        tool = find_tool(tool_name) # Raises ADK::Error if not found
        logger.info("Executing tool '#{tool_name}' with params: #{params.inspect}")

        # Tool#execute now returns a hash directly
        result_hash = tool.execute(params)

        # Basic validation of the returned hash from the tool
        unless result_hash.is_a?(Hash) && result_hash.key?(:status)
          logger.error("Tool '#{tool_name}' returned invalid result (not a hash with :status). Result: #{result_hash.inspect}")
          return { status: :error, error_message: "Tool '#{tool_name}' failed to return standard hash format." }
        end
        return result_hash
      rescue ADK::Error => e # Errors finding tool or potentially during tool validation (if tool raises)
        logger.error("ADK::Error during step execution for tool '#{tool_name}': #{e.message}")
        return { status: :error, error_message: e.message }
      rescue StandardError => e # Catch unexpected errors during execute call itself
        logger.error("Unexpected error during step execution pipeline for tool '#{tool_name}': #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        return { status: :error, error_message: "Internal error executing tool '#{tool_name}': #{e.message}" }
      end
    end

    # Find tool (No change needed here)
    def find_tool(name_symbol)
      # ... (implementation from previous response - no change needed) ...
      found_tool = tools.find { |t| t.name == name_symbol }
      unless found_tool
        logger.error("Tool not found in agent '#{name}' tool list: #{name_symbol}")
        # Make sure agent tool list is up-to-date if tools can be added/removed dynamically
        logger.debug("Available tools for agent '#{name}': #{tools.map(&:name).join(', ')}")
        raise ADK::Error, "Tool '#{name_symbol}' not found for this agent."
      end
      found_tool
    end
  end # End Agent class
end # End ADK module
