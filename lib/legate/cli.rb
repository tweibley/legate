# File: lib/legate/cli.rb
# frozen_string_literal: true

require 'thor'
# Require the files that DEFINE the command classes first
require_relative 'cli/base_command'
require_relative 'cli/output_helper'
require_relative 'cli/agent_commands'
require_relative 'cli/tool_commands'
require_relative 'cli/web_commands'
require_relative 'cli/session_commands'
require_relative 'cli/deployment_commands'
require_relative 'cli/skaffold_commands'
require_relative 'cli/auth_commands'

module Legate
  module CLI
    # Main CLI class that provides the entry point for all Legate commands
    class Main < BaseCommand
      desc 'version', 'Display the Legate version'
      def version
        puts "Legate version #{Legate::VERSION}"
      end

      # Register subcommands
      register(AgentCommands, 'agent', 'agent <command>',
               'Manage Legate agents and execution (list, save, delete, generate, execute, start)')
      register(ToolCommands, 'tool', 'tool <command>', 'Manage Legate tools')
      register(WebCommands, 'web', 'web <command>', 'Manage Legate web interface')
      register(SessionCommands, 'session', 'session <command>', 'Manage Legate sessions')
      register(DeploymentCommands, 'deployment', 'deployment <command>',
               'Generate deployment assets for cloud platforms')
      register(SkaffoldCommands, 'skaffold', 'skaffold [PROJECT_NAME]',
               'Generate a new Legate project structure (alias: new, init)')
      register(AuthCommands, 'auth', 'auth <command>',
               'Manage authentication schemes, credentials, and URL mappings')
    end
    # --- End Main class definition ---
  end # End CLI module
end # End Legate module
