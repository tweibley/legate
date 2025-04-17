# File: lib/adk/cli.rb
# frozen_string_literal: true

require 'thor'
# Require the files that DEFINE the command classes first
require_relative 'cli/agent_commands'
require_relative 'cli/tool_commands'
require_relative 'cli/web_commands'
require_relative 'cli/session_commands'

module ADK
  module CLI
    # --- Define Main class AFTER command classes are loaded ---
    class Main < Thor
      desc 'version', 'Display ADK version'
      def version
        # require_relative '../version' unless defined?(ADK::VERSION) # Usually loaded via adk.rb
        puts "ADK version #{ADK::VERSION}"
      end

      # --- REMOVE ...ARGS from desc ---
      desc 'agent SUBCOMMAND', 'Agent management commands'
      subcommand 'agent', ADK::CLI::AgentCommands

      # --- REMOVE ...ARGS from desc ---
      desc 'tool SUBCOMMAND', 'Tool management commands'
      subcommand 'tool', ADK::CLI::ToolCommands

      # --- REMOVE ...ARGS from desc ---
      desc 'web SUBCOMMAND', 'Web interface commands'
      subcommand 'web', ADK::CLI::WebCommands

      desc 'session SUBCOMMAND', 'Session management commands (Redis-based)'
      subcommand 'session', ADK::CLI::SessionCommands
    end
    # --- End Main class definition ---
  end # End CLI module
end # End ADK module
