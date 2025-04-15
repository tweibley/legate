# File: lib/adk/cli.rb
# frozen_string_literal: true

require 'thor'
# Require the files that DEFINE the command classes first
require_relative 'cli/agent_commands'
require_relative 'cli/tool_commands'
require_relative 'cli/web_commands'

module ADK
  module CLI
    # --- Define Main class AFTER command classes are loaded ---
    class Main < Thor
      desc 'version', 'Display ADK version'
      def version
        # require_relative '../version' unless defined?(ADK::VERSION) # Usually loaded via adk.rb
        puts "ADK version #{ADK::VERSION}"
      end

      desc 'agent SUBCOMMAND ...ARGS', 'Agent management commands'
      # Use the full namespace
      subcommand 'agent', ADK::CLI::AgentCommands # <--- Explicit Namespace

      desc 'tool SUBCOMMAND ...ARGS', 'Tool management commands'
      # Use the full namespace
      subcommand 'tool', ADK::CLI::ToolCommands # <--- Explicit Namespace

      desc 'web SUBCOMMAND ...ARGS', 'Web interface commands'
      # Use the full namespace
      subcommand 'web', ADK::CLI::WebCommands # <--- Explicit Namespace
    end
    # --- End Main class definition ---
  end # End CLI module
end # End ADK module
