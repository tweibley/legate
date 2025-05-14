# frozen_string_literal: true

# File: lib/adk/agents/sequential_agent.rb
require_relative '../agent'

module ADK
  module Agents
    # SequentialAgent executes a series of sub-agents in a predefined order.
    # Each sub-agent is executed one after another, with the same session and input.
    class SequentialAgent < ADK::Agent
      # Override run_task to execute sub-agents in sequence
      # @param session_id [String] The session ID
      # @param user_input [String] User input to process
      # @param session_service [ADK::SessionService::Base] Session service for persistence
      # @return [ADK::Event] The final agent event
      def run_task(session_id:, user_input:, session_service:)
        # Verify we have sequential sub-agents defined
        unless @definition.sequential_sub_agent_names&.any?
          err_msg = "SequentialAgent '#{name}' has no sequential_sub_agent_names defined."
          ADK.logger.error(err_msg)
          return ADK::Event.new(role: :agent, content: { 
            status: :error, 
            error_message: err_msg, 
            error_class: 'ConfigurationError' 
          })
        end

        # --- Pre-execution Checks --- #
        unless running?
          err_msg = "Agent '#{name}' runtime is not active (stopped)."
          ADK.logger.error(err_msg)
          return ADK::Event.new(role: :agent, content: { status: :error, error_message: err_msg })
        end

        session = session_service.get_session(session_id: session_id)
        unless session
          err_msg = "Session not found: #{session_id}"
          ADK.logger.error(err_msg)
          return ADK::Event.new(role: :agent, content: { status: :error, error_message: err_msg })
        end
        # --------------------------- #

        # Log user input to the SequentialAgent itself
        user_event = ADK::Event.new(role: :user, content: user_input)
        session_service.append_event(session_id: session_id, event: user_event)

        # Log the execution sequence start
        ADK.logger.info("SequentialAgent '#{name}' starting execution of #{@definition.sequential_sub_agent_names.size} sub-agents in sequence.")
        
        # Track results of all sub-agents
        all_results = []
        final_result = nil

        # Execute each sub-agent in order
        @definition.sequential_sub_agent_names.each_with_index do |sub_agent_name, index|
          sub_agent = find_sub_agent(sub_agent_name)
          unless sub_agent
            err_msg = "Sub-agent '#{sub_agent_name}' not found for SequentialAgent '#{name}'."
            ADK.logger.error(err_msg)
            final_result = { 
              status: :error, 
              error_message: err_msg, 
              error_class: 'MissingSubAgentError',
              step: index + 1,
              total_steps: @definition.sequential_sub_agent_names.size,
              previous_results: all_results.map.with_index { |r, i| { agent: @definition.sequential_sub_agent_names.to_a[i], result: r } }
            }
            break # Stop the sequence on error
          end

          # Start the sub-agent if it's not already running
          sub_agent.start unless sub_agent.running?

          # Execute the sub-agent with the same session and input
          begin
            ADK.logger.info("SequentialAgent '#{name}' executing sub-agent '#{sub_agent_name}' (step #{index + 1}/#{@definition.sequential_sub_agent_names.size}).")
            sub_result = sub_agent.run_task(
              session_id: session_id,
              user_input: user_input,
              session_service: session_service
            )

            # Record the result
            all_results << sub_result.content
            
            # Check for error to break sequence
            if sub_result.content[:status] == :error
              ADK.logger.warn("Sub-agent '#{sub_agent_name}' returned error, breaking sequence: #{sub_result.content[:error_message]}")
              final_result = { 
                status: :error, 
                error_message: "Error in sub-agent '#{sub_agent_name}': #{sub_result.content[:error_message]}",
                error_class: sub_result.content[:error_class] || 'SubAgentError',
                step: index + 1,
                total_steps: @definition.sequential_sub_agent_names.size,
                sub_agent: sub_agent_name.to_s,
                sub_result: sub_result.content,
                previous_results: all_results.map.with_index { |r, i| { agent: @definition.sequential_sub_agent_names.to_a[i], result: r } }
              }
              break # Stop the sequence on error
            end
          rescue StandardError => e
            ADK.logger.error("Error executing sub-agent '#{sub_agent_name}': #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
            final_result = { 
              status: :error, 
              error_message: "Exception in sub-agent '#{sub_agent_name}': #{e.message}",
              error_class: e.class.name,
              step: index + 1,
              total_steps: @definition.sequential_sub_agent_names.size,
              sub_agent: sub_agent_name.to_s,
              previous_results: all_results.map.with_index { |r, i| { agent: @definition.sequential_sub_agent_names.to_a[i], result: r } }
            }
            break # Stop the sequence on error
          end
        end

        # If we didn't set a final_result due to an error, create a success result with all sub-results
        if final_result.nil?
          final_result = {
            status: :success,
            result: "Completed sequential execution of #{@definition.sequential_sub_agent_names.size} sub-agents",
            steps_completed: @definition.sequential_sub_agent_names.size,
            sub_results: all_results.map.with_index { |r, i| { agent: @definition.sequential_sub_agent_names.to_a[i], result: r } }
          }
        end

        # Create the final event
        final_agent_event = ADK::Event.new(role: :agent, content: final_result)
        
        # Log the final event to the session
        session_service.append_event(session_id: session_id, event: final_agent_event)

        # --- MAS: Store result in session state if output_key is defined --- #
        if @definition.respond_to?(:output_key) && @definition.output_key && final_agent_event
          output_value = final_agent_event.content # Store the entire content hash
          ADK.logger.info("SequentialAgent '#{@name}' storing output to session state with key '#{@definition.output_key}' for session '#{session_id}'.")
          if session_service.respond_to?(:set_state)
            session_service.set_state(session_id: session_id, key: @definition.output_key, value: output_value)
          else
            ADK.logger.warn("SequentialAgent '#{@name}': Session service does not support :set_state. Cannot store output for key '#{@definition.output_key}'.")
          end
        end
        # --- End MAS State Management --- #

        final_agent_event
      end
    end
  end
end 