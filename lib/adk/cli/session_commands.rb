# File: lib/adk/cli/session_commands.rb
# frozen_string_literal: true

require 'thor'
require 'redis'
require 'json'
require_relative '../session'
require_relative '../session_service/redis'

module ADK
  module CLI
    # CLI commands for session management
    class SessionCommands < Thor
      desc 'list [APP_NAME] [USER_ID]', 'List all sessions or filter by app_name and/or user_id'
      method_option :app_name, type: :string, desc: 'Filter sessions by application name'
      method_option :user_id, type: :string, desc: 'Filter sessions by user ID'
      def list(*args)
        # Parse positional arguments if provided
        app_name = options[:app_name] || args[0]
        user_id = options[:user_id] || args[1]

        session_service = ADK::SessionService::Redis.new
        sessions = session_service.list_sessions(app_name: app_name, user_id: user_id)

        if sessions.empty?
          say "No sessions found#{app_name ? " for app '#{app_name}'" : ''}#{user_id ? " and user '#{user_id}'" : ''}.",
              :yellow
          return
        end

        say "Found #{sessions.length} session(s):", :bold
        sessions.each do |session|
          created_at = session.created_at.strftime('%Y-%m-%d %H:%M:%S')
          say "  ID: #{session.id}", :cyan
          say "    App: #{session.app_name}"
          say "    User: #{session.user_id}"
          say "    Created: #{created_at}"
          say "    Events: #{session.events.length}"
          say ''
        end
      end

      desc 'show SESSION_ID', 'Show details of a specific session including events'
      def show(session_id)
        session_service = ADK::SessionService::Redis.new
        session = session_service.get_session(session_id: session_id)

        unless session
          say "Session '#{session_id}' not found.", :red
          return
        end

        created_at = session.created_at.strftime('%Y-%m-%d %H:%M:%S')
        say 'Session Details:', :bold
        say "  ID: #{session.id}", :cyan
        say "  App: #{session.app_name}"
        say "  User: #{session.user_id}"
        say "  Created: #{created_at}"
        say "  Events: #{session.events.length}"

        if session.events.empty?
          say "\nNo events in this session.", :yellow
          return
        end

        say "\nEvents:", :bold
        session.events.each_with_index do |event, index|
          say "  #{index + 1}. [#{event.role}] #{event.content.inspect}"
        end
      end

      desc 'delete SESSION_ID', 'Delete a specific session'
      def delete(session_id)
        session_service = ADK::SessionService::Redis.new

        # Check if session exists first
        session = session_service.get_session(session_id: session_id)
        unless session
          say "Session '#{session_id}' not found.", :red
          return
        end

        # Confirm deletion
        if yes?("Are you sure you want to delete session '#{session_id}'? (y/n)")
          if session_service.delete_session(session_id: session_id)
            say "Session '#{session_id}' deleted successfully.", :green
          else
            say "Failed to delete session '#{session_id}'.", :red
          end
        else
          say 'Deletion cancelled.', :yellow
        end
      end

      desc 'execute AGENT_NAME TASK --session-id=SESSION_ID',
           'Execute a task using an agent with a specific Redis session'
      method_option :session_id, type: :string, desc: 'ID of an existing Redis session to use'
      method_option :user_id, type: :string, default: 'cli_user', desc: 'User ID for the session'
      def execute(agent_name, task)
        # This is a wrapper around the agent execute command that uses Redis sessions
        # We'll delegate to the agent_commands.rb implementation but with Redis session service

        # First, check if the agent exists
        redis = Redis.new
        key = "adk:agent:#{agent_name}"
        redis_agent_data = redis.hmget(key, 'description', 'tools', 'model')
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]
        model_name = redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL

        unless description
          say "Error: Agent definition '#{agent_name}' not found.", :red
          exit(1)
        end

        # Use Redis session service instead of InMemory
        session_service = ADK::SessionService::Redis.new
        session_id = options[:session_id]
        adk_session = nil

        if session_id
          adk_session = session_service.get_session(session_id: session_id)
          if adk_session
            say "Using existing Redis session: #{session_id}", :cyan
          else
            say "Warning: Session ID '#{session_id}' provided but not found. Starting a new session.", :yellow
            session_id = nil # Force creation below
          end
        end

        unless adk_session
          # Create a new Redis session
          adk_session = session_service.create_session(app_name: agent_name, user_id: options[:user_id])
          session_id = adk_session.id
          say "Started new Redis session: #{session_id}", :cyan
        end

        # Now execute the task using the agent_commands implementation
        agent_commands = ADK::CLI::AgentCommands.new
        agent_commands.invoke(:execute, [agent_name, task],
                              { session_id: session_id, session_service: session_service })
      end
    end
  end
end
