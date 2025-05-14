# frozen_string_literal: true

# File: lib/adk/agents/loop_agent.rb
require_relative '../agent'

module ADK
  module Agents
    # LoopAgent executes a set of sub-agents repeatedly until a condition is met or
    # maximum iterations are reached.
    class LoopAgent < ADK::Agent
      # Override run_task to execute sub-agents in a loop
      # @param session_id [String] The session ID
      # @param user_input [String] User input to process
      # @param session_service [ADK::SessionService::Base] Session service for persistence
      # @return [ADK::Event] The final agent event
      def run_task(session_id:, user_input:, session_service:)
        # Verify we have loop sub-agents defined
        unless @definition.loop_sub_agent_names&.any?
          err_msg = "LoopAgent '#{name}' has no loop_sub_agent_names defined."
          ADK.logger.error(err_msg)
          return ADK::Event.new(role: :agent, content: { 
            status: :error, 
            error_message: err_msg, 
            error_class: 'ConfigurationError' 
          })
        end

        # Verify we have either loop_max_iterations or a condition
        unless @definition.loop_max_iterations || (@definition.loop_condition_state_key && !@definition.loop_condition_expected_value.nil?)
          err_msg = "LoopAgent '#{name}' must define either loop_max_iterations or loop_condition (state key + expected value)."
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

        # Log user input to the LoopAgent itself
        user_event = ADK::Event.new(role: :user, content: user_input)
        session_service.append_event(session_id: session_id, event: user_event)

        # Determine loop parameters
        max_iterations = @definition.loop_max_iterations || Float::INFINITY
        condition_key = @definition.loop_condition_state_key
        expected_value = @definition.loop_condition_expected_value

        ADK.logger.info("LoopAgent '#{name}' starting execution with max #{max_iterations} iterations" + 
                        (condition_key ? " or until #{condition_key} equals #{expected_value.inspect}" : ""))
        
        # Track loop iterations and results
        iteration = 0
        all_iterations = []
        final_result = nil
        loop_condition_met = false

        # Execute the loop
        while iteration < max_iterations
          iteration += 1
          ADK.logger.info("LoopAgent '#{name}' starting iteration #{iteration}/#{max_iterations == Float::INFINITY ? '∞' : max_iterations}")
          
          # Check condition (if defined) before executing the iteration
          if condition_key && session_service.respond_to?(:get_state)
            current_value = session_service.get_state(session_id: session_id, key: condition_key)
            if current_value == expected_value
              ADK.logger.info("LoopAgent '#{name}' condition met: #{condition_key} = #{expected_value.inspect}. Exiting loop.")
              loop_condition_met = true
              break
            end
          end
          
          # Execute one iteration (all sub-agents in sequence)
          iteration_results = []
          iteration_error = nil
          
          # Execute each sub-agent in order (sequential execution within each iteration)
          @definition.loop_sub_agent_names.each_with_index do |sub_agent_name, index|
            sub_agent = find_sub_agent(sub_agent_name)
            unless sub_agent
              err_msg = "Sub-agent '#{sub_agent_name}' not found for LoopAgent '#{name}'."
              ADK.logger.error(err_msg)
              iteration_error = { 
                status: :error, 
                error_message: err_msg, 
                error_class: 'MissingSubAgentError',
                step: index + 1,
                total_steps: @definition.loop_sub_agent_names.size,
                previous_results: iteration_results.map.with_index { |r, i| { agent: @definition.loop_sub_agent_names.to_a[i], result: r } }
              }
              break # Stop this iteration's execution
            end

            # Start the sub-agent if it's not already running
            sub_agent.start unless sub_agent.running?

            # Execute the sub-agent with the same session and input
            begin
              ADK.logger.info("LoopAgent '#{name}' executing sub-agent '#{sub_agent_name}' (iteration #{iteration}, step #{index + 1}/#{@definition.loop_sub_agent_names.size}).")
              sub_result = sub_agent.run_task(
                session_id: session_id,
                user_input: user_input,
                session_service: session_service
              )

              # Record the result
              iteration_results << { agent: sub_agent_name, result: sub_result.content }
              
              # Check for error to break sequence
              if sub_result.content[:status] == :error
                ADK.logger.warn("Sub-agent '#{sub_agent_name}' returned error, breaking iteration: #{sub_result.content[:error_message]}")
                iteration_error = { 
                  status: :error, 
                  error_message: "Error in sub-agent '#{sub_agent_name}': #{sub_result.content[:error_message]}",
                  error_class: sub_result.content[:error_class] || 'SubAgentError',
                  step: index + 1,
                  total_steps: @definition.loop_sub_agent_names.size,
                  sub_agent: sub_agent_name.to_s,
                  sub_result: sub_result.content
                }
                break # Stop this iteration's execution on error
              end
            rescue StandardError => e
              ADK.logger.error("Error executing sub-agent '#{sub_agent_name}': #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
              iteration_error = { 
                status: :error, 
                error_message: "Exception in sub-agent '#{sub_agent_name}': #{e.message}",
                error_class: e.class.name,
                step: index + 1,
                total_steps: @definition.loop_sub_agent_names.size,
                sub_agent: sub_agent_name.to_s
              }
              break # Stop this iteration's execution on error
            end
          end
          
          # Record this iteration's results
          all_iterations << {
            iteration: iteration,
            results: iteration_results,
            error: iteration_error
          }
          
          # If there was an error in this iteration, we may need to break the loop
          if iteration_error
            # An error occurred during execution - decide whether to break the loop
            ADK.logger.warn("LoopAgent '#{name}' iteration #{iteration} encountered an error. Exiting loop.")
            final_result = { 
              status: :error, 
              error_message: "Loop terminated due to error in iteration #{iteration}: #{iteration_error[:error_message]}",
              error_class: iteration_error[:error_class],
              iterations_completed: iteration,
              max_iterations: max_iterations,
              loop_condition_met: false,
              iterations: all_iterations
            }
            break # Exit the loop on error
          end
          
          # Check condition (if defined) after executing the iteration
          if condition_key && session_service.respond_to?(:get_state)
            current_value = session_service.get_state(session_id: session_id, key: condition_key)
            if current_value == expected_value
              ADK.logger.info("LoopAgent '#{name}' condition met: #{condition_key} = #{expected_value.inspect}. Exiting loop.")
              loop_condition_met = true
              break
            end
          end
        end

        # If we didn't set a final_result due to an error, create a success result
        if final_result.nil?
          completion_reason = if loop_condition_met
                               "condition met (#{condition_key} = #{expected_value.inspect})"
                             elsif iteration >= max_iterations
                               "maximum iterations (#{max_iterations}) reached"
                             else
                               "unknown reason"
                             end
                             
          final_result = {
            status: :success,
            result: "Completed #{iteration} iteration(s) of #{@definition.loop_sub_agent_names.size} sub-agent(s) - #{completion_reason}",
            iterations_completed: iteration,
            max_iterations: max_iterations,
            loop_condition_met: loop_condition_met,
            iterations: all_iterations
          }
        end

        # Create the final event
        final_agent_event = ADK::Event.new(role: :agent, content: final_result)
        
        # Log the final event to the session
        session_service.append_event(session_id: session_id, event: final_agent_event)

        # --- MAS: Store result in session state if output_key is defined --- #
        if @definition.respond_to?(:output_key) && @definition.output_key && final_agent_event
          output_value = final_agent_event.content # Store the entire content hash
          ADK.logger.info("LoopAgent '#{@name}' storing output to session state with key '#{@definition.output_key}' for session '#{session_id}'.")
          if session_service.respond_to?(:set_state)
            session_service.set_state(session_id: session_id, key: @definition.output_key, value: output_value)
          else
            ADK.logger.warn("LoopAgent '#{@name}': Session service does not support :set_state. Cannot store output for key '#{@definition.output_key}'.")
          end
        end
        # --- End MAS State Management --- #

        final_agent_event
      end
    end
  end
end 