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

    # Initialize a new agent
    # @param name [String] The name of the agent
    # @param description [String] A description of the agent
    # @param options [Hash] Additional options for the agent
    # @option options [Logger] :logger Custom logger instance
    # @option options [ADK::Session] :session Custom session instance
    # @option options [ADK::Memory] :memory Custom memory instance
    # @option options [ADK::Planner] :planner Custom planner instance
    def initialize(name:, description:, **options)
      @name = name
      @description = description
      @tools = [] # Initialize as empty; tools are added via add_tool
      @logger = options[:logger] || Logger.new($stdout) # Default logger
      # Ensure Planner, Session, Memory classes are loaded before this runs
      # (Handled by load order in lib/adk.rb)
      @session = options[:session] || Session.new(agent: self)
      @memory = options[:memory] || Memory.new(agent: self)
      @planner = options[:planner] || Planner.new(agent: self)
      @state = Concurrent::Map.new # For runtime state like :running
    end

    # Add a tool to the agent's capabilities.
    # Typically called after initialization or during startup based on config.
    # @param tool [Tool] The tool instance to add.
    # @return [self]
    def add_tool(tool)
      unless tool.is_a?(ADK::Tool)
        logger.error("Attempted to add invalid tool: #{tool.inspect}")
        return self
      end
      # Avoid adding duplicate tools (optional, based on name)
      if @tools.any? { |t| t.name == tool.name }
        logger.warn("Tool '#{tool.name}' already added to agent '#{name}'. Skipping.")
      else
        @tools << tool
        logger.debug("Added tool '#{tool.name}' to agent '#{name}'")
      end
      self
    end

    # Start the agent's runtime state.
    # @return [self]
    def start
      # Log start only if not already running to avoid noise
      unless running?
        logger.info("Starting agent: #{name}")
        @state[:running] = true
      else
        logger.warn("Agent '#{name}' is already running.")
      end
      self
    end

    # Stop the agent's runtime state.
    # @return [self]
    def stop
      # Log stop only if currently running
      if running?
        logger.info("Stopping agent: #{name}")
        @state[:running] = false
      else
        logger.warn("Agent '#{name}' is already stopped.")
      end
      self
    end

    # Check if the agent is marked as running.
    # @return [Boolean]
    def running?
      @state[:running] == true
    end

    # Process a high-level task.
    # Uses the planner to break it down and executes the plan.
    # @param task [String] The task description.
    # @return [Object] The final result of executing the plan.
    def run_task(task)
      unless running?
        logger.error("Agent '#{name}' cannot run task '#{task}' because it is not running.")
        # Consider raising an error or returning a specific failure object
        return "Error: Agent '#{name}' is not running."
      end

      logger.info("Agent '#{name}' running task: #{task}")
      begin
        plan = planner.plan(task) # Get plan from planner
        execute_plan(plan) # Execute the obtained plan
      rescue StandardError => e
        logger.error("Error during task execution for agent '#{name}': #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        "Error during task execution: #{e.message}" # Return error message as result
      end
    end

    private

    # Execute a sequence of steps defined by the planner.
    # @param plan [Array<Hash>] An array of steps, each a hash like { tool: :symbol, params: {...} }
    # @return [Object] The result of the *last* step executed.
    def execute_plan(plan)
      unless plan.is_a?(Array)
        logger.error("Planner returned invalid plan (not an Array): #{plan.inspect}")
        return "Error: Invalid plan received from planner."
      end
      if plan.empty?
        logger.warn("Planner returned an empty plan for task.")
        return "No action taken (empty plan)." # Or maybe planner's fallback message?
      end

      logger.debug("Executing plan with #{plan.length} step(s): #{plan.inspect}")
      final_result = nil
      plan.each_with_index do |step, index|
        logger.debug("Executing step #{index + 1}: #{step.inspect}")
        final_result = execute_step(step)
        # TODO: Potentially add logic here to handle step failures or chain results
      end
      logger.debug("Plan execution finished. Final result: #{final_result.inspect}")
      final_result
    end

    # Execute a single step from the plan.
    # @param step [Hash] A hash like { tool: :symbol, params: {...} }
    # @return [Object] The result of the tool execution.
    # @raise [ADK::Error] if the specified tool is not found.
    def execute_step(step)
      unless step.is_a?(Hash) && step.key?(:tool) && step.key?(:params)
        logger.error("Invalid step format received: #{step.inspect}")
        return "Error: Invalid step format in plan." # Or raise?
      end

      tool_name = step[:tool]
      params = step[:params] || {} # Default to empty hash if params are nil

      unless tool_name.is_a?(Symbol)
        logger.error("Invalid tool name in step (not a Symbol): #{tool_name.inspect}")
        return "Error: Invalid tool name format in plan." # Or raise?
      end

      tool = find_tool(tool_name)
      logger.info("Executing tool '#{tool_name}' with params: #{params.inspect}")
      tool.execute(params) # Tool#execute handles validation
    end

    # Find a tool instance added to this agent by its name symbol.
    # @param name_symbol [Symbol] The symbolic name of the tool.
    # @return [Tool] The tool instance.
    # @raise [ADK::Error] if the tool is not found.
    def find_tool(name_symbol)
      found_tool = tools.find { |t| t.name == name_symbol }
      unless found_tool
        logger.error("Tool not found in agent '#{name}' tool list: #{name_symbol}")
        raise ADK::Error, "Tool not found: #{name_symbol}"
      end
      found_tool
    end
  end # End Agent class
end # End ADK module
