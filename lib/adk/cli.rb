# File: lib/adk/cli.rb
# frozen_string_literal: true

require 'thor'
# Require the files that DEFINE the command classes first
require_relative 'cli/agent_commands'
require_relative 'cli/tool_commands'
require_relative 'cli/web_commands'
require_relative 'cli/session_commands'
require_relative 'cli/sidekiq_commands'

module ADK
  module CLI
    # Main CLI class that provides the entry point for all ADK commands
    class Main < Thor
      desc 'version', 'Display the ADK version'
      def version
        # require_relative '../version' unless defined?(ADK::VERSION) # Usually loaded via adk.rb
        puts "ADK version #{ADK::VERSION}"
      end

      # Register subcommands
      register(AgentCommands, 'agent', 'agent <command>',
               'Manage ADK agents and execution (list, save, delete, generate, execute, start)')
      register(ToolCommands, 'tool', 'tool <command>', 'Manage ADK tools')
      register(WebCommands, 'web', 'web <command>', 'Manage ADK web interface')
      register(SessionCommands, 'session', 'session <command>', 'Manage ADK sessions')
      register(SidekiqCommands, 'sidekiq', 'sidekiq <command>', 'Manage Sidekiq workers and jobs')
    end
    # --- End Main class definition ---
  end # End CLI module
end # End ADK module
