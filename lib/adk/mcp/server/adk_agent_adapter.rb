# File: lib/adk/mcp/server/adk_agent_adapter.rb
# frozen_string_literal: true

require 'fast_mcp'
require 'redis' # Needed to load agent definition
require 'json' # Needed to parse tools
require 'securerandom'
require_relative '../../agent'
require_relative '../../tool_registry'
require_relative '../../session_service/base' # Need base for type check
require_relative '../../event' # Needed for result processing
require_relative '../error'
require_relative '../../global_tool_manager' # Added require

module ADK
  module Mcp
    module Server
      # (Experimental) Adapter to expose an entire ADK::Agent (defined in Redis)
      # as a single, simple tool via fast-mcp.
      # The agent runs ephemerally for each call
      class AdkAgentAdapter < FastMcp::Tool
        # --- Class Configuration --- Needs refinement if not using wrap ---
        # class_attribute :agent_definition_name, :session_service
        # Using class instance variables set by `wrap`
        class << self
          attr_reader :agent_definition_name, :session_service

          # --- Redis Helpers (mirrored from AgentCommands CLI for now) ---
          # TODO: Refactor these into a shared ADK::Util::RedisAgentLoader?
          def agent_redis_key(name)
            # Constants need to be defined or accessed carefully
            # Assuming default prefix for now
            redis_prefix = ENV.fetch('ADK_REDIS_AGENT_PREFIX', "adk:agent:")
            "#{redis_prefix}#{name}"
          end

          def connect_redis
            # Assumes ADK.redis_options are configured
            redis = Redis.new(ADK.redis_options)
            redis.ping
            redis
          rescue Redis::CannotConnectError => e
            Mcp.logger.error("AdkAgentAdapter: Could not connect to Redis. #{e.message}")
            raise ADK::Mcp::Error, "Redis connection failed: #{e.message}"
          end

          def parse_tools(tools_json)
            return [] unless tools_json && !tools_json.empty?

            JSON.parse(tools_json) rescue []
          end
          # --- End Redis Helpers ---
        end
        # -------------------------

        # Dynamically creates a new FastMcp::Tool subclass that wraps an ADK Agent definition.
        #
        # @param agent_definition_name [String] The name used to store the agent definition in Redis.
        # @param session_service_instance [ADK::SessionService::Base] The session service to use for temporary sessions.
        # @return [Class<AdkAgentAdapter>] A new anonymous class inheriting from AdkAgentAdapter.
        def self.wrap(agent_definition_name, session_service_instance)
          unless agent_definition_name.is_a?(String) && !agent_definition_name.empty?
            raise ArgumentError, "Agent definition name must be a non-empty String."
          end
          unless session_service_instance.is_a?(ADK::SessionService::Base)
            raise ArgumentError, "Session service instance must inherit from ADK::SessionService::Base."
          end

          # Create the anonymous adapter class
          adapter_class = Class.new(AdkAgentAdapter) do
            # Store config on the generated class
            @agent_definition_name = agent_definition_name
            @session_service = session_service_instance

            # Set fast-mcp tool metadata
            # Use a modified tool name to avoid clashes if agent name = tool name
            tool_name "run_agent_#{agent_definition_name}"
            description "Runs the ADK Agent '#{agent_definition_name}' with the given prompt."

            # Define the single prompt argument
            arguments do
              required(:prompt).filled(:string).description('The user input/prompt for the agent')
            end

            Mcp.logger.info("Created fast-mcp adapter for ADK agent definition: '#{agent_definition_name}'")
          end

          adapter_class
        end

        # Executes the wrapped ADK Agent for a single turn.
        # Loads definition, creates temp session, runs task, cleans up.
        #
        # @param prompt [String] The user prompt.
        # @return [Any] The final result payload from the agent's execution.
        # @raise [StandardError] If agent execution fails or returns an error status.
        def call(prompt:)
          # Retrieve config from the *class* instance variables
          agent_name = self.class.agent_definition_name
          session_service = self.class.session_service
          raise NotImplementedError,
                "AdkAgentAdapter must be configured using .wrap first." unless agent_name && session_service

          Mcp.logger.info("Executing ADK Agent '#{agent_name}' via MCP adapter with prompt: '#{prompt}'")

          agent = nil
          temp_session = nil
          begin
            # 1. Load Agent Definition from Redis
            Mcp.logger.debug("Loading agent definition '#{agent_name}' from Redis...")
            redis = self.class.connect_redis
            key = self.class.agent_redis_key(agent_name)
            redis_agent_data = redis.hmget(key, 'description', 'tools', 'model')
            description = redis_agent_data[0]
            tools_json_string = redis_agent_data[1]
            model_name = redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL

            unless description
              raise ADK::Mcp::Error, "Agent definition '#{agent_name}' not found in Redis."
            end

            Mcp.logger.debug("Agent definition loaded: Model=#{model_name}")

            # 2. Create Temporary Session
            Mcp.logger.debug("Creating temporary session...")
            temp_session = session_service.create_session(app_name: agent_name,
                                                          user_id: "mcp_temp_#{SecureRandom.hex(4)}")
            Mcp.logger.debug("Temporary session created: #{temp_session.id}")

            # 3. Instantiate Agent & Add Tools
            Mcp.logger.debug("Instantiating agent '#{agent_name}'...")
            # Extract tool classes from the definition
            tool_names_to_load = self.class.parse_tools(tools_json_string).map(&:to_sym)
            tool_classes_for_init = tool_names_to_load.map do |t_name|
              ADK::GlobalToolManager.find_class(t_name) # Use global registry to find classes
            end.compact

            if tool_classes_for_init.size != tool_names_to_load.size
              Mcp.logger.warn("Some tools defined for agent '#{agent_name}' were not found in the global ToolRegistry.")
            end

            agent = ADK::Agent.new(
              name: agent_name,
              description: description,
              model_name: model_name,
              tool_classes: tool_classes_for_init # Pass classes to agent initializer
            )

            # 4. Start Agent & Run Task
            Mcp.logger.debug("Starting ephemeral agent runtime...")
            agent.start
            Mcp.logger.debug("Running task in temp session #{temp_session.id}...")
            final_event = agent.run_task(
              session_id: temp_session.id,
              user_input: prompt,
              session_service: session_service
            )
            Mcp.logger.debug("Agent run_task finished. Final event: #{final_event.inspect}")

            # 5. Process Result
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
              job_id = result_content[:job_id] # Assuming key is :job_id
              msg = result_content[:message] || "Agent task resulted in a pending job."
              Mcp.logger.warn("Agent '#{agent_name}' execution ended with pending status (Job: #{job_id}). Returning as structured data.")
              # Return pending structure similar to AdkToolAdapter for consistency
              return { status: 'pending', job_id: job_id, message: msg }
            else
              raise StandardError, "Agent task finished with unknown status: #{result_content[:status]}"
            end
          rescue ADK::Mcp::Error, StandardError => e
            # Catch errors during setup or execution within the adapter
            Mcp.logger.error("Error during AdkAgentAdapter call for '#{agent_name}': #{e.class} - #{e.message}")
            Mcp.logger.error(e.backtrace.join("\n"))
            # Let fast-mcp handle the error
            raise StandardError, "Failed to run agent '#{agent_name}': #{e.message}"
          ensure
            # 6. Cleanup: Stop Agent & Delete Session
            if agent&.running?
              begin
                Mcp.logger.debug("Stopping ephemeral agent runtime...")
                agent.stop
              rescue StandardError => stop_e
                Mcp.logger.error("Error stopping agent runtime during cleanup: #{stop_e.message}")
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
