# File: lib/adk/agent.rb
# frozen_string_literal: true

require 'logger'
require 'concurrent'
require_relative 'tool_context'
require 'sidekiq' # Ensure sidekiq is required if needed here
# Note: Requires are handled by lib/adk.rb
require_relative 'planner'
require_relative 'tool_registry'
require_relative 'mcp/client'
require_relative 'mcp/tool_wrapper'


module ADK
  class Error < StandardError; end unless defined?(ADK::Error)

  # Agent class represents an AI agent that can perform tasks using tools and a planner.
  # It operates within the context of a session managed by a SessionService.
  class Agent
    DEFAULT_MODEL = 'gemini-2.0-flash'

    attr_reader :name, :description, :planner, :logger, :model_name, :state, :tool_registry, :fallback_mode

    # Initializes a new agent instance.
    # Note: Session and Memory are no longer managed directly by the agent instance.
    #
    # @param name [String] The unique name of the agent definition.
    # @param description [String] A description of the agent's purpose.
    # @param model_name [String, nil] The specific LLM model name (optional).
    # @param tool_classes [Array<Class>] An initial list of native tool *classes* (must inherit from ADK::Tool).
    # @param planner [ADK::Planner] A specific planner instance (default: created automatically).
    # @param mcp_servers [Array<Hash>] Optional configurations for external MCP servers.
    #        Example: [{ type: :stdio, command: 'cmd', args: [] }]
    # @param fallback_mode [Symbol] Behavior when planning fails (:error or :echo). Default: :error
    def initialize(name:, description:, model_name: nil, tool_classes: [], planner: nil, mcp_servers: [],
                   fallback_mode: :error)
      ADK.logger.info("Initializing agent '#{name}'...")
      @name = name
      @description = description
      @model_name = model_name || DEFAULT_MODEL
      @fallback_mode = fallback_mode == :echo ? :echo : :error # Ensure only valid modes
      @state = :idle # Initial state
      @mcp_servers_config = mcp_servers # Store MCP configurations
      @mcp_clients = [] # Store active MCP client instances

      # Each agent instance gets its own registry
      @tool_registry = ADK::ToolRegistry.new
      ADK.logger.debug("Agent '#{name}' created its ToolRegistry instance: #{@tool_registry.object_id}")

      # Register initial native tool classes
      tool_classes.each { |tool_class| register_tool_class(tool_class) }

      # Automatically register the CheckJobStatusTool class if Sidekiq is defined
      if defined?(Sidekiq)
        unless @tool_registry.find_class(:check_job_status)
          begin
            require_relative 'tools/check_job_status_tool' # Ensure loaded
            register_tool_class(ADK::Tools::CheckJobStatusTool)
          rescue LoadError => e
            ADK.logger.error("Failed to load CheckJobStatusTool: #{e.message}")
          end
        end
      else
        ADK.logger.warn("Sidekiq not defined. Skipping automatic registration of CheckJobStatusTool for agent '#{name}'.")
      end

      @planner = planner || ADK::Planner.new(agent: self, model_name: @model_name)

      ADK.logger.info("Agent '#{name}' initialized successfully with tools: #{@tool_registry.tools.keys.join(', ')}")
    end

    # Adds a tool instance to the agent's registry
    # @param tool [ADK::Tool] The tool instance to add
    # @return [Boolean] True if the tool was added, false otherwise
    def add_tool(tool)
      # Check if it's a valid tool instance or class
      is_tool_instance = tool.is_a?(ADK::Tool)
      is_tool_class = tool.is_a?(Class) && tool < ADK::Tool

      unless is_tool_instance || is_tool_class
        ADK.logger.error("Agent '#{name}': Attempted to add invalid tool: #{tool.inspect}")
        return false
      end

      # Get the tool name, handling both instances and classes
      tool_name = is_tool_class ? tool.tool_name : tool.name
      tool_name = tool_name.to_sym

      if @tool_registry.find_class(tool_name)
        ADK.logger.warn("Agent '#{name}': Tool '#{tool_name}' already added. Overwriting.")
      end

      # If it's a class, register it directly. If it's an instance, register its class
      tool_class = is_tool_class ? tool : tool.class
      @tool_registry.register(tool_name, tool_class)
      true
    end

    # Returns the list of tools registered with this agent
    # @return [Array<ADK::Tool>] Array of tool instances
    def tools
      @tool_registry.tools.values.map do |tool_class|
        @tool_registry.create_instance(tool_class.tool_name)
      end.compact
    end

    # Finds a tool instance by name
    # @param tool_name [Symbol] The name of the tool to find
    # @return [ADK::Tool, nil] The tool instance if found, nil otherwise
    def find_tool(tool_name)
      @tool_registry.create_instance(tool_name.to_sym)
    end

    # Registers a tool class with the agent's specific registry.
    # @param tool_class [Class] The tool class to register (must inherit from ADK::Tool).
    # @return [Boolean] True if registration was successful, false otherwise.
    def register_tool_class(tool_class)
      # Basic validation - simplified check
      unless tool_class < ADK::Tool
        ADK.logger.error("Agent '#{name}': Attempted to register invalid object (must inherit from ADK::Tool): #{tool_class.inspect}")
        return false
      end

      tool_name = tool_class.tool_name
      unless tool_name
        ADK.logger.error("Agent '#{name}': Tool class #{tool_class} missing metadata (use define_metadata). Cannot register.")
        return false
      end

      if @tool_registry.find_class(tool_name)
        ADK.logger.warn("Agent '#{name}': Tool '#{tool_name}' already registered. Overwriting.")
      end

      # Register with the instance registry
      @tool_registry.register(tool_name, tool_class)
    end

    # --- Runtime State Methods (unchanged) ---
    def start
      return if running? # Prevent starting multiple times

      ADK.logger.info("Starting agent '#{name}' runtime...")
      @state = :running

      # Connect to MCP Servers and register tools
      connect_mcp_servers

      ADK.logger.info("Agent '#{name}' runtime started.")
    end

    def stop
      return unless running?

      ADK.logger.info("Stopping agent '#{name}' runtime...")
      @state = :stopped

      # Disconnect MCP Clients
      disconnect_mcp_servers

      ADK.logger.info("Agent '#{name}' runtime stopped.")
    end

    def running?
      @state == :running
    end

    # Returns the list of available tool metadata (names, descriptions, parameters)
    # from the agent's specific tool registry.
    def available_tools_metadata
      @tool_registry.list_tools
    end

    # Finds a tool class by name from the agent's specific tool registry.
    # @param tool_name [Symbol]
    # @return [Class<ADK::Tool>, nil]
    def find_tool_class(tool_name)
      @tool_registry.find_class(tool_name.to_sym)
    end

    # --- REFACTORED: run_task operates within a session context ---
    # Processes user input within the context of a specific session.
    #
    # @param session_id [String] The ID of the session to use/update.
    # @param user_input [String] The user's input/request for this turn.
    # @param session_service [Object] The service used to manage sessions (must respond to #append_event, #get_session).
    # @return [ADK::Event] The final :agent event containing the response.
    # @return [Hash] An error hash { status: :error, error_message: ... } if a critical error occurs (less common now, errors wrap in Events).
    def run_task(session_id:, user_input:, session_service:)
      final_agent_event = nil
      adk_session = nil

      adk_session = session_service.get_session(session_id: session_id)
      unless adk_session
        msg = "Session not found: #{session_id}"
        ADK.logger.error(msg)
        error_event = ADK::Event.new(role: :agent, content: { status: :error, error_message: msg })
        session_service.append_event(session_id: session_id, event: error_event) rescue nil
        return error_event
      end

      unless running?
        msg = "Agent '#{name}' runtime is not active (stopped)."
        ADK.logger.error(msg)
        error_event = ADK::Event.new(role: :agent, content: { status: :error, error_message: msg })
        session_service.append_event(session_id: session_id, event: error_event)
        return error_event
      end

      ADK.logger.info("Agent '#{name}' starting task in session '#{session_id}': #{user_input}")

      begin
        user_event = ADK::Event.new(role: :user, content: user_input)
        session_service.append_event(session_id: session_id, event: user_event)

        plan = planner.plan(user_input)

        execution_result = execute_plan(plan, adk_session, session_service)

        final_content = nil
        # --- Determine Final Agent Response based on execution result ---
        if execution_result.is_a?(Hash) && execution_result[:status] == :error
          final_content = execution_result
          ADK.logger.error("Agent '#{name}' task failed. Reason: #{execution_result[:error_message]}")
        elsif execution_result.is_a?(Array)
          last_step = execution_result.last
          if last_step
            # Pass the entire hash from the last step regardless of status (:success, :error, :pending)
            final_content = last_step
            log_level = (last_step[:status] == :error) ? :warn : :info
            ADK.logger.send(log_level,
                            "Agent '#{name}' task completed multi-step with final status: #{last_step[:status]}. Last step msg: #{last_step&.dig(:error_message) || last_step&.dig(:message) || last_step&.dig(:result)}")
          else # Empty results array
            final_content = { status: :error, error_message: "Multi-step execution resulted in empty result array." }
            ADK.logger.error(final_content[:error_message])
          end
        elsif execution_result.is_a?(Hash) && [:success, :pending].include?(execution_result[:status]) # Single successful or pending step
          final_content = execution_result
          ADK.logger.info("Agent '#{name}' task completed with status: #{execution_result[:status]}. Result: #{final_content[:result] || final_content[:message] || final_content[:job_id]}")
        else # Unexpected format
          msg = "Task finished with unexpected execution result: #{execution_result.inspect}"
          final_content = { status: :error, error_message: msg }
          ADK.logger.error(msg)
        end

        unless final_content.is_a?(Hash) && final_content.key?(:status)
          final_content = { status: :success, result: final_content.to_s }
        end
        # --- End Determine Final Agent Response based on execution result ---

        final_agent_event = ADK::Event.new(role: :agent, content: final_content)
        session_service.append_event(session_id: session_id, event: final_agent_event)
      rescue StandardError => e
        ADK.logger.error("Critical error during run_task for agent '#{name}': #{e.class} - #{e.message}")
        ADK.logger.error(e.backtrace.join("\n"))
        error_event_content = { status: :error, error_message: "An internal error occurred: #{e.message}" }
        final_agent_event = ADK::Event.new(role: :agent, content: error_event_content)
        session_service.append_event(session_id: session_id, event: final_agent_event) if adk_session rescue nil
      end

      final_agent_event
    end

    private

    # --- REFACTORED: execute_plan uses session context ---
    # Executes a plan, logging tool request/result events via the session service.
    # @param plan [Array<Hash>] Plan from the planner.
    # @param session [ADK::Session] The current session object.
    # @param session_service [Object] The session service instance.
    # @return [Hash, Array<Hash>] Result hash or array of hashes from steps. Returns error hash on planning issues.
    def execute_plan(plan, session, session_service)
      session_id = session.id

      unless plan.is_a?(Array)
        msg = "Invalid plan received from planner (not an Array)."
        ADK.logger.error("#{msg} Plan: #{plan.inspect}")
        return { status: :error, error_message: msg }
      end

      # --- Handle Empty Plan based on Fallback Mode ---
      if plan.empty?
        if @fallback_mode == :echo
          # --- Check if echo tool is actually available to this agent ---
          if @tool_registry.find_class(:echo)
            ADK.logger.warn("Plan is empty. Falling back to echo mode for session '#{session_id}'.")
            # Reconstruct the plan to be a single echo step
            # We need the original user input for this - fetch it from the session
            # Find the *last* user event in case of corrections/multiple turns
            original_user_input = session.events.reverse.find { |e|
              e.role == :user
            }&.content || "[Original input not found]"
            plan = [{ tool: :echo, params: { message: original_user_input } }]
            ADK.logger.debug("Reconstructed plan for echo fallback: #{plan.inspect}")
            # Now continue execution with the modified plan
          else
            # Echo tool not available, default to error mode
            msg = "Planning failed and Echo fallback tool is not available to this agent."
            ADK.logger.warn(msg)
            return { status: :error, error_message: msg }
          end
        else # Default or :error mode
          msg = "I cannot fulfill this request with the available tools (empty plan)."
          ADK.logger.warn(msg)
          return { status: :error, error_message: msg }
        end
      end
      # --- End Handle Empty Plan ---

      ADK.logger.debug("Executing plan with #{plan.length} step(s) for session '#{session_id}': #{plan.inspect}")
      previous_step_result_hash = nil
      all_results_hashes = []

      plan.each_with_index do |step, index|
        ADK.logger.debug("Executing step #{index + 1}/#{plan.length}: #{step.inspect}")
        ADK.logger.debug("  Input (result hash from previous step): #{previous_step_result_hash.inspect}")

        # --- Input Injection Logic (Updated for job_id) ---
        current_params = step[:params].dup
        current_params.transform_values! do |value|
          injection_value = nil
          if value.is_a?(String) && value.match?(/\[Result from step \d+\]|\[Result from previous step\]/i)
            if previous_step_result_hash && [:success, :pending].include?(previous_step_result_hash[:status])
              # Prioritize :result, then :job_id (was workflow_id), then :message
              if previous_step_result_hash.key?(:result)
                prev_result = previous_step_result_hash[:result]
                if prev_result.is_a?(Hash) && prev_result.key?(:status) && prev_result.key?(:result) # AgentTool nested result
                  injection_value = prev_result[:result]
                  ADK.logger.debug("Injecting nested result...")
                else
                  injection_value = prev_result
                  ADK.logger.debug("Injecting direct result...")
                end
              elsif previous_step_result_hash.key?(:job_id) # <-- CHANGED from workflow_id
                injection_value = previous_step_result_hash[:job_id]
                ADK.logger.debug("Injecting job_id from previous step...")
              elsif previous_step_result_hash.key?(:message)
                injection_value = previous_step_result_hash[:message]
                ADK.logger.debug("Injecting message from previous step...")
              else
                ADK.logger.warn("Cannot inject: Previous successful/pending step missing usable key (:result, :job_id, :message). Prev Hash: #{previous_step_result_hash.inspect}")
                value
              end
            else
              ADK.logger.warn("Cannot inject: Previous step failed or absent. Prev Hash: #{previous_step_result_hash.inspect}")
              value
            end
            injection_value || value # Use injection if found, otherwise keep original
          else
            value # Not a placeholder string, keep original value
          end
        end
        step_with_injected_params = step.merge(params: current_params)
        ADK.logger.debug("  Params after potential injection: #{current_params.inspect}")
        # --- End Input Injection Logic ---

        # --- Execute Step (Passes session context) ---
        current_result_hash = execute_step(step_with_injected_params, session, session_service) # <-- Pass session
        all_results_hashes << current_result_hash

        # --- Stop on first error ---
        if current_result_hash[:status] == :error
          ADK.logger.warn("Step #{index + 1} failed, stopping plan execution: #{current_result_hash[:error_message]}")
          break # Exit the loop
        end
        # --- End Stop on first error ---

        previous_step_result_hash = current_result_hash
      end

      ADK.logger.debug("Plan execution finished. Result hashes collected: #{all_results_hashes.inspect}")

      # Return single hash or array based on *executed* steps length
      # If loop broke early, return array up to that point.
      # If plan was single step, return the single hash.
      if all_results_hashes.length == 1
        all_results_hashes.first
      else
        all_results_hashes # Return all collected results (including potential error hash)
      end
    end # end execute_plan

    # --- REFACTORED: execute_step uses session context and passes it to tools ---
    # Executes a single step, logging :tool_request and :tool_result events via session service.
    # @param step [Hash] A hash like { tool: :symbol, params: {...} }.
    # @param session [ADK::Session] The current session object.
    # @param session_service [Object] The session service instance.
    # @return [Hash] A standard result hash { status: ..., result/error_message/job_id: ... }. <-- Updated return description
    def execute_step(step, session, session_service) # <-- Takes session object now
      session_id = session.id

      # --- Basic validation ---
      unless step.is_a?(Hash) && step[:tool].is_a?(Symbol) && step[:params].is_a?(Hash)
        msg = "Invalid step format received: #{step.inspect}"
        ADK.logger.error(msg)
        # Log as tool_result event (even though it failed before tool call)
        error_event = ADK::Event.new(role: :tool_result, tool_name: step[:tool] || :unknown,
                                     content: { status: :error, error_message: msg })
        session_service.append_event(session_id: session_id, event: error_event)
        return error_event.content
      end
      tool_name = step[:tool]
      params = step[:params]

      # 1. Log Tool Request Event (No state delta typically for requests)
      request_event = ADK::Event.new(role: :tool_request, tool_name: tool_name, content: params)
      session_service.append_event(session_id: session_id, event: request_event)

      # 2. Execute Tool <-- MODIFIED Block Start >>
      result_hash = nil
      begin
        # --- Get an *instance* of the tool from the registry ---
        tool_instance = @tool_registry.create_instance(tool_name)
        unless tool_instance
          raise ADK::Error, "Tool '#{tool_name}' not found for this agent."
        end

        # --- Create ToolContext ---
        tool_context = ADK::ToolContext.new(
          session_id: session.id,
          user_id: session.user_id,
          app_name: session.app_name,
          tool_registry: @tool_registry
        )
        ADK.logger.info("Executing tool '#{tool_name}' with params: #{params.inspect} and context: #{tool_context.to_h.inspect}")
        # --- Pass context to execute ---
        result_hash = tool_instance.execute(params, tool_context) # <-- MODIFIED: Use instance, Pass context

        # Validate tool's return format (including :pending status)
        unless result_hash.is_a?(Hash) && result_hash.key?(:status) && [:success, :error,
                                                                        :pending].include?(result_hash[:status])
          ADK.logger.error("Tool '#{tool_name}' returned invalid hash or status: #{result_hash.inspect}")
          result_hash = { status: :error, error_message: "Tool '#{tool_name}' failed to return standard hash format." }
        end
      rescue ADK::Error => e # Tool not found or validation error from tool.execute
        ADK.logger.error("ADK::Error executing tool '#{tool_name}': #{e.message}")
        result_hash = { status: :error, error_message: e.message }
      rescue StandardError => e # Unexpected error within tool.execute
        ADK.logger.error("Unexpected error executing tool '#{tool_name}': #{e.class} - #{e.message}")
        ADK.logger.error(e.backtrace.join("\n"))
        result_hash = { status: :error, error_message: "Internal error executing tool '#{tool_name}': #{e.message}" }
      end
      # --- << MODIFIED Block End >> ---

      # 3. Log Tool Result Event
      result_event = ADK::Event.new(
        role: :tool_result,
        tool_name: tool_name,
        content: result_hash # Log the entire result hash as content
      )
      session_service.append_event(session_id: session_id, event: result_event)

      # 4. Return the result hash from the tool execution
      result_hash
    end

    # Connects to all configured MCP servers.
    def connect_mcp_servers
      @mcp_servers_config.each do |config|
        ADK.logger.info("Attempting to connect to MCP server: #{config.inspect}")
        begin
          # --- Add check for :sse type --- >
          unless [:stdio, :sse].include?(config[:type])
            ADK.logger.error("Unsupported MCP server type specified: #{config[:type]}. Skipping configuration: #{config.inspect}")
            next # Skip to the next server config
          end
          # <-----------------------------

          client = ADK::Mcp::Client.new(config)
          client.connect # This performs handshake and gets capabilities
          @mcp_clients << client
          discover_and_register_mcp_tools(client)
        rescue ADK::Mcp::ConnectionError, ADK::Mcp::ProtocolError => e # More specific MCP errors
          ADK.logger.error("Failed to connect or handshake with MCP server #{config.inspect}: #{e.message}")
        rescue ADK::Mcp::McpError => e # Catch specific MCP errors (typo fix: Error -> McpError)
          ADK.logger.error("MCP-related error connecting to server #{config.inspect}: #{e.message}")
        rescue StandardError => e
          ADK.logger.error("Unexpected error connecting to MCP server #{config.inspect}: #{e.class} - #{e.message}")
        end
      end
    end

    # Disconnects all active MCP clients.
    def disconnect_mcp_servers
      @mcp_clients.each do |client|
        begin
          ADK.logger.info("Disconnecting MCP client...")
          client.disconnect
        rescue StandardError => e
          ADK.logger.error("Error disconnecting MCP client: #{e.message}")
        end
      end
      @mcp_clients.clear
    end

    # Discovers tools from a connected MCP client and registers them with the agent's registry.
    # @param client [ADK::Mcp::Client]
    def discover_and_register_mcp_tools(client)
      ADK.logger.debug("[Agent E2E Debug] discover_and_register - @tool_registry ID: #{@tool_registry.object_id}")
      begin
        mcp_tool_schemas = client.list_tools
        ADK.logger.debug("[Agent E2E Debug] list_tools returned: #{mcp_tool_schemas.inspect}")
        ADK.logger.info("Discovered #{mcp_tool_schemas.count} tools from MCP server.")
        mcp_tool_schemas.each do |schema|
          # Pass the agent's specific registry instance (@tool_registry)
          ADK::Mcp::ToolWrapper.from_mcp_schema(schema, client, @tool_registry)
        end
      rescue ADK::Mcp::McpError => e # Corrected typo: Error -> McpError
        ADK.logger.error("Failed to list tools from MCP server: #{e.message}")
      rescue StandardError => e
        ADK.logger.error("Unexpected error discovering MCP tools: #{e.class} - #{e.message}")
      end
    end
  end # End Agent class
end # End ADK module
