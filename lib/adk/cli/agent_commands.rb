# frozen_string_literal: true

module ADK
  module CLI
    # CLI commands for agent management
    class AgentCommands < Thor
      desc 'create NAME', 'Create a new agent'
      method_option :description, type: :string, desc: 'Agent description', required: true
      def create(name)
        agent = ADK::Agent.new(
          name: name,
          description: options[:description]
        )
        puts "Created agent: #{agent.name} (#{agent.description})"
      end

      desc 'list', 'List all agents'
      def list
        # In a real implementation, this would list agents from a registry or storage
        puts "No agents found. Use 'adk agent create' to create one."
      end

      desc 'start NAME', 'Start an agent'
      def start(name)
        # In a real implementation, this would load the agent from a registry
        agent = ADK::Agent.new(name: name, description: 'Loaded agent')
        agent.start
        puts "Started agent: #{agent.name}"
      end

      desc 'stop NAME', 'Stop an agent'
      def stop(name)
        # In a real implementation, this would load the agent from a registry
        agent = ADK::Agent.new(name: name, description: 'Loaded agent')
        agent.stop
        puts "Stopped agent: #{agent.name}"
      end

      desc 'execute NAME TASK', 'Execute a task on an agent'
      def execute(name, task)
        # In a real implementation, this would load the agent from a registry
        agent = ADK::Agent.new(name: name, description: 'Loaded agent')
        agent.start
        result = agent.run_task(task)
        puts "Task result: #{result}"
        agent.stop
      end
    end
  end
end 