# File: lib/adk/tools/agent_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative '../agent'
require_relative '../tool_registry'
require 'redis'
require 'json'
require 'securerandom' # <-- Added require for SecureRandom

module ADK
  module Tools
    class AgentTool < ADK::Tool
      # ... (define_metadata, constants, initialize) ...
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
      REDIS_AGENT_HASH_PREFIX = "adk:agent:"
      def initialize(**options)
        super(**options)
      end

      private

      # ... (agent_redis_key, parse_tools helpers) ...
      def agent_redis_key(name)
        "#{REDIS_AGENT_HASH_PREFIX}#{name}"
      end

      def parse_tools(tools_json)
        return [] unless tools_json && !tools_json.empty?

        JSON.parse(tools_json) rescue []
      end

      def perform_execution(params)
        # --- Fetch parameters using SYMBOLS ---
        target_agent_name = params.fetch(:target_agent_name)
        task_to_delegate = params.fetch(:task)
        # --- End Symbol Fetch ---

        redis = nil
        ADK.logger.info("AgentTool: Attempting to delegate task '#{task_to_delegate}' to agent '#{target_agent_name}'")

        # 1. Connect to Redis
        begin
          redis = Redis.new
          redis.ping
        rescue Redis::CannotConnectError => e
          msg = "AgentTool: Could not connect to Redis. #{e.message}"
          ADK.logger.error(msg)
          return { status: :error, error_message: msg }
        end

        # 2. Load Target Agent Definition
        target_key = agent_redis_key(target_agent_name)
        target_data = redis.hmget(target_key, 'description', 'tools', 'model')
        target_description = target_data[0]
        target_tools_json = target_data[1]
        target_model = target_data[2] || ADK::Agent::DEFAULT_MODEL

        unless target_description
          msg = "AgentTool: Target agent definition '#{target_agent_name}' not found in Redis."
          ADK.logger.error(msg)
          return { status: :error, error_message: msg }
        end

        # 3. Instantiate Target Agent
        ADK.logger.debug("AgentTool: Instantiating target agent '#{target_agent_name}' with model '#{target_model}'")
        target_agent = ADK::Agent.new(
          name: "#{target_agent_name}_delegated_#{SecureRandom.hex(4)}",
          description: target_description,
          model_name: target_model
        )

        # 4. Add Tools to Target Agent
        target_tool_names = parse_tools(target_tools_json).map(&:to_sym)
        if target_tool_names.empty?
          ADK.logger.warn("AgentTool: Target agent '#{target_agent_name}' has no tools configured.")
        else
          ADK.logger.debug("AgentTool: Adding tools #{target_tool_names} to target agent")
          target_tool_names.each do |tool_name|
            tool_instance = ADK::ToolRegistry.create_instance(tool_name)
            if tool_instance then target_agent.add_tool(tool_instance);
            else ADK.logger.warn("AgentTool: Tool '#{tool_name}' not found in ToolRegistry."); end
          end
        end

        # 5. Start and Execute Task on Target Agent
        target_agent.start
        ADK.logger.info("AgentTool: Running task '#{task_to_delegate}' on target agent '#{target_agent_name}'")
        target_result = target_agent.run_task(task_to_delegate)
        ADK.logger.info("AgentTool: Target agent '#{target_agent_name}' finished task. Result: #{target_result.inspect}")

        # 6. Return Result
        { status: :success, result: target_result }
      rescue KeyError => e # Specific rescue for fetch failure
        msg = "AgentTool: Missing required parameter in plan step: #{e.key}"
        ADK.logger.error(msg)
        { status: :error, error_message: msg }
      rescue JSON::ParserError => e
        msg = "AgentTool: Failed to parse tools JSON for target agent '#{target_agent_name}'. #{e.message}"
        ADK.logger.error(msg)
        { status: :error, error_message: msg }
      rescue StandardError => e
        # Use target_agent_name if available, otherwise use what was fetched (might be nil)
        effective_target_name = defined?(target_agent_name) && target_agent_name ? "'#{target_agent_name}'" : '(unknown target)'
        msg = "AgentTool: Unexpected error during delegation to #{effective_target_name}: #{e.class} - #{e.message}"
        ADK.logger.error(msg)
        ADK.logger.error(e.backtrace.first(5).join("\n"))
        { status: :error, error_message: msg }
      end
    end # End AgentTool class
  end # End Tools module
end # End ADK module
