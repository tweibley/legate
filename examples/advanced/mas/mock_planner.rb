# frozen_string_literal: true

module Legate
  # A mock planner that returns pre-defined plans based on the input
  class MockPlanner
    attr_reader :agent, :logger, :model_name

    def initialize(agent:, model_name: nil, **options)
      @agent = agent
      @logger = options[:logger] || Legate.logger
      @model_name = model_name || 'mock-model'
    end

    def plan(user_input)
      input_lower = user_input.downcase

      if input_lower.match?(%r{[\d\s+\-*/()]+}) || input_lower.match?(/calculate|math|sum|multiply|divide|subtract|add/)
        # Math question - delegate to calculator
        return create_delegation_plan(:calculator_agent, user_input) if @agent.definition.delegation_targets&.include?(:calculator_agent)

        create_calculator_plan(user_input)

      elsif input_lower.match?(/who|what|where|when|why|how|explain|describe|tell me|history|science|geography|capital|country/)
        # Knowledge question - delegate to researcher
        return create_delegation_plan(:researcher_agent, user_input) if @agent.definition.delegation_targets&.include?(:researcher_agent)

        create_echo_plan("I know the answer is: Test response about #{user_input}")

      else
        # Simple response
        create_echo_plan("I'll help with: #{user_input}")
      end
    end

    private

    def create_delegation_plan(target_agent, task)
      {
        thought_process: "This task should be delegated to the #{target_agent}",
        steps: [
          {
            tool: :"agent_transfer_to_#{target_agent}",
            params: { task: task }
          }
        ]
      }
    end

    def create_calculator_plan(input)
      # Extract numbers and operations
      expression = input.gsub(%r{[^\d\s+\-*/().]+}, '')
      expression = '2+2' if expression.empty?

      {
        thought_process: 'This appears to be a calculation request',
        steps: [
          {
            tool: :calculate,
            params: { expression: expression.strip }
          }
        ]
      }
    end

    def create_echo_plan(message)
      {
        thought_process: 'Responding directly',
        steps: [
          {
            tool: :echo,
            params: { message: message }
          }
        ]
      }
    end
  end
end
