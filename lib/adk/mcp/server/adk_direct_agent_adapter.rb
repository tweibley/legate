# File: lib/adk/mcp/server/adk_direct_agent_adapter.rb
# frozen_string_literal: true

require 'fast_mcp'
require 'securerandom'
require_relative '../../agent'
require_relative '../../session_service/base'
require_relative '../../event'
require_relative '../error'

module ADK
  module Mcp
    module Server
      # Adapter to expose an ADK::Agent instance directly as a single tool via fast-mcp.
      # The agent is used ephemerally for each call.
      class AdkDirectAgentAdapter < FastMcp::Tool
        class << self
          attr_reader :adk_agent_instance, :session_service
        end

        # Dynamically creates a new FastMcp::Tool subclass that wraps the given ADK::Agent instance.
        #
        # @param agent_instance [ADK::Agent] The initialized ADK::Agent instance to wrap.
        # @param session_service_instance [ADK::SessionService::Base] The session service for temporary sessions.
        # @return [Class<AdkDirectAgentAdapter>] A new anonymous class inheriting from AdkDirectAgentAdapter.
        def self.wrap(agent_instance, session_service_instance)
          unless agent_instance.is_a?(ADK::Agent)
            raise ArgumentError, "Provided object is not a valid ADK::Agent instance."
          end
          unless session_service_instance.is_a?(ADK::SessionService::Base)
            raise ArgumentError, "Session service instance must inherit from ADK::SessionService::Base."
          end

          agent_name = agent_instance.name
          agent_description = agent_instance.description

          # Create the anonymous adapter class
          adapter_class = Class.new(AdkDirectAgentAdapter) do
            # Store instances on the generated class
            @adk_agent_instance = agent_instance
            @session_service = session_service_instance

            # Set fast-mcp tool metadata
            tool_name "run_agent_#{agent_name}" # Or just agent_name if desired
            description "Runs the ADK Agent '#{agent_name}': #{agent_description}"

            # Define the single prompt argument
            arguments do
              required(:prompt).filled(:string).description('The user input/prompt for the agent')
            end

            Mcp.logger.info("Created direct fast-mcp adapter for ADK agent instance: '#{agent_name}'")
          end

          adapter_class
        end

        # Executes the wrapped ADK Agent instance for a single turn.
        #
        # @param prompt [String] The user prompt.
        # @return [Any] The final result payload from the agent's execution.
        # @raise [StandardError] If agent execution fails or returns an error status.
        def call(prompt:)
          # Retrieve instances from the *class* instance variables
          agent = self.class.adk_agent_instance
          session_service = self.class.session_service
          raise NotImplementedError,
                "AdkDirectAgentAdapter must be configured using .wrap first." unless agent && session_service

          agent_name = agent.name
          Mcp.logger.info("Executing ADK Agent '#{agent_name}' via direct MCP adapter with prompt: '#{prompt}'")

          temp_session = nil
          was_agent_already_running = agent.running?
          begin
            # 1. Create Temporary Session
            Mcp.logger.debug("Creating temporary session...")
            temp_session = session_service.create_session(app_name: agent_name,
                                                          user_id: "mcp_direct_#{SecureRandom.hex(4)}")
            Mcp.logger.debug("Temporary session created: #{temp_session.id}")

            # 2. Ensure Agent is Running
            unless was_agent_already_running
              Mcp.logger.debug("Starting ephemeral agent runtime...")
              agent.start
            end

            # 3. Run Task
            Mcp.logger.debug("Running task in temp session #{temp_session.id}...")
            final_event = agent.run_task(
              session_id: temp_session.id,
              user_input: prompt,
              session_service: session_service
            )
            Mcp.logger.debug("Agent run_task finished. Final event: #{final_event.inspect}")

            # 4. Process Result
            unless final_event.is_a?(ADK::Event) && final_event.role == :agent && final_event.content.is_a?(Hash)
              raise StandardError, "Agent task finished with unexpected event format: #{final_event.inspect}"
            end

            result_content = final_event.content

            case result_content[:status]
            when :success
              return result_content[:result] # Return result payload
            when :error
              err_msg = result_content[:error_message] || "Agent execution failed."
              Mcp.logger.error("Agent '#{agent_name}' execution failed: #{err_msg}")
              raise StandardError, "Agent Error: #{err_msg}"
            when :pending
              job_id = result_content[:job_id]
              msg = result_content[:message] || "Agent task resulted in a pending job."
              Mcp.logger.warn("Agent '#{agent_name}' execution ended with pending status (Job: #{job_id}). Returning as structured data.")
              return { status: 'pending', job_id: job_id, message: msg }
            else
              raise StandardError, "Agent task finished with unknown status: #{result_content[:status]}"
            end
          rescue StandardError => e
            Mcp.logger.error("Error during AdkDirectAgentAdapter call for '#{agent_name}': #{e.class} - #{e.message}")
            Mcp.logger.error(e.backtrace.join("\n"))
            raise StandardError, "Failed to run agent '#{agent_name}': #{e.message}"
          ensure
            # 5. Cleanup
            unless was_agent_already_running
              if agent&.running?
                begin
                  Mcp.logger.debug("Stopping ephemeral agent runtime...")
                  agent.stop
                rescue StandardError => stop_e
                  Mcp.logger.error("Error stopping agent runtime during cleanup: #{stop_e.message}")
                end
              end
            end
            if temp_session && session_service
              begin
                Mcp.logger.debug("Deleting temporary session: #{temp_session.id}")
                session_service.delete_session(session_id: temp_session.id)
              rescue StandardError => del_e
                Mcp.logger.error("Error deleting temporary session #{temp_session.id}: #{del_e.message}")
              end
            end
          end
        end
      end
    end
  end
end
