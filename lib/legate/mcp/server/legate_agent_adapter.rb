# File: lib/legate/mcp/server/legate_agent_adapter.rb
# frozen_string_literal: true

require 'fast_mcp'
require 'json' # Needed to parse tools
require 'securerandom'
require_relative '../../agent'
require_relative '../../tool_registry'
require_relative '../../session_service/base' # Need base for type check
require_relative '../../event' # Needed for result processing
require_relative '../../errors'
require_relative '../../global_tool_manager' # Added require
require_relative '../../global_definition_registry' # For definition lookups

module Legate
  module Mcp
    module Server
      # (Experimental) Adapter to expose an entire Legate::Agent (defined in GlobalDefinitionRegistry)
      # as a single, simple tool via fast-mcp.
      # The agent runs ephemerally for each call
      class LegateAgentAdapter < FastMcp::Tool
        # --- Class Configuration ---
        # Using class instance variables set by `wrap`
        class << self
          attr_reader :agent_definition_name, :session_service
        end
        # -------------------------

        # Dynamically creates a new FastMcp::Tool subclass that wraps an Legate Agent definition.
        #
        # @param agent_definition_name [String] The name of the agent definition in GlobalDefinitionRegistry.
        # @param session_service_instance [Legate::SessionService::Base] The session service to use for temporary sessions.
        # @return [Class<LegateAgentAdapter>] A new anonymous class inheriting from LegateAgentAdapter.
        def self.wrap(agent_definition_name, session_service_instance)
          raise ArgumentError, 'Agent definition name must be a non-empty String.' unless agent_definition_name.is_a?(String) && !agent_definition_name.empty?
          raise ArgumentError, 'Session service instance must inherit from Legate::SessionService::Base.' unless session_service_instance.is_a?(Legate::SessionService::Base)

          # Create the anonymous adapter class
          Class.new(LegateAgentAdapter) do
            # Store config on the generated class
            @agent_definition_name = agent_definition_name
            @session_service = session_service_instance

            # Set fast-mcp tool metadata
            # Use a modified tool name to avoid clashes if agent name = tool name
            tool_name "run_agent_#{agent_definition_name}"
            description "Runs the Legate Agent '#{agent_definition_name}' with the given prompt."

            # Define the single prompt argument
            arguments do
              required(:prompt).filled(:string).description('The user input/prompt for the agent')
            end

            Mcp.logger.info("Created fast-mcp adapter for Legate agent definition: '#{agent_definition_name}'")
          end
        end

        # Executes the wrapped Legate Agent for a single turn.
        # Loads definition, creates temp session, runs task, cleans up.
        #
        # @param prompt [String] The user prompt.
        # @return [Any] The final result payload from the agent's execution.
        # @raise [StandardError] If agent execution fails or returns an error status.
        def call(prompt:)
          # Retrieve config from the *class* instance variables
          agent_name = self.class.agent_definition_name
          session_service = self.class.session_service
          unless agent_name && session_service
            raise NotImplementedError,
                  'LegateAgentAdapter must be configured using .wrap first.'
          end

          Mcp.logger.info("Executing Legate Agent '#{agent_name}' via MCP adapter with prompt: '#{prompt}'")

          agent = nil
          temp_session = nil
          begin
            # 1. Load Agent Definition from GlobalDefinitionRegistry
            Mcp.logger.debug("Loading agent definition '#{agent_name}' from GlobalDefinitionRegistry...")
            agent_definition_object = Legate::GlobalDefinitionRegistry.find(agent_name.to_sym)

            # Try get_definition if available (expanded API from Phase 2)
            if !agent_definition_object && Legate::GlobalDefinitionRegistry.respond_to?(:get_definition)
              definition_hash = Legate::GlobalDefinitionRegistry.get_definition(agent_name)
              agent_definition_object = Legate::AgentDefinition.from_hash(definition_hash) if definition_hash
            end

            raise Legate::Mcp::Error, "Agent definition '#{agent_name}' not found in GlobalDefinitionRegistry." unless agent_definition_object

            Mcp.logger.debug("Agent definition loaded for '#{agent_name}'.")

            Mcp.logger.debug("AgentDefinition object ready: #{agent_definition_object.name}, Model=#{agent_definition_object.model_name}")

            # 2. Create Temporary Session
            Mcp.logger.debug('Creating temporary session...')
            temp_session = session_service.create_session(app_name: agent_name,
                                                          user_id: "mcp_temp_#{SecureRandom.hex(4)}")
            Mcp.logger.debug("Temporary session created: #{temp_session.id}")

            # 3. Instantiate Agent
            Mcp.logger.debug("Instantiating agent '#{agent_definition_object.name}' with its definition object and session service...")

            agent = Legate::Agent.new(
              definition: agent_definition_object,
              session_service: session_service # Pass the session_service from adapter config
            )
            # Tool loading is handled by Legate::Agent#initialize based on the definition object.

            # 4. Start Agent & Run Task
            Mcp.logger.debug('Starting ephemeral agent runtime...')
            agent.start
            Mcp.logger.debug("Running task in temp session #{temp_session.id}...")
            final_event = agent.run_task(
              session_id: temp_session.id,
              user_input: prompt,
              session_service: session_service
            )
            Mcp.logger.debug("Agent run_task finished. Final event: #{final_event.inspect}")

            # 5. Process Result
            raise StandardError, "Agent task finished with unexpected event format: #{final_event.inspect}" unless final_event.is_a?(Legate::Event) && final_event.role == :agent && final_event.content.is_a?(Hash)

            result_content = final_event.content

            case result_content[:status]
            when :success
              result_content[:result] # Return result payload
            when :error
              err_msg = result_content[:error_message] || 'Agent execution failed.'
              Mcp.logger.error("Agent '#{agent_name}' execution failed: #{err_msg}")
              raise StandardError, "Agent Error: #{err_msg}"
            when :pending
              job_id = result_content[:job_id] # Assuming key is :job_id
              msg = result_content[:message] || 'Agent task resulted in a pending job.'
              Mcp.logger.warn("Agent '#{agent_name}' execution ended with pending status (Job: #{job_id}). Returning as structured data.")
              # Return pending structure similar to LegateToolAdapter for consistency
              { status: 'pending', job_id: job_id, message: msg }
            else
              raise StandardError, "Agent task finished with unknown status: #{result_content[:status]}"
            end
          rescue Legate::Mcp::Error, StandardError => e
            # Catch errors during setup or execution within the adapter
            Mcp.logger.error("Error during LegateAgentAdapter call for '#{agent_name}': #{e.class} - #{e.message}")
            Mcp.logger.error(e.backtrace.join("\n"))
            # Let fast-mcp handle the error
            raise StandardError, "Failed to run agent '#{agent_name}': #{e.message}"
          ensure
            # 6. Cleanup: Stop Agent & Delete Session
            if agent&.running?
              begin
                Mcp.logger.debug('Stopping ephemeral agent runtime...')
                agent.stop
              rescue StandardError => e
                Mcp.logger.error("Error stopping agent runtime during cleanup: #{e.message}")
              end
            end
            if temp_session && session_service
              begin
                Mcp.logger.debug("Deleting temporary session: #{temp_session.id}")
                session_service.delete_session(session_id: temp_session.id)
              rescue StandardError => e
                Mcp.logger.error("Error deleting temporary session #{temp_session.id}: #{e.message}")
              end
            end
          end
        end
      end
    end
  end
end
