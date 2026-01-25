# frozen_string_literal: true

module ADK
  # Manages the loading and registration of ADK's built-in tools.
  module BuiltinTools
    def self.load_and_register_all
      load_tools
      register_tools
    end

    def self.load_tools
      require_relative 'tools/echo'
      require_relative 'tools/calculator'
      require_relative 'tools/cat_facts'
      require_relative 'tools/random_number_tool'
      require_relative 'tools/agent_tool' # Tool that allows an agent to call another agent
      require_relative 'tools/base_async_job_tool' # Base class for tools that run asynchronously
      require_relative 'tools/check_job_status_tool' # Tool to check the status of async jobs
      require_relative 'tools/sleepy_tool' # Example async tool
      require_relative 'tools/webhook_tool' # Added webhook_tool here
    end

    def self.register_tools
      ADK.logger.info 'Explicitly registering built-in ADK tools...'
      [
        ADK::Tools::Echo,
        ADK::Tools::Calculator,
        ADK::Tools::CatFacts,
        ADK::Tools::RandomNumberTool,
        ADK::Tools::AgentTool, # Ensure this is registered
        ADK::Tools::CheckJobStatusTool,
        ADK::Tools::SleepyTool,
        ADK::Tools::WebhookTool
        # ADK::Tools::BaseAsyncJobTool should NOT be registered as it's abstract
      ].each do |tool_klass|
        if tool_klass.respond_to?(:abstract?) && tool_klass.abstract?
          ADK.logger.debug "Skipping explicit registration of abstract tool: #{tool_klass}"
        else
          ADK::GlobalToolManager.register_tool(tool_klass)
        end
      end
      ADK.logger.info "Explicit tool registration complete. Current global tools: #{ADK::GlobalToolManager.registered_tool_names.inspect}"
    end
  end
end
