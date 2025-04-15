# frozen_string_literal: true

require 'thor'
require_relative 'cli/agent_commands'
require_relative 'cli/tool_commands'
require_relative 'cli/web_commands'

module ADK
  module CLI
    # Main CLI class that handles all commands
    class Main < Thor
      desc 'version', 'Display ADK version'
      def version
        puts "ADK version #{ADK::VERSION}"
      end

      desc 'agent SUBCOMMAND ...ARGS', 'Agent management commands'
      subcommand 'agent', AgentCommands

      desc 'tool SUBCOMMAND ...ARGS', 'Tool management commands'
      subcommand 'tool', ToolCommands

      desc 'web SUBCOMMAND ...ARGS', 'Web interface commands'
      subcommand 'web', WebCommands
    end
  end
end 