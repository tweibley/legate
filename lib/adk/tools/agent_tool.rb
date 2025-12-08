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

      parameter :use_calling_session,
                type: :boolean,
                description: 'If true, the target agent executes within the same session context as the caller. If false, a new isolated session is created. Defaults to false.',
                required: false

      private

      def perform_execution(params, context) # context is the ToolContext of the calling agent
        # Validate that the context has a valid tool registry
        unless context && context.respond_to?(:tool_registry) && context.tool_registry
          msg = "Tool registry not found or invalid in the provided context"
          ADK.logger.error("AgentTool: #{msg}")
          raise ADK::ToolError, msg
        end

        target_agent_name_str = params.fetch(:target_agent_name) do
          raise ADK::ToolArgumentError, 'Missing required parameter: target_agent_name'
        end.to_s # Ensure it's a string for store lookup

        task_to_delegate = params.fetch(:task) { raise ADK::ToolArgumentError, 'Missing required parameter: task' }
        use_calling_session = params.fetch(:use_calling_session, false)

        ADK.logger.info("AgentTool: Attempting to delegate task '#{task_to_delegate}' to agent '#{target_agent_name_str}' (Session reuse: #{use_calling_session})")

        # Load definition hash from the store
        definition_hash = ADK::AgentDefinitionStore.find(target_agent_name_str.to_sym) # Try memory first
        definition_hash ||= ADK::AgentDefinitionStore.load_from_redis(target_agent_name_str.to_sym) # Ensure symbol key for lookup

        unless definition_hash
          msg = "Target agent definition '#{target_agent_name_str}' could not be loaded from store."
          ADK.logger.error("AgentTool: #{msg}")
          raise ADK::ToolArgumentError, msg
        end

        # Ensure we have essential fields for a valid definition
        definition_hash = definition_hash.transform_keys(&:to_sym) if definition_hash.respond_to?(:transform_keys)

        # Ensure the definition has all required fields
        definition_hash[:name] = target_agent_name_str.to_sym unless definition_hash.key?(:name)
        definition_hash[:description] = definition_hash[:description] || "Delegated agent #{target_agent_name_str}"
        definition_hash[:instruction] = definition_hash[:instruction] || "Perform the delegated task: #{task_to_delegate}"

        # Handle 'tools' field: parse if JSON string, convert to array of symbols
        if definition_hash.key?(:tools)
          tool_array = if definition_hash[:tools].is_a?(String)
                         begin
                           parsed = JSON.parse(definition_hash[:tools])
                           parsed.is_a?(Array) ? parsed : []
                         rescue JSON::ParserError
                           ADK.logger.warn("AgentTool: Could not parse :tools JSON for agent '#{target_agent_name_str}'. Defaulting to empty tools array.")
                           []
                         end
                       else
                         Array(definition_hash[:tools])
                       end

          # Convert to symbols for the definition
          definition_hash[:tools] = tool_array.map(&:to_sym)
        elsif !definition_hash.key?(:tool_names) # Ensure some form of tools field exists
          definition_hash[:tools] = []
        end

        # Handle 'mcp_servers_json' field: if present and no mcp_servers, rename
        if definition_hash.key?(:mcp_servers_json) && !definition_hash.key?(:mcp_servers)
          definition_hash[:mcp_servers] = definition_hash.delete(:mcp_servers_json)
        end

        # Ensure fallback_mode is symbolized
        if definition_hash[:fallback_mode].is_a?(String)
          definition_hash[:fallback_mode] = definition_hash[:fallback_mode].to_sym
        end

        # Convert hash to an ADK::AgentDefinition object
        target_definition_object = ADK::AgentDefinition.from_hash(definition_hash)

        unless target_definition_object
          msg = "Failed to create a valid AgentDefinition object for target '#{target_agent_name_str}' from loaded hash."
          ADK.logger.error("AgentTool: #{msg} Hash was: #{definition_hash.inspect}")
          raise ADK::ToolError, msg # More generic error as it's post-load
        end

        ADK.logger.debug("AgentTool: Instantiating target agent '#{target_definition_object.name}' using its definition object.")

        # Determine session service and session ID to use
        delegate_session_service = nil
        delegate_session_id = nil

        if use_calling_session
          if context.session_service
            delegate_session_service = context.session_service
            delegate_session_id = context.session_id
            ADK.logger.debug("AgentTool: Reusing session service and session ID '#{delegate_session_id}' from caller.")
          else
            ADK.logger.warn("AgentTool: use_calling_session is true but context has no session_service. Falling back to new isolated session.")
          end
        end

        # Fallback if reuse failed or not requested
        unless delegate_session_service
          delegate_session_service = ADK::SessionService::InMemory.new
          # Create a new session
          new_session = delegate_session_service.create_session(
            app_name: target_definition_object.name.to_s,
            user_id: "delegation_#{SecureRandom.hex(4)}"
          )
          delegate_session_id = new_session.id
          ADK.logger.debug("AgentTool: Created new isolated session '#{delegate_session_id}' for target agent.")
        end

        # Create the ephemeral agent using its definition object
        target_agent = ADK::Agent.new(
          definition: target_definition_object,
          session_service: delegate_session_service
        )

        # Check if tools are configured for this agent
        if target_definition_object.tool_names.empty?
          ADK.logger.warn("AgentTool: Target agent '#{target_agent_name_str}' has no tools configured.")
        end

        # Register tools - get the class objects for each tool name and register with the agent
        tool_names = Array(definition_hash[:tools] || definition_hash[:tool_names] || [])
        tool_names.each do |tool_name|
          tool_class = ADK::GlobalToolManager.find_class(tool_name.to_sym)
          if tool_class
            target_agent.register_tool_class(tool_class)
            ADK.logger.debug("AgentTool: Registered tool '#{tool_name}' with target agent.")
          else
            ADK.logger.warn("AgentTool: Could not find tool class for '#{tool_name}' in GlobalToolManager.")
          end
        end

        target_agent.start
        ADK.logger.info("AgentTool: Running task '#{task_to_delegate}' on target agent '#{target_agent.name}' (Session: #{delegate_session_id})")

        agent_event = target_agent.run_task(
          session_id: delegate_session_id,
          user_input: task_to_delegate,
          session_service: delegate_session_service # Pass the correct service
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
