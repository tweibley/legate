# frozen_string_literal: true

# File: lib/legate/agents/parallel_agent.rb
require_relative '../agent'
require 'concurrent'

module Legate
  module Agents
    # ParallelAgent executes a set of sub-agents concurrently.
    # All sub-agents are started simultaneously and the agent waits for all to complete.
    class ParallelAgent < Legate::Agent
      DEFAULT_PARALLEL_TIMEOUT = 120

      # Override run_task to execute sub-agents in parallel
      # @param session_id [String] The session ID
      # @param user_input [String] User input to process
      # @param session_service [Legate::SessionService::Base] Session service for persistence
      # @return [Legate::Event] The final agent event
      def run_task(session_id:, user_input:, session_service:)
        # Verify we have parallel sub-agents defined
        unless @definition.parallel_sub_agent_names&.any?
          err_msg = "ParallelAgent '#{name}' has no parallel_sub_agent_names defined."
          Legate.logger.error(err_msg)
          return Legate::Event.new(role: :agent, content: {
                                     status: :error,
                                     error_message: err_msg,
                                     error_class: 'ConfigurationError'
                                   })
        end

        # --- Pre-execution Checks --- #
        unless running?
          err_msg = "Agent '#{name}' is not running. Call agent.start before run_task, " \
                    'or use agent.ask (which starts automatically).'
          Legate.logger.error(err_msg)
          return Legate::Event.new(role: :agent, content: { status: :error, error_message: err_msg })
        end

        session = session_service.get_session(session_id: session_id)
        unless session
          err_msg = "Session not found: #{session_id}"
          Legate.logger.error(err_msg)
          return Legate::Event.new(role: :agent, content: { status: :error, error_message: err_msg })
        end
        # --------------------------- #

        # Log user input to the ParallelAgent itself
        user_event = Legate::Event.new(role: :user, content: user_input)
        session_service.append_event(session_id: session_id, event: user_event)

        # Log the execution start
        Legate.logger.info("ParallelAgent '#{name}' starting parallel execution of #{@definition.parallel_sub_agent_names.size} sub-agents.")

        # Get the sub-agents to run in parallel
        sub_agents_to_run = []
        missing_agents = []

        @definition.parallel_sub_agent_names.each do |sub_agent_name|
          sub_agent = find_sub_agent(sub_agent_name)
          if sub_agent
            # Start the sub-agent if it's not already running
            sub_agent.start unless sub_agent.running?
            sub_agents_to_run << { name: sub_agent_name, agent: sub_agent }
          else
            missing_agents << sub_agent_name
          end
        end

        # Check if any agents are missing
        unless missing_agents.empty?
          err_msg = "The following sub-agents were not found for ParallelAgent '#{name}': #{missing_agents.join(', ')}."
          Legate.logger.error(err_msg)
          return Legate::Event.new(role: :agent, content: {
                                     status: :error,
                                     error_message: err_msg,
                                     error_class: 'MissingSubAgentError'
                                   })
        end

        # Prepare futures for parallel execution
        futures = {}
        sub_agents_to_run.each do |agent_info|
          futures[agent_info[:name]] = Concurrent::Promises.future do
            Legate.logger.info("ParallelAgent '#{name}' executing sub-agent '#{agent_info[:name]}' in parallel.")
            agent_info[:agent].run_task(
              session_id: session_id,
              user_input: user_input,
              session_service: session_service
            )
          rescue StandardError => e
            Legate.logger.error("Error executing sub-agent '#{agent_info[:name]}': #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
            # Return an error event
            Legate::Event.new(role: :agent, content: {
                                status: :error,
                                error_message: "Exception in sub-agent '#{agent_info[:name]}': #{e.message}",
                                error_class: e.class.name
                              })
          end
        end

        # Wait for all futures to complete
        all_results = {}
        has_errors = false
        timeout = @definition.respond_to?(:parallel_timeout_seconds) && @definition.parallel_timeout_seconds || DEFAULT_PARALLEL_TIMEOUT

        futures.each do |agent_name, future|
          result = future.value(timeout)
          all_results[agent_name] = result.content
          has_errors = true if result.content[:status] == :error
        rescue Concurrent::TimeoutError
          Legate.logger.error("Timeout waiting for sub-agent '#{agent_name}' to complete.")
          all_results[agent_name] = {
            status: :error,
            error_message: 'Timeout waiting for sub-agent to complete',
            error_class: 'TimeoutError'
          }
          has_errors = true
        rescue StandardError => e
          Legate.logger.error("Error processing sub-agent '#{agent_name}' result: #{e.class} - #{e.message}")
          all_results[agent_name] = {
            status: :error,
            error_message: "Error processing result: #{e.message}",
            error_class: e.class.name
          }
          has_errors = true
        end

        # Create the final result
        final_result = {
          status: has_errors ? :partial_success : :success,
          result: if has_errors
                    'Completed parallel execution with some errors'
                  else
                    "Successfully completed parallel execution of #{@definition.parallel_sub_agent_names.size} sub-agents"
                  end,
          sub_results: all_results,
          agents_completed: all_results.keys.map(&:to_sym),
          all_successful: !has_errors
        }

        # Create the final event
        final_agent_event = Legate::Event.new(role: :agent, content: final_result)

        # Log the final event to the session
        session_service.append_event(session_id: session_id, event: final_agent_event)

        # --- MAS: Store result in session state if output_key is defined --- #
        if @definition.respond_to?(:output_key) && @definition.output_key && final_agent_event
          output_value = final_agent_event.content # Store the entire content hash
          Legate.logger.info("ParallelAgent '#{@name}' storing output to session state with key '#{@definition.output_key}' for session '#{session_id}'.")
          if session_service.respond_to?(:set_state)
            session_service.set_state(session_id: session_id, key: @definition.output_key, value: output_value)
          else
            Legate.logger.warn("ParallelAgent '#{@name}': Session service does not support :set_state. Cannot store output for key '#{@definition.output_key}'.")
          end
        end
        # --- End MAS State Management --- #

        final_agent_event
      end
    end
  end
end
