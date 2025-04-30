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
      def perform_execution(params, context)
        # Fetch required parameters using symbols (matching planner output)
        begin
          target_agent_name = params.fetch(:target_agent_name)
          task_to_delegate = params.fetch(:task)
        rescue KeyError => e
          msg = "Missing required parameter in plan step: #{e.key}"
          ADK.logger.error("AgentTool Argument Error: #{msg}")
          raise ADK::ToolArgumentError, msg
        end

        redis = nil # Initialize outside begin block for potential error messages
        ADK.logger.info("AgentTool: Attempting to delegate task '#{task_to_delegate}' to agent '#{target_agent_name}'")

        # 1. Connect to Redis
        begin
          redis = Redis.new(ADK.redis_options) # Use configured options
          redis.ping # Verify connection
        rescue Redis::BaseError => e # Catch specific Redis errors
          msg = "AgentTool: Could not connect to Redis to load target agent. #{e.message}"
          ADK.logger.error(msg)
          raise ADK::ToolError, msg
        end

        # 2. Load Target Agent Definition from Redis
        target_key = agent_redis_key(target_agent_name)
        target_data = redis.hmget(target_key, 'description', 'tools', 'model')
        target_description = target_data[0]
        target_tools_json = target_data[1] # String or nil
        target_model = target_data[2] || ADK::Agent::DEFAULT_MODEL # Default if not set

        # Check if the definition was found
        unless target_description
          msg = "Target agent definition '#{target_agent_name}' not found in Redis."
          ADK.logger.error("AgentTool Argument Error: #{msg}")
          raise ADK::ToolArgumentError, msg
        end

        # 3. Parse Target Agent's Tools JSON Safely
        parsed_tool_list = nil
        begin
          if target_tools_json && !target_tools_json.empty? && target_tools_json != '[]'
            parsed_tool_list = JSON.parse(target_tools_json)
            unless parsed_tool_list.is_a?(Array)
              raise JSON::ParserError, "Tools JSON did not parse into an Array"
            end
          else
            parsed_tool_list = [] # Treat nil, empty, or '[]' as empty list
          end
        rescue JSON::ParserError => e
          msg = "Failed to parse tools JSON for target agent '#{target_agent_name}'. Invalid JSON: #{target_tools_json.inspect}. Error: #{e.message}"
          ADK.logger.error("AgentTool Argument Error: #{msg}")
          raise ADK::ToolArgumentError, msg
        end
        target_tool_names = parsed_tool_list.map(&:to_sym) # Convert names to symbols

        # 4. Instantiate Target Agent (Ephemeral Instance)
        ADK.logger.debug("AgentTool: Instantiating target agent '#{target_agent_name}' with model '#{target_model}'")
        target_agent = ADK::Agent.new(
          name: "#{target_agent_name}_delegated_#{SecureRandom.hex(4)}",
          description: target_description,
          model_name: target_model
        )

        # 5. Add Tools to Target Agent Instance
        executing_agent_registry = context&.tool_registry
        unless executing_agent_registry && executing_agent_registry.respond_to?(:find_class)
          msg = "AgentTool: Tool registry not found or does not respond to :find_class in context. Cannot load tools for target agent '#{target_agent_name}'."
          ADK.logger.error(msg)
          raise ADK::ToolError, msg
        end

        if target_tool_names.empty?
          ADK.logger.warn("AgentTool: Target agent '#{target_agent_name}' has no tools configured (or tools JSON was invalid).")
        else
          ADK.logger.debug("AgentTool: Adding tools #{target_tool_names} to target agent")
          target_tool_names.each do |tool_name|
            tool_class = executing_agent_registry.find_class(tool_name)
            if tool_class
              target_agent.register_tool_class(tool_class)
            else
              ADK.logger.warn("AgentTool: Tool '#{tool_name}' configured for target agent '#{target_agent_name}' not found in executing agent's ToolRegistry. Skipping.")
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

        agent_event = target_agent.run_task(
          session_id: session_id,
          user_input: task_to_delegate,
          session_service: session_service
        )

        target_result = agent_event.is_a?(ADK::Event) ? agent_event.content : agent_event

        ADK.logger.info("AgentTool: Target agent '#{target_agent_name}' finished task. Result: #{target_result.inspect}")

        # 8. Return Result (wrapping the target's result)
        { status: :success, result: target_result }

      # --- Error Handling for perform_execution ---
      rescue ADK::ToolArgumentError => e # Catch specific argument errors (raised above)
        raise e # Re-raise to be handled by agent
      rescue ADK::ToolError => e # Catch specific tool errors (raised above)
        raise e # Re-raise to be handled by agent
      rescue StandardError => e # Catch other unexpected errors during the process
        msg = "AgentTool: Unexpected error during delegation to '#{target_agent_name}': #{e.class} - #{e.message}"
        ADK.logger.error(msg)
        ADK.logger.error(e.backtrace.first(5).join("\n"))
        raise ADK::ToolError, msg # Wrap unexpected errors
      end # end perform_execution
    end # End AgentTool class
  end # End Tools module
end # End ADK module
