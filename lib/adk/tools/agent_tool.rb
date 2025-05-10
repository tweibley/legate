# File: lib/adk/tools/agent_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative '../agent'
# ToolRegistry is NOT needed directly by AgentTool for loading target tools
# require_relative '../tool_registry'
require_relative '../session'
require_relative '../session_service/in_memory'
require 'json'
require 'securerandom'
require_relative '../agent_definition_store'
require_relative '../global_tool_manager' # Make sure this is required

module ADK
  module Tools
    class AgentTool < ADK::Tool
      self.explicit_tool_name = :delegate_task

      tool_description 'Delegates a specified task to another agent identified by its unique name. Use this when a specific agent is better suited for the sub-task.'

      parameter :target_agent_name,
                type: :string,
                description: 'The unique name of the agent definition to delegate the task to.',
                required: true

      parameter :task,
                type: :string,
                description: 'The specific task description to be executed by the target agent.',
                required: true

      private

      def perform_execution(params, context) # context is the ToolContext of the calling agent
        target_agent_name_str = params.fetch(:target_agent_name) do
          raise ADK::ToolArgumentError, 'Missing required parameter: target_agent_name'
        end.to_s # Ensure it's a string for store lookup

        task_to_delegate = params.fetch(:task) { raise ADK::ToolArgumentError, 'Missing required parameter: task' }

        ADK.logger.info("AgentTool: Attempting to delegate task '#{task_to_delegate}' to agent '#{target_agent_name_str}'")

        target_definition = ADK::AgentDefinitionStore.find(target_agent_name_str.to_sym) # Try memory first
        target_definition ||= ADK::AgentDefinitionStore.load_from_redis(target_agent_name_str)

        unless target_definition
          msg = "Target agent definition '#{target_agent_name_str}' not found."
          ADK.logger.error("AgentTool: #{msg}") # Log before raising
          raise ADK::ToolArgumentError, msg
        end

        target_description = target_definition[:description]
        target_tool_names = target_definition[:tools].map(&:to_sym) # From store, ensure symbols
        target_model = target_definition[:model]
        target_instruction = target_definition[:instruction] # Get instruction

        ADK.logger.debug("AgentTool: Instantiating target agent '#{target_agent_name_str}' with model '#{target_model}'")

        # Create the ephemeral agent. It will get its own fresh ToolRegistry.
        # Pass instruction to the new agent instance.
        target_agent = ADK::Agent.new(
          name: "#{target_agent_name_str}_delegated_#{SecureRandom.hex(4)}",
          description: target_description,
          model_name: target_model,
          instruction: target_instruction # Pass instruction here
          # Do NOT pass tool_classes or selected_tool_names here initially,
          # tools will be added from its definition below.
        )

        ADK.logger.debug("AgentTool: Adding tools #{target_tool_names.inspect} to target agent '#{target_agent.name}'")
        if target_tool_names.empty?
          ADK.logger.warn("AgentTool: Target agent '#{target_agent_name_str}' has no tools configured in its definition.")
        else
          target_tool_names.each do |tool_name_sym|
            # --- MODIFICATION: Look up tool class in GlobalToolManager ---
            tool_class = ADK::GlobalToolManager.find_class(tool_name_sym)
            if tool_class
              # Register the class with the target_agent's specific registry
              target_agent.register_tool_class(tool_class)
              ADK.logger.debug("AgentTool: Added tool '#{tool_name_sym}' (class: #{tool_class}) to target agent '#{target_agent.name}'.")
            else
              ADK.logger.warn("AgentTool: Tool '#{tool_name_sym}' (needed by '#{target_agent_name_str}') not found in GlobalToolManager. Skipping for target agent.")
            end
            # --- END MODIFICATION ---
          end
        end

        session_service = ADK::SessionService::InMemory.new
        delegate_session = session_service.create_session(
          app_name: target_agent_name_str, # Use string name for app_name consistency
          user_id: "delegation_#{SecureRandom.hex(4)}"
        )
        session_id = delegate_session.id
        ADK.logger.debug("AgentTool: Created delegation session #{session_id} for target agent")

        target_agent.start
        ADK.logger.info("AgentTool: Running task '#{task_to_delegate}' on target agent '#{target_agent.name}'")

        agent_event = target_agent.run_task(
          session_id: session_id,
          user_input: task_to_delegate,
          session_service: session_service
        )

        target_result = agent_event.respond_to?(:content) ? agent_event.content : agent_event
        ADK.logger.info("AgentTool: Target agent '#{target_agent.name}' finished task. Result: #{target_result.inspect}")

        { status: :success, result: target_result }
      rescue ADK::ToolArgumentError => e
        ADK.logger.error("AgentTool ArgumentError: #{e.message}")
        raise e
      rescue ADK::ToolError => e
        ADK.logger.error("AgentTool ToolError: #{e.message}")
        raise e
      rescue StandardError => e
        msg = "AgentTool: Unexpected error during delegation to '#{target_agent_name_str}': #{e.class} - #{e.message}"
        ADK.logger.error(msg)
        ADK.logger.error(e.backtrace.first(5).join("\n"))
        raise ADK::ToolError, msg
      end # end perform_execution
    end # End AgentTool class
  end # End Tools module
end # End ADK module
