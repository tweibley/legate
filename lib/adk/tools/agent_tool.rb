# File: lib/adk/tools/agent_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative '../agent'
require_relative '../tool_registry'
require_relative '../session'
require_relative '../session_service/in_memory'
require 'redis'
require 'json'
require 'securerandom' # Required for SecureRandom

module ADK
  module Tools
    # A tool that allows an agent to delegate a task to another agent definition.
    # It loads the target agent's definition from Redis, instantiates it ephemerally,
    # adds its configured tools, runs the specified task, and returns the result.
    class AgentTool < ADK::Tool
      # --- Define Metadata ---
      # Describes how the planner should use this tool.
      define_metadata(
        name: :delegate_task,
        description: 'Delegates a specified task to another agent identified by its unique name. Use this when a specific agent is better suited for the sub-task.',
        parameters: {
          target_agent_name: {
            type: :string,
            description: 'The unique name of the agent definition to delegate the task to.',
            required: true
          },
          task: {
            type: :string,
            description: 'The specific task description to be executed by the target agent.',
            required: true
          }
        }
      )
      # --- End Metadata ---

      # Constant for Redis key prefix. Consider centralizing if used elsewhere besides CLI.
      REDIS_AGENT_HASH_PREFIX = "adk:agent:"

      # Initializes the AgentTool. No specific instance variables needed currently.
      def initialize(**options)
        super(**options)
      end

      private

      # Helper to generate the Redis HASH key for an agent definition.
      # @param name [String] The name of the agent.
      # @return [String] The Redis key.
      def agent_redis_key(name)
        "#{REDIS_AGENT_HASH_PREFIX}#{name}"
      end

      # Performs the delegation logic.
      # Fetches target agent details from Redis, instantiates it, runs the task,
      # and returns the result within the standard hash format.
      #
      # @param params [Hash] Parameters provided by the planner's step.
      #                      Expected keys: :target_agent_name, :task (as Symbols).
      # @param _context [ADK::ToolContext, nil] The execution context (unused here, but session context is passed implicitly through service).
      # @return [Hash] A hash with :status (:success or :error) and :result or :error_message.
      def perform_execution(params, _context)
        # Fetch required parameters using symbols (matching planner output)
        target_agent_name = params.fetch(:target_agent_name)
        task_to_delegate = params.fetch(:task)

        redis = nil # Initialize outside begin block for potential error messages
        ADK.logger.info("AgentTool: Attempting to delegate task '#{task_to_delegate}' to agent '#{target_agent_name}'")

        # 1. Connect to Redis
        begin
          redis = Redis.new # Assumes default connection: localhost:6379
          redis.ping # Verify connection
        rescue Redis::CannotConnectError => e
          msg = "AgentTool: Could not connect to Redis to load target agent. #{e.message}"
          ADK.logger.error(msg)
          return { status: :error, error_message: msg }
        end

        # 2. Load Target Agent Definition from Redis
        target_key = agent_redis_key(target_agent_name)
        target_data = redis.hmget(target_key, 'description', 'tools', 'model')
        target_description = target_data[0]
        target_tools_json = target_data[1] # String or nil
        target_model = target_data[2] || ADK::Agent::DEFAULT_MODEL # Default if not set

        # Check if the definition was found
        unless target_description
          msg = "AgentTool: Target agent definition '#{target_agent_name}' not found in Redis."
          ADK.logger.error(msg)
          return { status: :error, error_message: msg }
        end

        # 3. Parse Target Agent's Tools JSON Safely
        # This block now handles parsing and raises a specific error if needed
        parsed_tool_list = nil
        begin
          if target_tools_json && !target_tools_json.empty? && target_tools_json != '[]'
            parsed_tool_list = JSON.parse(target_tools_json)
            # Ensure it's an array after parsing
            unless parsed_tool_list.is_a?(Array)
              raise JSON::ParserError, "Tools JSON did not parse into an Array"
            end
          else
            parsed_tool_list = [] # Treat nil, empty, or '[]' as empty list
          end
        rescue JSON::ParserError => e
          # Raise specific error if parsing failed on potentially valid JSON string
          raise JSON::ParserError,
                "Failed to parse tools JSON for target agent '#{target_agent_name}'. Invalid JSON: #{target_tools_json.inspect}. Error: #{e.message}"
        end
        target_tool_names = parsed_tool_list.map(&:to_sym) # Convert names to symbols

        # 4. Instantiate Target Agent (Ephemeral Instance)
        ADK.logger.debug("AgentTool: Instantiating target agent '#{target_agent_name}' with model '#{target_model}'")
        # Create with a temporary, unique runtime name
        target_agent = ADK::Agent.new(
          name: "#{target_agent_name}_delegated_#{SecureRandom.hex(4)}",
          description: target_description,
          model_name: target_model
          # Note: Does not inherit the calling agent's logger, memory, or session state
        )

        # 5. Add Tools to Target Agent Instance
        if target_tool_names.empty?
          ADK.logger.warn("AgentTool: Target agent '#{target_agent_name}' has no tools configured (or tools JSON was invalid).")
        else
          ADK.logger.debug("AgentTool: Adding tools #{target_tool_names} to target agent")
          target_tool_names.each do |tool_name|
            tool_instance = ADK::ToolRegistry.create_instance(tool_name)
            if tool_instance
              target_agent.add_tool(tool_instance)
            else
              # Log warning but continue, agent might function with subset of tools
              ADK.logger.warn("AgentTool: Tool '#{tool_name}' configured for target agent '#{target_agent_name}' not found in ToolRegistry. Skipping.")
            end
          end
        end

        # 6. Create Session Service and Session for delegation
        session_service = ADK::SessionService::InMemory.new
        delegate_session = session_service.create_session(
          app_name: target_agent_name,
          user_id: "delegation_#{SecureRandom.hex(4)}"
        )
        session_id = delegate_session.id
        ADK.logger.debug("AgentTool: Created delegation session #{session_id} for target agent")

        # 7. Start and Execute Task on Target Agent
        target_agent.start # Start the ephemeral instance
        ADK.logger.info("AgentTool: Running task '#{task_to_delegate}' on target agent '#{target_agent_name}'")

        # Use the new session-based interface
        agent_event = target_agent.run_task(
          session_id: session_id,
          user_input: task_to_delegate,
          session_service: session_service
        )

        # Extract content from the agent event
        target_result = agent_event.is_a?(ADK::Event) ? agent_event.content : agent_event

        ADK.logger.info("AgentTool: Target agent '#{target_agent_name}' finished task. Result: #{target_result.inspect}")

        # 8. Return Result (wrapping the target's result)
        { status: :success, result: target_result }

      # --- Error Handling for perform_execution ---
      rescue KeyError => e # Specific rescue for params.fetch failure
        msg = "AgentTool: Missing required parameter in plan step: #{e.key}"
        ADK.logger.error(msg)
        { status: :error, error_message: msg }
      rescue JSON::ParserError => e # Catch the re-raised parser error from Step 3
        # The message was already constructed informatively
        msg = e.message
        ADK.logger.error(msg)
        { status: :error, error_message: msg }
      rescue StandardError => e # Catch other unexpected errors
        # Use target_agent_name if it was assigned, otherwise indicate unknown
        effective_target_name = defined?(target_agent_name) && target_agent_name ? "'#{target_agent_name}'" : '(unknown target)'
        msg = "AgentTool: Unexpected error during delegation to #{effective_target_name}: #{e.class} - #{e.message}"
        ADK.logger.error(msg)
        ADK.logger.error(e.backtrace.first(5).join("\n")) # Log part of backtrace for context
        { status: :error, error_message: msg }
      end # end perform_execution
    end # End AgentTool class
  end # End Tools module
end # End ADK module
