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
    # Default model used if none is specified during initialization.
    DEFAULT_MODEL = 'gemini-2.0-flash'

    attr_reader :name, :description, :tools, :session, :memory, :planner, :logger, :model_name

    # Initializes a new agent.
    #
    # @param name [String] The unique name of the agent.
    # @param description [String] A description of the agent's purpose.
    # @param model_name [String, nil] The specific LLM model name to use (optional). Defaults to DEFAULT_MODEL.
    # @param options [Hash] Additional options:
    # @option options [ADK::Planner] :planner Custom planner instance.
    # @option options [ADK::Memory] :memory Custom memory instance.
    # @option options [ADK::Session] :session Custom session instance.
    # @option options [Logger] :logger Custom logger instance.
    def initialize(name:, description:, model_name: nil, **options)
      @name = name
      @description = description
      # Use provided model or default, store it
      @model_name = model_name && !model_name.empty? ? model_name : DEFAULT_MODEL
      @tools = [] # Initialize tools array
      @logger = options[:logger] || ADK.logger # Use provided logger or global default
      # Initialize dependencies, passing self and logger/model where needed
      @planner = options[:planner] || ADK::Planner.new(agent: self, logger: @logger, model_name: @model_name)
      @memory = options[:memory] || ADK::Memory.new(agent: self)
      @session = options[:session] || ADK::Session.new(agent: self)
      @state = Concurrent::Map.new # Thread-safe map for runtime state like :running
      logger.info("Agent '#{@name}' initialized with model: '#{@model_name}'")
    end

    # Adds a tool instance to the agent's available tools.
    #
    # @param tool [ADK::Tool] The tool instance to add.
    # @return [self] The agent instance.
    def add_tool(tool)
      unless tool.is_a?(ADK::Tool)
        logger.error("Attempted to add invalid tool: #{tool.inspect}")
        return self
      end
      # Avoid adding duplicates by checking name
      if @tools.any? { |t| t.name == tool.name }
        logger.warn("Tool '#{tool.name}' already added to agent '#{name}'. Skipping.")
      else
        @tools << tool
        logger.debug("Added tool '#{tool.name}' to agent '#{name}'")
      end
      self
    end

    # Marks the agent as running.
    #
    # @return [self] The agent instance.
    def start
      unless running?
        logger.info("Starting agent: #{name}")
        @state[:running] = true
      else
        logger.warn("Agent '#{name}' is already running.")
      end
      self
    end

    # Marks the agent as stopped.
    #
    # @return [self] The agent instance.
    def stop
      if running?
        logger.info("Stopping agent: #{name}")
        @state[:running] = false
      else
        logger.warn("Agent '#{name}' is already stopped.")
      end
      self
    end

    # Checks if the agent is marked as running.
    #
    # @return [Boolean] True if the agent is running, false otherwise.
    def running?
      @state[:running] == true
    end

    # Processes a high-level task by getting a plan from the planner
    # and executing that plan.
    #
    # @param task [String] The task description.
    # @return [Hash, Array<Hash>] The result hash from the last step (for single-step plans),
    #                             an array of result hashes (for multi-step plans),
    #                             or a single error hash on planning failure or execution error.
    def run_task(task)
      unless running?
        msg = "Agent '#{name}' is not running."
        logger.error("Agent '#{name}' cannot run task '#{task}' because it is not running.")
        return { status: :error, error_message: msg } # Return standard error hash
      end

      logger.info("Agent '#{name}' running task: #{task}")
      begin
        plan = planner.plan(task) # Returns Array of Hashes, or empty Array
        execute_plan(plan) # Returns Hash or Array<Hash> or Error Hash
      rescue StandardError => e
        # Catch errors during the plan/execute pipeline itself
        logger.error("Error during task execution pipeline for agent '#{name}': #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        # Return standard error hash
        { status: :error, error_message: "Error during task execution: #{e.message}" }
      end
    end

    private

    # Executes a plan (sequence of steps) provided by the planner.
    # Handles passing results between steps and returns the final outcome(s).
    #
    # @param plan [Array<Hash>] An array of steps, each { tool: :symbol, params: {...} }.
    # @return [Hash, Array<Hash>] Result hash for 1-step plan, Array of hashes for multi-step.
    #                             Returns a single error hash on critical planning/setup failures.
    def execute_plan(plan)
      # Validate plan structure early
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

      logger.debug("Executing plan with #{plan.length} step(s): #{plan.inspect}")
      previous_step_result_hash = nil # Stores the complete hash result of the previous step
      all_results_hashes = [] # Stores result hashes from all steps

      # Iterate through each step in the plan
      plan.each_with_index do |step, index|
        logger.debug("Executing step #{index + 1}/#{plan.length}: #{step.inspect}")
        logger.debug("  Input (result hash from previous step): #{previous_step_result_hash.inspect}")

        # --- Refined Input Injection Logic ---
        current_params = step[:params].dup # Work on a copy
        current_params.transform_values! do |value|
          injection_value = nil # Holds the value to potentially inject
          # Is the parameter value requesting injection?
          if value.is_a?(String) && value.match?(/\[Result from step \d+\]|\[Result from previous step\]/i)
            # Was the previous step successful?
            if previous_step_result_hash && previous_step_result_hash[:status] == :success
              prev_result = previous_step_result_hash[:result]
              # Check if the previous result is a nested success hash (likely from AgentTool)
              if prev_result.is_a?(Hash) && prev_result[:status] == :success && prev_result.key?(:result)
                injection_value = prev_result[:result] # Inject the innermost result
                logger.debug("  Injecting nested result '#{injection_value}' into parameter value '#{value}'")
              # Check if previous result was a simple success value
              elsif previous_step_result_hash.key?(:result)
                injection_value = prev_result # Inject the direct result
                logger.debug("  Injecting direct result '#{injection_value}' into parameter value '#{value}'")
              else
                # Previous step succeeded but had no :result key? Log warning.
                logger.warn("  Cannot inject previous result: Previous step succeeded but has no :result key. Placeholder '#{value}' kept.")
                value # Keep placeholder
              end
            else
              # Previous step failed or didn't exist, cannot inject.
              logger.warn("  Cannot inject previous result: Previous step failed, returned no result, or placeholder found inappropriately. Placeholder '#{value}' kept.")
              value # Keep placeholder
            end
            # Return the determined injection value or the original placeholder
            injection_value || value
          else
            # Not a placeholder string, keep original value
            value
          end
        end # end transform_values!
        step_with_injected_params = step.merge(params: current_params)
        logger.debug("  Params after potential injection: #{current_params.inspect}")
        # --- End Refined Input Injection Logic ---

        # Execute the current step
        current_result_hash = execute_step(step_with_injected_params) # Returns a standard hash
        all_results_hashes << current_result_hash

        # Optional: Halt plan execution if a step fails
        if current_result_hash[:status] == :error
          logger.warn("Step #{index + 1} failed: #{current_result_hash[:error_message]}")
          # Uncomment 'break' to stop the entire plan immediately on step failure
          # break
        end

        # Store the current result hash for the next iteration's injection logic
        previous_step_result_hash = current_result_hash
      end # end plan.each_with_index

      logger.debug("Plan execution finished. Result hashes collected: #{all_results_hashes.inspect}")

      # Return single hash for single-step plans, array otherwise
      if plan.length == 1
        single_result_hash = all_results_hashes.first
        logger.debug("Returning single result hash for 1-step plan: #{single_result_hash.inspect}")
        single_result_hash
      else
        logger.debug("Returning array of result hashes for multi-step plan: #{all_results_hashes.inspect}")
        all_results_hashes
      end
    end # end execute_plan

    # Executes a single step from the plan by finding the correct tool
    # and calling its execute method. Handles finding/execution errors.
    #
    # @param step [Hash] A hash like { tool: :symbol, params: {...} }.
    # @return [Hash] A standard result hash { status: ..., result: ... } or { status: ..., error_message: ... }.
    def execute_step(step)
      unless step.is_a?(Hash) && step.key?(:tool) && step.key?(:params)
        msg = "Invalid step format in plan."
        logger.error("#{msg} Step: #{step.inspect}")
        return { status: :error, error_message: msg }
      end

      tool_name = step[:tool]
      params = step[:params] || {} # Ensure params is a hash

      unless tool_name.is_a?(Symbol)
        msg = "Invalid tool name format in plan (not a Symbol)."
        logger.error("#{msg} Name: #{tool_name.inspect}")
        return { status: :error, error_message: msg }
      end

      begin
        # Find the tool instance associated with this agent
        tool = find_tool(tool_name) # Raises ADK::Error if not found

        logger.info("Executing tool '#{tool_name}' with params: #{params.inspect}")

        # Call the tool's execute method. It performs its own validation
        # and is expected to return a standard status hash.
        result_hash = tool.execute(params)

        # Validate the structure of the hash returned by the tool
        unless result_hash.is_a?(Hash) && result_hash.key?(:status)
          logger.error("Tool '#{tool_name}' returned invalid result (not a hash with :status). Result: #{result_hash.inspect}")
          return { status: :error, error_message: "Tool '#{tool_name}' failed to return standard hash format." }
        end
        # Return the valid hash from the tool
        result_hash
      rescue ADK::Error => e
        # Catch errors finding the tool or validation errors raised by tool.execute
        logger.error("ADK::Error during step execution for tool '#{tool_name}': #{e.message}")
        { status: :error, error_message: e.message }
      rescue StandardError => e
        # Catch unexpected errors during the tool.execute call itself
        logger.error("Unexpected error during step execution pipeline for tool '#{tool_name}': #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        { status: :error, error_message: "Internal error executing tool '#{tool_name}': #{e.message}" }
      end
    end # end execute_step

    # Finds a tool instance added to this agent by its symbolic name.
    #
    # @param name_symbol [Symbol] The symbolic name of the tool.
    # @return [ADK::Tool] The tool instance.
    # @raise [ADK::Error] if the tool is not found in the agent's tool list.
    def find_tool(name_symbol)
      found_tool = tools.find { |t| t.name == name_symbol }
      unless found_tool
        logger.error("Tool not found in agent '#{name}' tool list: #{name_symbol}")
        logger.debug("Available tools for agent '#{name}': #{tools.map(&:name).join(', ')}")
        # Raise an error that can be caught by execute_step
        raise ADK::Error, "Tool '#{name_symbol}' not found for this agent."
      end
      found_tool
    end # end find_tool
  end # End Agent class
end # End ADK module
