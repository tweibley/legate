# frozen_string_literal: true

require 'logger'
require 'concurrent'

module ADK
  # Agent class represents an AI agent that can perform tasks
  class Agent
    attr_reader :name, :description, :tools, :session, :memory, :planner, :logger

    # Initialize a new agent
    # @param name [String] The name of the agent
    # @param description [String] A description of the agent
    # @param options [Hash] Additional options for the agent
    def initialize(name:, description:, **options)
      @name = name
      @description = description
      @tools = []
      @logger = options[:logger] || Logger.new($stdout)
      @session = options[:session] || Session.new(agent: self)
      @memory = options[:memory] || Memory.new(agent: self)
      @planner = options[:planner] || Planner.new(agent: self)
      @state = Concurrent::Map.new
    end

    # Add a tool to the agent
    # @param tool [Tool] The tool to add
    # @return [self]
    def add_tool(tool)
      @tools << tool
      self
    end

    # Start the agent
    # @return [self]
    def start
      logger.info("Starting agent: #{name}")
      @state[:running] = true
      self
    end

    # Stop the agent
    # @return [self]
    def stop
      logger.info("Stopping agent: #{name}")
      @state[:running] = false
      self
    end

    # Check if the agent is running
    # @return [Boolean]
    def running?
      @state[:running] == true
    end

    # Run a task
    # @param task [String] The task to run
    # @return [Object] The result of the task
    def run_task(task)
      logger.info("Running task: #{task}")
      plan = planner.plan(task)
      execute_plan(plan)
    end

    private

    # Execute a plan
    # @param plan [Array] The plan to execute
    # @return [Object] The result of the plan execution
    def execute_plan(plan)
      result = nil
      plan.each do |step|
        result = execute_step(step)
      end
      result
    end

    # Execute a single step of a plan
    # @param step [Hash] The step to execute
    # @return [Object] The result of the step execution
    def execute_step(step)
      tool = find_tool(step[:tool])
      tool.execute(step[:params])
    end

    # Find a tool by name
    # @param name [String] The name of the tool
    # @return [Tool] The tool
    def find_tool(name)
      tools.find { |t| t.name == name } || raise(Error, "Tool not found: #{name}")
    end
  end
end 