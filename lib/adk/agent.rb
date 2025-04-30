# File: lib/adk/agent.rb
# frozen_string_literal: true

require 'logger'
require 'concurrent'
require 'pathname' # Added for path manipulation
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
    DEFAULT_MODEL = 'gemini-2.0-flash' # Updated default model

    attr_reader :name, :description, :planner, :logger, :model_name, :state, :tool_registry, :fallback_mode

    # --- Builder Class for `define` method ---
    class AgentBuilder
      attr_accessor :name, :description, :model_name, :fallback_mode, :mcp_servers, :selected_tool_names
      attr_reader :tool_paths, :tool_classes # Keep track of both

      def initialize
        @name = nil
        @description = nil
        @model_name = nil
        @fallback_mode = :error
        @tool_paths = []
        @tool_classes = []
        @mcp_servers = []
        @selected_tool_names = []
        # Planner is not directly configured here, it's created by Agent#initialize
      end

      # Sets the paths for automatic tool discovery.
      # @param paths [String, Array<String>] One or more directory paths.
      def discover_tools_in(*paths)
        @tool_paths.concat(Array(paths).flatten.compact.uniq)
      end

      # Adds native tool classes directly.
      # @param classes [Class, Array<Class>] One or more classes inheriting from ADK::Tool.
      def add_tool_classes(*classes)
        @tool_classes.concat(Array(classes).flatten.compact.uniq)
      end

      # Builds the Agent instance using the collected configuration.
      # @return [ADK::Agent] The configured agent instance.
      # @raise [ArgumentError] if required attributes like name or description are missing.
      def build
        raise ArgumentError, "Agent name must be set in the define block." unless @name && !@name.strip.empty?

        raise ArgumentError,
              "Agent description must be set in the define block." unless @description && !@description.strip.empty?

        ADK::Agent.new(
          name: @name,
          description: @description,
          model_name: @model_name, # Defaults handled in initialize
          tool_classes: @tool_classes,
          tool_paths: @tool_paths,
          mcp_servers: @mcp_servers,
          fallback_mode: @fallback_mode,
          selected_tool_names: @selected_tool_names
          # Planner is created internally by ADK::Agent.new
        )
      end
    end
    # --- End Builder Class ---

    # --- Class Method for Configuration DSL ---
    # Provides a block-based DSL for configuring and creating an Agent instance.
    #
    # @example
    #   agent = ADK::Agent.define do |a|
    #     a.name = 'news_agent'
    #     a.description = 'Summarizes news articles.'
    #     a.model_name = 'gemini-pro'
    #     a.discover_tools_in 'path/to/my_tools'
    #     a.add_tool_classes MyCustomTool
    #     a.fallback_mode = :echo
    #   end
    #
    # @yieldparam builder [ADK::Agent::AgentBuilder] The builder object to configure the agent.
    # @return [ADK::Agent] The newly configured agent instance.
    # @raise [ArgumentError] if the block is not provided or required attributes are missing.
    def self.define
      raise ArgumentError, "ADK::Agent.define requires a block." unless block_given?

      builder = AgentBuilder.new
      yield builder
      builder.build
    end
    # --- End Class Method ---

    # Initializes a new agent instance.
    # Note: Session and Memory are no longer managed directly by the agent instance.
    #
    # @param name [String] The unique name of the agent definition.
    # @param description [String] A description of the agent's purpose.
    # @param model_name [String, nil] The specific LLM model name (optional).
    # @param tool_classes [Array<Class>] An initial list of native tool *classes* (must inherit from ADK::Tool).
    # @param tool_paths [String, Array<String>] Optional: Path(s) to directories containing tool definitions (.rb files) to automatically discover and load.
    # @param planner [ADK::Planner] A specific planner instance (default: created automatically).
    # @param mcp_servers [Array<Hash>, String] Optional configurations for external MCP servers (JSON string or Array).
    # @param fallback_mode [Symbol] Behavior when planning fails (:error or :echo). Default: :error
    # @param selected_tool_names [Array<Symbol>] List of tool names explicitly selected in the agent definition (used for MCP).
    def initialize(name:, description:, model_name: nil, tool_classes: [], tool_paths: [], planner: nil, mcp_servers: [],
                   fallback_mode: :error, selected_tool_names: [])
      ADK.logger.info("Initializing agent '#{name}'...")
      @name = name
      @description = description
      @model_name = model_name || DEFAULT_MODEL
      @fallback_mode = fallback_mode == :echo ? :echo : :error # Ensure only valid modes
      @state = :idle # Initial state

      # Each agent instance gets its own registry
      @tool_registry = ADK::ToolRegistry.new
      ADK.logger.debug("Agent '#{name}' created its ToolRegistry instance: #{@tool_registry.object_id}")

      # Store initial tool names from global registry before automatic discovery
      initial_global_tools = ADK::GlobalToolManager.registered_tool_names.to_set

      # Normalize tool_paths to an array
      @tool_paths = Array(tool_paths).compact.uniq

      # --- Automatic Tool Discovery ---
      unless @tool_paths.empty?
        _discover_and_load_tools(@tool_paths)
      end
      # --- End Tool Discovery ---

      # --- Determine newly registered tools ---
      current_global_tools = ADK::GlobalToolManager.registered_tool_names.to_set
      newly_discovered_tool_names = (current_global_tools - initial_global_tools).to_a
      ADK.logger.debug("[Agent Init '#{name}'] Initial global tools: #{initial_global_tools.inspect}")
      ADK.logger.debug("[Agent Init '#{name}'] Current global tools: #{current_global_tools.inspect}")
      ADK.logger.debug("[Agent Init '#{name}'] Newly discovered tool names: #{newly_discovered_tool_names.inspect}")
      # ------------------------------------

      # Register initial native tool *classes* passed directly
      tool_classes.each { |tool_class| register_tool_class(tool_class) }

      # Instantiate and add *newly discovered* tools from paths
      ADK.logger.debug("[Agent Init '#{name}'] Adding newly discovered tools: #{newly_discovered_tool_names.inspect}")
      newly_discovered_tool_names.each do |tool_name|
        ADK.logger.debug("[Agent Init '#{name}'] Processing discovered tool: #{tool_name.inspect}")
        # Fetch the CLASS from the global manager, not an instance
        tool_class = ADK::GlobalToolManager.find_class(tool_name)
        if tool_class
          ADK.logger.debug("[Agent Init '#{name}'] Found class #{tool_class} for #{tool_name.inspect}, attempting register_tool_class...")
          register_tool_class(tool_class) # Register the class in the agent's registry
        else
          # This logic path was hit in some spec failures with the other approach
          ADK.logger.error("[Agent Init '#{name}'] Failed to find class for discovered tool '#{tool_name}' in GlobalToolManager.")
        end
      end

      # Automatically register the CheckJobStatusTool class if Sidekiq is defined
      # and if it wasn't already discovered/added
      if defined?(Sidekiq)
        unless @tool_registry.find_class(:check_job_status)
          begin
            require_relative 'tools/check_job_status_tool' # Ensure loaded
            register_tool_class(ADK::Tools::CheckJobStatusTool)
            ADK.logger.info("Automatically registered CheckJobStatusTool for agent '#{name}'.")
          rescue LoadError => e
            ADK.logger.error("Failed to load CheckJobStatusTool: #{e.message}")
          end
        end
      else
        ADK.logger.warn("Sidekiq not defined. Skipping automatic registration of CheckJobStatusTool for agent '#{name}'.")
      end

      # --- Parse MCP Server Config (moved down to avoid log clutter during tool loading) ---
      if mcp_servers.is_a?(String) && !mcp_servers.strip.empty?
        begin
          @mcp_servers_config = JSON.parse(mcp_servers)
          unless @mcp_servers_config.is_a?(Array)
            ADK.logger.warn("Agent '#{name}': MCP server config parsed but is not an Array: #{@mcp_servers_config.inspect}. Defaulting to empty array.")
            @mcp_servers_config = []
          end
        rescue JSON::ParserError => e
          ADK.logger.error("Agent '#{name}': Failed to parse MCP server config JSON: #{e.message}. Config string: '#{mcp_servers}'. Defaulting to empty array.")
          @mcp_servers_config = []
        end
      elsif mcp_servers.is_a?(Array)
        @mcp_servers_config = mcp_servers # Already an array
      else
        ADK.logger.debug("Agent '#{name}': No valid MCP server config provided. Defaulting to empty array.")
        @mcp_servers_config = []
      end
      # -------------------------------\n
      @selected_tool_names = selected_tool_names # Store selected tool names (used for MCP)
      @mcp_clients = [] # Store active MCP client instances

      @planner = planner || ADK::Planner.new(agent: self, model_name: @model_name)

      ADK.logger.info("Agent '#{name}' initialized successfully with tools: #{@tool_registry.tools.keys.join(', ')}")
    end

    # Adds a tool instance OR class to the agent's registry
    # @param tool [ADK::Tool, Class<ADK::Tool>] The tool instance or class to add
    # @return [Boolean] True if the tool was added, false otherwise
    def add_tool(tool)
      # Check if it's a valid tool instance or class
      is_tool_instance = tool.is_a?(ADK::Tool)
      is_tool_class = tool.is_a?(Class) && tool < ADK::Tool

      unless is_tool_instance || is_tool_class
        ADK.logger.error("Agent '#{name}' add_tool: Attempted to add invalid tool: #{tool.inspect}")
        return false
      end

      # Determine the actual tool class
      tool_class = is_tool_class ? tool : tool.class

      # --- Determine Tool Name with Fallbacks --- #
      metadata = tool_class.tool_metadata # No rescue - let errors propagate if metadata itself fails
      tool_name = metadata[:name]&.to_sym

      if tool_name.nil? || tool_name == :''
        # Check deprecated @tool_name
        if tool_class.instance_variable_defined?(:@tool_name)
          tool_name = tool_class.instance_variable_get(:@tool_name)&.to_sym
          ADK.logger.debug("Agent '#{name}' add_tool: using name from deprecated @tool_name: #{tool_name.inspect}")
        elsif tool_class.respond_to?(:inferred_name)
          # Try inference
          tool_name = tool_class.inferred_name
          ADK.logger.debug("Agent '#{name}' add_tool: using inferred name: #{tool_name.inspect}")
        end
      end
      # --- End Determine Tool Name --- #

      # Validate name was found
      unless tool_name && tool_name != :''
        ADK.logger.error("Agent '#{name}' add_tool: Could not determine tool name for class #{tool_class}. Cannot add tool.")
        return false
      end

      # Check for overwrite
      if @tool_registry.find_class(tool_name)
        ADK.logger.warn("Agent '#{name}': Tool '#{tool_name}' already added. Overwriting with class #{tool_class}.")
      end

      # Register the class using the determined name
      ADK.logger.debug("Agent '#{name}' add_tool: Registering tool_name=#{tool_name.inspect} with class=#{tool_class.inspect} in registry=#{@tool_registry.object_id}")
      registration_result = @tool_registry.register(tool_name, tool_class)
      ADK.logger.debug("Agent '#{name}' add_tool: Registry after registration for #{tool_name.inspect}: #{@tool_registry.tools.keys.inspect}")

      # Explicitly return the boolean result from the registry
      registration_result
    end

    # Returns the list of tools registered with this agent
    # @return [Array<ADK::Tool>] Array of tool instances
    def tools
      @tool_registry.tools.values.map do |tool_class|
        # Get name reliably using the unified metadata method
        tool_name = tool_class.tool_metadata[:name]
        if tool_name
          @tool_registry.create_instance(tool_name)
        else
          ADK.logger.warn("Agent '#{name}': Skipping tool instance creation for class #{tool_class} as it has no retrievable name.")
          nil
        end
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
      # Basic validation
      unless tool_class < ADK::Tool
        ADK.logger.error("Agent '#{name}': Attempted to register invalid object (must inherit from ADK::Tool): #{tool_class.inspect}")
        return false
      end

      # Get name via metadata method
      metadata = tool_class.tool_metadata
      tool_name = metadata[:name]&.to_sym

      unless tool_name
        # Use logger method, not direct access
        ADK.logger.error("Agent '#{name}': Tool class #{tool_class} missing name in its metadata. Cannot register.")
        return false
      end

      if @tool_registry.find_class(tool_name)
        ADK.logger.warn("Agent '#{name}': Tool '#{tool_name}' already registered. Overwriting.")
      end

      # Register with the instance registry
      @tool_registry.register(tool_name, tool_class)
      true # Return true on success
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

        # --- MODIFIED: execute_plan now returns hash { details: [...], last_result: {...} } ---
        execution_outcome = execute_plan(plan, adk_session, session_service)
        plan_execution_details = execution_outcome[:details]
        original_last_step_result = execution_outcome[:last_result]
        # ----------------------------------------------------------

        final_content = nil

        # --- Determine Final Agent Response based on execution result ---
        if original_last_step_result.nil?
          # This case handles planning errors or empty plans where execute_plan returned an error hash directly
          final_content = plan_execution_details # In error cases, details *is* the error hash
          ADK.logger.error("Agent '#{name}' task failed. Reason: #{final_content[:error_message]}") if final_content.is_a?(Hash)
        else
          # Plan execution happened. Use the original last step result for final content.
          # Deep copy to prevent modification issues if result is mutable
          final_content = Marshal.load(Marshal.dump(original_last_step_result))
          ADK.logger.debug("Using original last step result for final_content: #{final_content.inspect}")
        end

        # --- Attach plan details (sanitized) to the final content hash ---
        if final_content.is_a?(Hash) && plan_execution_details.is_a?(Array)
          final_content[:plan_details] = plan_execution_details
        elsif plan_execution_details.is_a?(Array) # final_content wasn't a hash, log warning?
          ADK.logger.warn("Could not attach plan details because final_content was not a hash: #{final_content.inspect}")
        end
        # --- End Determine Final Agent Response based on execution result ---

        ADK.logger.debug("Final content for agent event BEFORE creation: #{final_content.inspect}")

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

    # Discovers and loads tool definition files from specified paths.
    # @param paths [Array<String>] An array of directory paths to search.
    # @return [void]
    def _discover_and_load_tools(paths)
      return if paths.empty?

      ADK.logger.debug("Starting tool discovery in paths: #{paths.inspect}")

      paths.each do |path|
        absolute_dir_path = File.expand_path(path, Dir.pwd)

        unless Dir.exist?(absolute_dir_path)
          ADK.logger.warn("Tool discovery path does not exist or is not a directory: '#{path}' (resolved to '#{absolute_dir_path}'). Skipping.")
          next
        end

        Dir.glob(File.join(absolute_dir_path, '*.rb')).each do |absolute_file_path|
          begin
            ADK.logger.debug("Attempting to load tool file using 'require': #{absolute_file_path}")
            # Use require instead of load to prevent re-registration issues
            require absolute_file_path
            ADK.logger.debug("Successfully required (or already required): #{absolute_file_path}")
          rescue LoadError, SyntaxError => e
            ADK.logger.error("Failed to require/eval tool file '#{absolute_file_path}': #{e.class} - #{e.message}")
          rescue StandardError => e
            ADK.logger.error("Error encountered while requiring/processing tool file '#{absolute_file_path}': #{e.class} - #{e.message}")
          end
        end
      end
      ADK.logger.debug("Finished tool discovery.")
    end

    # --- REFACTORED: execute_plan now returns hash { details: [...], last_result: original_hash } ---
    # Executes a plan, logging tool request/result events via the session service.
    # @param plan [Array<Hash>] Plan from the planner.
    # @param session [ADK::Session] The current session object.
    # @param session_service [Object] The session service instance.
    # @return [Hash] { details: Array<Hash>, last_result: Hash } or { details: Hash, last_result: nil } on planning errors.
    def execute_plan(plan, session, session_service)
      session_id = session.id

      unless plan.is_a?(Array)
        msg = "Invalid plan received from planner (not an Array)."
        ADK.logger.error("#{msg} Plan: #{plan.inspect}")
        return { details: { status: :error, error_message: msg }, last_result: nil }
      end

      # --- Handle Empty Plan based on Fallback Mode ---
      if plan.empty?
        if @fallback_mode == :echo
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
            return { details: { status: :error, error_message: msg }, last_result: nil }
          end
        else # Default or :error mode
          msg = "I cannot fulfill this request with the available tools (empty plan)."
          ADK.logger.warn(msg)
          return { details: { status: :error, error_message: msg }, last_result: nil }
        end
      end
      # --- End Handle Empty Plan ---

      ADK.logger.debug("Executing plan with #{plan.length} step(s) for session '#{session_id}': #{plan.inspect}")
      previous_step_result_hash = nil
      plan_execution_details = []
      last_successful_or_pending_result = nil # <-- Store the original last hash

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

        # --- Execute Step --- #
        current_result_hash = execute_step(step_with_injected_params, session, session_service)

        # --- Sanitize for plan_details --- #
        sanitized_result_for_plan = {}
        if current_result_hash.is_a?(Hash)
          sanitized_result_for_plan[:status] = current_result_hash[:status]
          sanitized_result_for_plan[:error_message] =
            current_result_hash[:error_message] if current_result_hash.key?(:error_message)
          sanitized_result_for_plan[:error_class] =
            current_result_hash[:error_class] if current_result_hash.key?(:error_class)
          sanitized_result_for_plan[:job_id] = current_result_hash[:job_id] if current_result_hash.key?(:job_id)
          sanitized_result_for_plan[:message] = current_result_hash[:message] if current_result_hash.key?(:message)
          # Only include :result value if it's simple
          result_val = current_result_hash[:result]
          if result_val.is_a?(String) || result_val.is_a?(Numeric) || [true, false, nil].include?(result_val)
            sanitized_result_for_plan[:result] = result_val
          elsif current_result_hash.key?(:result) # It exists but is complex
            sanitized_result_for_plan[:result] = "[Complex Result Structure]"
          end
        else # Should not happen based on execute_step validation, but handle defensively
          sanitized_result_for_plan[:status] = :error
          sanitized_result_for_plan[:error_message] = "Invalid format from execute_step: #{current_result_hash.inspect}"
        end
        # --- END Sanitization ---

        # --- Store SANITIZED step detail --- #
        plan_execution_details << {
          tool_name: step[:tool],
          params: current_params,
          result: sanitized_result_for_plan
        }

        # --- Store ORIGINAL result and check for errors --- #
        if current_result_hash[:status] == :error
          ADK.logger.warn("Step #{index + 1} failed, stopping plan execution: #{current_result_hash[:error_message]}")
          last_successful_or_pending_result = current_result_hash # Store the error hash as last result
          break # Exit the loop
        else
          # Store successful or pending hash for potential injection AND final result
          previous_step_result_hash = current_result_hash
          last_successful_or_pending_result = current_result_hash
        end
        # --- End Stop on first error / Store last result --- #
      end

      ADK.logger.debug("Plan execution finished. Structured details collected: #{plan_execution_details.inspect}")
      ADK.logger.debug("Plan execution finished. Original last result: #{last_successful_or_pending_result.inspect}")

      # --- Return BOTH sanitized details AND original last result --- #
      { details: plan_execution_details, last_result: last_successful_or_pending_result }
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
                                     content: { status: :error, error_message: msg, error_class: 'InvalidStepFormat' })
        session_service.append_event(session_id: session_id, event: error_event)
        return error_event.content
      end
      tool_name = step[:tool]
      params = step[:params]

      # 1. Log Tool Request Event (No state delta typically for requests)
      request_event = ADK::Event.new(role: :tool_request, tool_name: tool_name, content: params)
      session_service.append_event(session_id: session_id, event: request_event)

      # 2. Execute Tool
      result_hash = nil
      begin
        # --- Get an *instance* of the tool from the registry ---
        tool_instance = @tool_registry.create_instance(tool_name)
        unless tool_instance
          # Raise ToolError directly if tool is not found
          raise ADK::ToolError, "Tool '#{tool_name}' not found for this agent."
        end

        # --- Create ToolContext ---
        tool_context = ADK::ToolContext.new(
          session_id: session.id,
          user_id: session.user_id,
          app_name: session.app_name,
          tool_registry: @tool_registry
        )
        ADK.logger.info("Executing tool '#{tool_name}' with params: #{params.inspect} and context: #{tool_context.to_h.inspect}")

        # --- Execute the tool, rescuing specific ToolErrors ---
        begin
          result_hash = tool_instance.execute(params, tool_context)

          # Validate tool's success/pending return format.
          # Tools should now RAISE ADK::ToolError on failure, not return {status: :error}.
          unless result_hash.is_a?(Hash) && result_hash.key?(:status) && [:success,
                                                                          :pending].include?(result_hash[:status])
            ADK.logger.error("Tool '#{tool_name}' returned invalid hash or status (expected success/pending): #{result_hash.inspect}")
            # Raise a ToolError if the format is wrong, even on expected success/pending path.
            raise ADK::ToolError, "Tool '#{tool_name}' failed to return standard hash format (status: success/pending)."
          end
        rescue ADK::ToolError => e # Catch specific ToolErrors raised by the tool
          ADK.logger.error("ToolError executing tool '#{tool_name}': #{e.message} (#{e.class.name})")
          # --- FIXED: Ensure error_class and result: nil are included --- #
          result_hash = { status: :error, error_message: e.message, error_class: e.class.name, result: nil }
        rescue StandardError => e # Catch unexpected errors *within* the tool's execute method
          ADK.logger.error("Unexpected error *within* tool '#{tool_name}' execution: #{e.class} - #{e.message}")
          ADK.logger.error(e.backtrace.join("\n"))
          # --- FIXED: Ensure error_class and result: nil are included --- #
          result_hash = { status: :error, error_message: "Internal error executing tool '#{tool_name}': #{e.message}",
                          error_class: e.class.name, result: nil }
        end
        # --- End tool execution block ---
      rescue ADK::ToolError => e # Catch ToolError from setup (e.g., tool not found)
        ADK.logger.error("ToolError preparing tool '#{tool_name}': #{e.message} (#{e.class.name})")
        # --- FIXED: Ensure error_class and result: nil are included --- #
        result_hash = { status: :error, error_message: e.message, error_class: e.class.name, result: nil }
      rescue StandardError => e # Catch unexpected errors during tool preparation (e.g., context creation)
        ADK.logger.error("Unexpected error preparing tool '#{tool_name}': #{e.class} - #{e.message}")
        ADK.logger.error(e.backtrace.join("\n"))
        # --- FIXED: Ensure error_class and result: nil are included --- #
        result_hash = { status: :error, error_message: "Internal error preparing tool '#{tool_name}': #{e.message}",
                        error_class: e.class.name, result: nil }
      end

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
        # Transform keys to symbols for the client
        symbolized_config = config.transform_keys(&:to_sym)
        ADK.logger.info("Attempting to connect to MCP server: #{symbolized_config.inspect}")
        begin
          # --- FIXED: Check using STRING key 'type' --- >
          unless ['stdio', 'sse'].include?(symbolized_config[:type])
            # --- FIXED: Log the actual value found using string key ---\
            ADK.logger.error("Unsupported MCP server type specified: #{symbolized_config[:type].inspect}. Skipping configuration: #{symbolized_config.inspect}")
            next # Skip to the next server config
          end
          # <-----------------------------

          # --- NEW: Explicitly convert known string type values to symbols ---
          if symbolized_config[:type] == "stdio"
            symbolized_config[:type] = :stdio
          elsif symbolized_config[:type] == "sse"
            symbolized_config[:type] = :sse
          end
          # Pass the modified hash
          client = ADK::Mcp::Client.new(symbolized_config)
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
          # --- ADDED check: Only register if tool was selected ---
          tool_name_sym = schema[:name].to_sym
          if @selected_tool_names.include?(tool_name_sym)
            # Pass the agent's specific registry instance (@tool_registry)
            ADK::Mcp::ToolWrapper.from_mcp_schema(schema, client, @tool_registry)
          else
            ADK.logger.debug("Skipping registration of MCP tool '#{tool_name_sym}' as it was not selected in agent definition.")
          end
          # --- END check ---
        end
      rescue ADK::Mcp::McpError => e # Corrected typo: Error -> McpError
        ADK.logger.error("Failed to list tools from MCP server: #{e.message}")
      rescue StandardError => e
        ADK.logger.error("Unexpected error discovering MCP tools: #{e.class} - #{e.message}")
      end
    end
  end # End Agent class
end # End ADK module
