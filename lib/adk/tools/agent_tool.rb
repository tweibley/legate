# File: lib/adk/tools/agent_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative '../agent'
require_relative '../tool_registry'
require_relative '../session'
require_relative '../session_service/in_memory'
require 'json'
require 'securerandom'
require_relative '../agent_definition_store'

module ADK
  module Tools
    # A tool that allows an agent to delegate a task to another agent definition.
    # It loads the target agent's definition (via AgentDefinitionStore), instantiates it ephemerally,
    # adds its configured tools, runs the specified task, and returns the result.
    class AgentTool < ADK::Tool
      # --- New DSL Metadata ---
      # Name will be inferred as :agent_tool
      self.explicit_tool_name = :delegate_task # Keep the original name

      tool_description 'Delegates a specified task to another agent identified by its unique name. Use this when a specific agent is better suited for the sub-task.'

      parameter :target_agent_name,
                type: :string,
                description: 'The unique name of the agent definition to delegate the task to.',
                required: true

      parameter :task,
                type: :string,
                description: 'The specific task description to be executed by the target agent.',
                required: true
      # --- End New DSL Metadata ---

      private

      # Performs the delegation logic.
      def perform_execution(params, context)
        target_agent_name = params.fetch(:target_agent_name) {
          raise ADK::ToolArgumentError, "Missing required parameter: target_agent_name"
        }
        task_to_delegate = params.fetch(:task) { raise ADK::ToolArgumentError, "Missing required parameter: task" }

        ADK.logger.info("AgentTool: Attempting to delegate task '#{task_to_delegate}' to agent '#{target_agent_name}'")

        # 1. Load Target Agent Definition using AgentDefinitionStore
        # First, try the in-memory store. If not found, try loading from Redis.
        target_definition = ADK::AgentDefinitionStore.find(target_agent_name)
        target_definition ||= ADK::AgentDefinitionStore.load_from_redis(target_agent_name)

        unless target_definition
          msg = "Target agent definition '#{target_agent_name}' not found."
          ADK.logger.error("AgentTool Argument Error: #{msg}")
          raise ADK::ToolArgumentError, msg
        end

        # Extract definition details
        target_description = target_definition[:description]
        # AgentDefinitionStore ensures tools is an array of strings
        target_tool_names = target_definition[:tools].map(&:to_sym)
        target_model = target_definition[:model] # Already defaulted by store if nil

        # 2. Instantiate Target Agent (Ephemeral Instance)
        ADK.logger.debug("AgentTool: Instantiating target agent '#{target_agent_name}' with model '#{target_model}'")
        target_agent = ADK::Agent.new(
          name: "#{target_agent_name}_delegated_#{SecureRandom.hex(4)}",
          description: target_description,
          model_name: target_model
          # Do NOT pass tool_classes here, add them manually below
        )

        # 3. Add Tools to Target Agent Instance
        executing_agent_registry = context&.tool_registry
        unless executing_agent_registry && executing_agent_registry.respond_to?(:find_class)
          msg = "AgentTool: Tool registry not found or invalid in current context. Cannot load tools for target agent."
          ADK.logger.error(msg)
          raise ADK::ToolError, msg
        end

        if target_tool_names.empty?
          ADK.logger.warn("AgentTool: Target agent '#{target_agent_name}' has no tools configured in its definition.")
        else
          ADK.logger.debug("AgentTool: Adding tools #{target_tool_names} to target agent")
          target_tool_names.each do |tool_name|
            # Find tool class in the *executing* agent's registry
            tool_class = executing_agent_registry.find_class(tool_name)
            if tool_class
              target_agent.register_tool_class(tool_class)
            else
              ADK.logger.warn("AgentTool: Tool '#{tool_name}' (needed by '#{target_agent_name}') not found in executing agent's ToolRegistry. Skipping.")
            end
          end
        end

        # 4. Create Session Service and Session for delegation
        session_service = ADK::SessionService::InMemory.new # Keep ephemeral session
        delegate_session = session_service.create_session(
          app_name: target_agent_name,
          user_id: "delegation_#{SecureRandom.hex(4)}"
        )
        session_id = delegate_session.id
        ADK.logger.debug("AgentTool: Created delegation session #{session_id} for target agent")

        # 5. Start and Execute Task on Target Agent
        target_agent.start # Start the ephemeral instance
        ADK.logger.info("AgentTool: Running task '#{task_to_delegate}' on target agent '#{target_agent_name}'")

        agent_event = target_agent.run_task(
          session_id: session_id,
          user_input: task_to_delegate,
          session_service: session_service
        )

        # Use respond_to? to handle actual Events and mocks/doubles consistently
        target_result = agent_event.respond_to?(:content) ? agent_event.content : agent_event

        ADK.logger.info("AgentTool: Target agent '#{target_agent_name}' finished task. Result: #{target_result.inspect}")

        # 6. Return Result (wrapping the target's result)
        { status: :success, result: target_result }

      # --- Error Handling ---
      rescue ADK::ToolArgumentError => e
        raise e # Re-raise
      rescue ADK::ToolError => e
        raise e # Re-raise
      rescue StandardError => e
        msg = "AgentTool: Unexpected error during delegation to '#{target_agent_name}': #{e.class} - #{e.message}"
        ADK.logger.error(msg)
        ADK.logger.error(e.backtrace.first(5).join("\n"))
        raise ADK::ToolError, msg # Wrap
      end # end perform_execution
    end # End AgentTool class
  end # End Tools module
end # End ADK module
