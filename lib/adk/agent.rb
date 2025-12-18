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
require_relative 'agent_definition'
require_relative 'mcp/client'
require_relative 'mcp/tool_wrapper'
require 'set'
require 'forwardable'
require 'json'
require_relative 'global_definition_registry'
require_relative 'global_tool_manager' # Added
require 'socket'
require 'set' # Required for the Set class in _check_circular_dependency
require 'securerandom' # Added for SecureRandom

module ADK
  class Error < StandardError; end unless defined?(ADK::Error)

  # Represents the static definition of an Agent, including its name,
  # description, instructions, tools, and model configuration.

  # Agent class represents an AI agent that can perform tasks using tools and a planner.
  # It operates within the context of a session managed by a SessionService.
  class Agent
    DEFAULT_MODEL = 'gemini-2.5-flash' # Updated default model

    attr_reader :name, :description, :planner, :logger, :model_name, :state, :tool_registry, :fallback_mode,
                :instruction, :definition, :session_service # Added session_service to attr_reader
    # MAS Attributes
    attr_reader :parent_agent # The parent agent in a hierarchy, if any
    attr_reader :sub_agents   # A collection of sub-agents

    # --- Callback Instance Variables ---
    attr_reader :before_agent_callback, :after_agent_callback,
                :before_model_callback, :after_model_callback,
                :before_tool_callback, :after_tool_callback

    # --- End Callback Instance Variables ---

    # --- Authentication Instance Variables ---
    attr_reader :auth_credential_names, :auth_url_mappings,
                :auth_scheme_assignments, :auth_credential_assignments

    # --- End Authentication Instance Variables ---

    # --- Builder Class for `define` method ---
    # class AgentBuilder
    #   ...
    #   ...
    # end
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
    def self.define(&block)
      raise ArgumentError, 'ADK::Agent.define requires a block.' unless block_given?

      # 1. Create a new AgentDefinition
      definition = ADK::AgentDefinition.new

      # 2. Evaluate the block within the definition's proxy DSL
      # Use the definition instance's define method which takes the block
      # This also handles internal validation via validate!
      begin
        definition.define(&block)
      rescue ArgumentError => e
        # Re-raise DSL validation errors immediately
        raise e
      end

      # 3. Save the validated definition using the configured definition store
      begin
        store = ADK.config.definition_store
        raise ADK::ConfigurationError, 'ADK.config.definition_store is not configured.' unless store

        # Ensure store responds to save_definition
        unless store.respond_to?(:save_definition)
          raise ADK::ConfigurationError,
                "Configured definition store (#{store.class}) does not support :save_definition method."
        end

        # Extract values using instance variables to avoid delegation issues
        agent_name = definition.instance_variable_get(:@name)
        description = definition.instance_variable_get(:@description)
        tool_names = definition.instance_variable_get(:@tool_names).map(&:to_s)
        model = definition.instance_variable_get(:@model_name)
        fallback_mode = definition.instance_variable_get(:@fallback_mode)
        mcp_servers = definition.instance_variable_get(:@mcp_servers) || []
        instruction = definition.instance_variable_get(:@instruction)
        webhook_enabled = definition.instance_variable_get(:@webhook_enabled)
        webhook_secret = definition.instance_variable_get(:@webhook_secret)

        # Prepare MCP JSON
        mcp_json = JSON.generate(mcp_servers)

        # Call save_definition with keyword arguments
        store.save_definition(
          name: agent_name.to_s,
          description: description,
          tools: tool_names,
          model: model,
          fallback_mode: fallback_mode,
          mcp_servers_json: mcp_json,
          instruction: instruction,
          webhook_enabled: webhook_enabled,
          webhook_secret: webhook_secret
        )

        # Use extracted name for logging
        ADK.logger.info("Agent definition '#{agent_name}' saved to store.")
      rescue JSON::GeneratorError => e
        agent_name_for_log = definition.instance_variable_get(:@name) || 'unknown'
        ADK.logger.error("Failed to serialize MCP servers for definition '#{agent_name_for_log}': #{e.message}")
        raise ADK::StoreError, "Internal error preparing definition '#{agent_name_for_log}' for storage."
      # Catch config errors specifically
      rescue ADK::ConfigurationError => e
        agent_name_for_log = definition.instance_variable_get(:@name) || 'unknown'
        ADK.logger.error("Configuration error during definition save for '#{agent_name_for_log}': #{e.message}")
        raise e
      # Catch store-specific errors (like connection issues, Redis errors, ArgumentErrors from store method)
      rescue ADK::StoreError, ArgumentError => e
        agent_name_for_log = definition.instance_variable_get(:@name) || 'unknown'
        ADK.logger.error("Failed to save definition '#{agent_name_for_log}' to store: #{e.class} - #{e.message}")
        raise e # Re-raise store/argument errors
      rescue => e # Catch other unexpected errors
        agent_name_for_log = definition.instance_variable_get(:@name) || 'unknown'
        ADK.logger.error("Unexpected error saving definition '#{agent_name_for_log}' to store: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
        raise ADK::StoreError, "Unexpected error saving definition '#{agent_name_for_log}': #{e.message}"
      end

      # <<< ADDED BACK: Register the in-memory definition object globally >>>
      GlobalDefinitionRegistry.register(definition)

      definition # Return the definition instance
    end
    # --- End Class Method ---

    # Initializes a new agent instance.
    # An agent MUST be initialized with a valid ADK::AgentDefinition object.
    #
    # @param definition [ADK::AgentDefinition] The agent definition object.
    # @param session_service [ADK::SessionService::Base, nil] Optional: Pre-initialized session service.
    # @param planner_override [ADK::Planner, nil] Optional: A specific planner instance to override the default.
    # @param sub_agents [Array<ADK::Agent>, nil] Optional: An array of pre-initialized sub-agent instances. If provided, these will be used instead of instantiating from `definition.sub_agent_names`.
    def initialize(definition:, session_service: nil, planner_override: nil, sub_agents: nil)
      unless definition.is_a?(ADK::AgentDefinition)
        raise ArgumentError,
              "Agent must be initialized with an ADK::AgentDefinition object. Received: #{definition.class}"
      end
      # Perform a more thorough check if it looks like a definition
      unless definition.respond_to?(:name) && definition.respond_to?(:description) &&
             definition.respond_to?(:instruction) && definition.respond_to?(:tool_names) &&
             definition.respond_to?(:model_name) && definition.respond_to?(:fallback_mode) &&
             definition.respond_to?(:mcp_servers)
        raise ArgumentError,
              'Provided definition object does not appear to be a valid ADK::AgentDefinition (missing required attributes/methods).'
      end

      @definition = definition
      @name = definition.name

      # --- Initialize Callbacks from Definition ---
      @before_agent_callback = definition.before_agent_callback
      @after_agent_callback = definition.after_agent_callback
      @before_model_callback = definition.before_model_callback
      @after_model_callback = definition.after_model_callback
      @before_tool_callback = definition.before_tool_callback
      @after_tool_callback = definition.after_tool_callback
      # --- End Initialize Callbacks ---

      # --- Initialize Authentication Config from Definition ---
      @auth_credential_names = definition.auth_credential_names || Set.new
      @auth_url_mappings = definition.auth_url_mappings || []
      @auth_scheme_assignments = definition.auth_scheme_assignments || {}
      @auth_credential_assignments = definition.auth_credential_assignments || {}
      # --- End Initialize Authentication Config ---

      # Check for direct self-references in the definition's sub_agent_names
      if definition.respond_to?(:sub_agent_names) && definition.sub_agent_names&.any?
        if definition.sub_agent_names.include?(@name)
          raise ADK::ConfigurationError, "Circular dependency detected: Agent '#{@name}' cannot include itself as a sub-agent"
        end
      end

      @description = definition.description
      @instruction = definition.instruction
      @model_name = definition.model_name || DEFAULT_MODEL
      @fallback_mode = definition.fallback_mode # Assumes :error is default in AgentDefinition
      @selected_tool_names = definition.tool_names.to_a # Tool names are directly from definition

      # MAS Attributes Initialization
      @parent_agent = nil # Will be set by parent if this is a sub-agent
      @sub_agents = []    # Will be populated if this agent has sub-agents defined

      # Tool paths are NOT loaded when initializing from definition; tools are expected to be globally registered.
      tool_paths_to_load = []
      # Tool classes are resolved via GlobalToolManager using names from definition
      tool_classes_to_load = definition.tool_names.map { |tn| ADK::GlobalToolManager.find_class(tn) }.compact

      if tool_classes_to_load.length != definition.tool_names.length
        found_tool_names = tool_classes_to_load.map { |tc| tc.tool_metadata[:name].to_sym rescue nil }.compact.to_set
        missing_tool_names = definition.tool_names.to_set - found_tool_names
        ADK.logger.warn("Agent '#{@name}': Could not find globally registered classes for tools: #{missing_tool_names.to_a.join(', ')}. These tools will be unavailable.")
      end

      @session_service = session_service || ADK.config.session_service # Simplified session service init

      # MCP servers are taken directly from the definition
      mcp_servers_config_str = definition.mcp_servers || []

      ADK.logger.info("Initializing agent '#{@name}' from provided definition object...")
      # -----------------------------------------
      @state = :idle # Initial state

      @tool_registry = ADK::ToolRegistry.new
      ADK.logger.debug("Agent '#{@name}' created its ToolRegistry instance: #{@tool_registry.object_id}")

      # 1. Discover tools from paths (if any) and update GlobalToolManager
      newly_discovered_tool_names = Set.new
      unless tool_paths_to_load.empty?
        initial_global_tools = ADK::GlobalToolManager.registered_tool_names.to_set
        _discover_and_load_tools(tool_paths_to_load)
        current_global_tools = ADK::GlobalToolManager.registered_tool_names.to_set
        newly_discovered_tool_names = current_global_tools - initial_global_tools
        ADK.logger.debug("[Agent Init '#{@name}'] Newly discovered tool names: #{newly_discovered_tool_names.to_a.inspect}")
      end

      # 2. Register tool *classes* passed directly (via add_tool_classes or from definition)
      ADK.logger.debug("[Agent Init '#{@name}'] Registering explicitly provided tool classes: #{tool_classes_to_load.inspect}")
      tool_classes_to_load.each do |tool_class|
        ADK.logger.debug("[Agent Init '#{@name}'] Processing class from builder: #{tool_class.inspect} (Object ID: #{tool_class.object_id})")
        register_tool_class(tool_class) # Use the agent's specific register method
      end

      # 3. Register newly *discovered* tool classes (from paths) that weren't explicitly passed
      ADK.logger.debug("[Agent Init '#{@name}'] Registering newly discovered tool classes (from paths): #{newly_discovered_tool_names.to_a.inspect}")
      newly_discovered_tool_names.each do |tool_name|
        tool_class = ADK::GlobalToolManager.find_class(tool_name)
        if tool_class
          # Check if already registered from step 2 before registering again
          unless @tool_registry.find_class(tool_name)
            ADK.logger.debug("[Agent Init '#{@name}'] Registering discovered tool #{tool_name.inspect} (class: #{tool_class})...")
            register_tool_class(tool_class) # Use the agent's specific register method
          else
            ADK.logger.debug("[Agent Init '#{@name}'] Skipping registration of discovered tool #{tool_name.inspect}, already registered via explicit classes.")
          end
        else
          # This case should be rare now due to _discover_and_load_tools logic
          ADK.logger.error("[Agent Init '#{@name}'] Failed to find class for discovered tool '#{tool_name}' in GlobalToolManager during agent init.")
        end
      end

      # 4. Register mandatory tools like CheckJobStatusTool if needed
      if defined?(Sidekiq)
        unless @tool_registry.find_class(:check_job_status)
          begin
            require_relative 'tools/check_job_status_tool' # Ensure loaded
            register_tool_class(ADK::Tools::CheckJobStatusTool)
            ADK.logger.info("Automatically registered CheckJobStatusTool for agent '#{@name}'.")
          rescue LoadError => e
            ADK.logger.error("Failed to load CheckJobStatusTool: #{e.message}")
          end
        end
      else
        ADK.logger.warn("Sidekiq not defined. Skipping automatic registration of CheckJobStatusTool for agent '#{@name}'.")
      end

      # --- Parse MCP Server Config (uses mcp_servers_config_str) ---
      if mcp_servers_config_str.is_a?(String) && !mcp_servers_config_str.strip.empty?
      # ... (rest of existing MCP parsing) ...
      elsif mcp_servers_config_str.is_a?(Array)
        @mcp_servers_config = mcp_servers_config_str # Already an array
      else
        ADK.logger.debug("Agent '#{@name}': No valid MCP server config provided. Defaulting to empty array.")
        @mcp_servers_config = []
      end

      @selected_tool_names = @definition.tool_names.to_a # Ensure this uses the definition
      @mcp_clients = [] # Store active MCP client instances

      @planner = planner_override || ADK::Planner.new(agent: self, model_name: @model_name)

      # Validate essential components using respond_to? for duck typing
      unless @session_service&.respond_to?(:get_session) && @session_service&.respond_to?(:append_event)
        raise ConfigurationError,
              "Agent '#{@name}' requires a valid Session Service (must respond to :get_session, :append_event)."
      end
      unless @planner&.respond_to?(:plan)
        raise ConfigurationError, "Agent '#{@name}' requires a valid Planner (must respond to :plan)."
      end

      ADK.logger.debug {
        "Agent '#{@name}' initialized with #{@tool_registry.tools.count} tools: [#{@tool_registry.tools.keys.join(', ')}]"
      }

      # MAS: Instantiate Sub-Agents or use provided ones
      if sub_agents && !sub_agents.empty?
        ADK.logger.info("Agent '#{@name}': Initializing with programmatically provided sub-agents (#{sub_agents.length} agents).")
        sub_agents.each do |sub_agent|
          unless sub_agent.is_a?(ADK::Agent)
            ADK.logger.warn("Agent '#{@name}': Item in provided sub_agents list is not an ADK::Agent. Skipping: #{sub_agent.inspect}")
            next
          end

          # Check for circular dependencies
          begin
            _check_circular_dependency(sub_agent.name)
          rescue ADK::ConfigurationError => e
            ADK.logger.error("Agent '#{@name}': #{e.message}")
            next # Skip this sub-agent
          end

          # Enforce single parent rule
          if sub_agent.parent_agent.nil?
            sub_agent.instance_variable_set(:@parent_agent, self)
          elsif sub_agent.parent_agent != self
            ADK.logger.error("Agent '#{@name}': Cannot adopt sub-agent '#{sub_agent.name}'. It already has a different parent: '#{sub_agent.parent_agent.name}'. Skipping this sub-agent.")
            next # Skip this sub-agent
          end
          # (If sub_agent.parent_agent == self, it's already correctly parented, do nothing extra here)

          # Verify session service consistency and assign if missing
          if sub_agent.instance_variable_get(:@session_service).nil? && @session_service
            ADK.logger.debug("Agent '#{@name}': Setting session_service for programmatic sub-agent '#{sub_agent.name}' to match parent.")
            sub_agent.instance_variable_set(:@session_service, @session_service)
          elsif sub_agent.instance_variable_get(:@session_service) != @session_service && @session_service # Warn if different and parent has one
            ADK.logger.warn("Agent '#{@name}': Programmatic sub-agent '#{sub_agent.name}' has a different session_service than parent.")
          end
          @sub_agents << sub_agent
          ADK.logger.info("Agent '#{@name}': Successfully instantiated and linked sub-agent '#{sub_agent.name}'.")
        end
        ADK.logger.info("Agent '#{@name}' finished linking programmatic sub-agents. Total sub-agents: #{@sub_agents.length}")
      elsif definition.respond_to?(:sub_agent_names) && definition.sub_agent_names&.any?
        ADK.logger.info("Agent '#{@name}' attempting to instantiate sub-agents from definition: #{definition.sub_agent_names.to_a.inspect}")
        definition.sub_agent_names.each do |sub_agent_name|
          begin
            # Check for circular dependencies before instantiation
            _check_circular_dependency(sub_agent_name)

            sub_agent_definition = ADK::GlobalDefinitionRegistry.get(sub_agent_name)
            unless sub_agent_definition
              ADK.logger.error("Agent '#{@name}': Could not find definition for sub-agent '#{sub_agent_name}' in GlobalDefinitionRegistry. Skipping.")
              next
            end

            ADK.logger.debug("Agent '#{@name}': Instantiating sub-agent '#{sub_agent_name}'...")
            sub_agent = ADK::Agent.new(definition: sub_agent_definition, session_service: @session_service)
            # Set parent link - enforce single parent rule
            if sub_agent.parent_agent.nil?
              sub_agent.instance_variable_set(:@parent_agent, self)
            elsif sub_agent.parent_agent != self # Should not happen if instantiated fresh, but defensive check
              ADK.logger.error("Agent '#{@name}': Newly instantiated sub-agent '#{sub_agent.name}' unexpectedly already has a different parent: '#{sub_agent.parent_agent.name}'. Skipping.")
              next # Skip this sub-agent
            end
            # (If sub_agent.parent_agent == self, it's already fine)

            @sub_agents << sub_agent
            ADK.logger.info("Agent '#{@name}': Successfully instantiated and linked sub-agent '#{sub_agent.name}'.")
          rescue ArgumentError => e # Catch errors from ADK::Agent.new (e.g. definition issues)
            ADK.logger.error("Agent '#{@name}': ArgumentError instantiating sub-agent '#{sub_agent_name}': #{e.message}")
          rescue StandardError => e
            ADK.logger.error("Agent '#{@name}': Unexpected error instantiating sub-agent '#{sub_agent_name}': #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
          end
        end
        ADK.logger.info("Agent '#{@name}' finished sub-agent instantiation. Total sub-agents: #{@sub_agents.length}")
      end
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
      tool_name = get_tool_name_from_class(tool_class) # Use the new helper
      # --- End Determine Tool Name --- #

      # Validate name was found
      unless tool_name # The helper returns nil if no valid name is found
        ADK.logger.error("Agent '#{name}' add_tool: Could not determine tool name for class #{tool_class}. Cannot add tool.")
        return false # Explicitly return false
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
        # Get name reliably using the new helper method
        tool_name = get_tool_name_from_class(tool_class)
        if tool_name
          @tool_registry.create_instance(tool_name)
        else
          # This branch should ideally not be hit frequently if registration robustly requires a name.
          ADK.logger.warn("Agent '#{name}': Skipping tool instance creation for class #{tool_class} as its name could not be determined post-registration.")
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
      ADK.logger.debug("[register_tool_class] Registering class: #{tool_class.inspect} (Object ID: #{tool_class.object_id})")
      # Basic validation
      unless tool_class < ADK::Tool
        ADK.logger.error("Agent '#{name}': Attempted to register invalid object (must inherit from ADK::Tool): #{tool_class.inspect}")
        return false
      end

      # Get name via metadata method
      tool_name = get_tool_name_from_class(tool_class) # Use the new helper
      ADK.logger.debug("[register_tool_class] Determined tool name: #{tool_name.inspect} for class #{tool_class.inspect}")

      unless tool_name # Helper returns nil if no valid name
        # Use logger method, not direct access
        ADK.logger.error("Agent '#{name}': Could not determine tool name for class #{tool_class}. Cannot register.") # Consistent error message
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

    # @return [ADK::Event] The final agent event.
    def run_task(session_id:, user_input:, session_service:)
      # --- Pre-execution Checks --- #
      unless running?
        err_msg = "Agent '#{name}' runtime is not active (stopped)."
        ADK.logger.error(err_msg)
        return ADK::Event.new(role: :agent, content: { status: :error, error_message: err_msg })
      end

      session = session_service.get_session(session_id: session_id)
      unless session
        err_msg = "Session not found: #{session_id}"
        ADK.logger.error(err_msg)
        # Even if session isn't found, return an event for consistency?
        return ADK::Event.new(role: :agent, content: { status: :error, error_message: err_msg })
      end
      # ----------------- #

      # Generate invocation_id for this run and create callback context
      invocation_id = SecureRandom.uuid
      callback_context = nil

      begin
        # Create callback context for callbacks to use
        callback_context = ADK::Callbacks::CallbackContext.new(
          agent_name: @name,
          invocation_id: invocation_id,
          session_id: session_id,
          user_id: session.user_id,
          app_name: session.app_name,
          session_service: session_service
        )

        # Execute before_agent_callback if defined
        if @definition.respond_to?(:before_agent_callback) && @definition.before_agent_callback
          ADK.logger.debug { "Agent '#{@name}': Executing before_agent_callback." }

          # Execute the callback and check if it returns a result
          begin
            override_result = @definition.before_agent_callback.call(callback_context)

            # If the callback returns a result (not nil), use it instead of normal execution
            if override_result
              ADK.logger.info { "Agent '#{@name}': before_agent_callback provided an override result." }

              # Apply any pending state changes from the callback
              unless callback_context.pending_state_delta.empty?
                callback_context.pending_state_delta.each do |key, value|
                  session_service.set_state(session_id: session_id, key: key, value: value)
                end
              end

              # Create an agent event with the override result
              final_agent_event = ADK::Event.new(role: :agent, content: override_result)
              session_service.append_event(session_id: session_id, event: final_agent_event)

              # Store the output if configured
              _store_output_in_session(final_agent_event, session_id, session_service)

              return final_agent_event
            end
          rescue StandardError => e
            ADK.logger.error { "Agent '#{@name}': Error in before_agent_callback: #{e.message}\n#{e.backtrace.join("\n")}" }
            return ADK::Event.new(role: :agent, content: {
                                    status: :error,
                                    error_message: "Error in before_agent_callback: #{e.message}"
                                  })
          end

          # Apply any pending state changes from the callback if execution continues
          unless callback_context.pending_state_delta.empty?
            callback_context.pending_state_delta.each do |key, value|
              session_service.set_state(session_id: session_id, key: key, value: value)
            end
            callback_context.clear_pending_state_delta!
          end
        end

        # --- Normal Execution Flow --- #
        # Create a user-message event for this turn
        user_message_event = ADK::Event.new(
          role: :user,
          content: user_input
        )
        session_service.append_event(session_id: session_id, event: user_message_event)

        # Use planner to generate a plan - pass invocation_id to support model callbacks
        plan = @planner.plan(user_input, invocation_id)

        # Execute the plan and get result
        result_hash = execute_plan(plan, session, session_service, invocation_id)

        # Create an agent event with the result
        final_agent_event = ADK::Event.new(role: :agent, content: result_hash[:last_result] || result_hash)
        session_service.append_event(session_id: session_id, event: final_agent_event)

        # Execute after_agent_callback if defined
        if @definition.respond_to?(:after_agent_callback) && @definition.after_agent_callback
          ADK.logger.debug { "Agent '#{@name}': Executing after_agent_callback." }

          begin
            # Execute the callback and let it modify the result if needed
            # Pass the actual result (last_result) to the callback, not the full hash with details
            modified_result = @definition.after_agent_callback.call(callback_context, result_hash[:last_result] || result_hash)

            # If the callback returned a modified result, use it
            if modified_result && modified_result != (result_hash[:last_result] || result_hash)
              ADK.logger.info { "Agent '#{@name}': after_agent_callback modified the result." }

              # Apply any pending state changes from the callback
              unless callback_context.pending_state_delta.empty?
                callback_context.pending_state_delta.each do |key, value|
                  session_service.set_state(session_id: session_id, key: key, value: value)
                end
              end

              # Create a new agent event with the modified result
              final_agent_event = ADK::Event.new(role: :agent, content: modified_result)
              session_service.append_event(session_id: session_id, event: final_agent_event)
            end
          rescue StandardError => e
            ADK.logger.error { "Agent '#{@name}': Error in after_agent_callback: #{e.message}\n#{e.backtrace.join("\n")}" }
            # Don't override the result completely on error, just log it
          end

          # Apply any pending state changes from the callback
          unless callback_context.pending_state_delta.empty?
            callback_context.pending_state_delta.each do |key, value|
              session_service.set_state(session_id: session_id, key: key, value: value)
            end
          end
        end

        # Store the output if configured
        _store_output_in_session(final_agent_event, session_id, session_service)

        # Return the final agent event
        final_agent_event
      rescue StandardError => e
        # Handle any other errors during execution
        ADK.logger.error { "Agent '#{@name}' runtime error: #{e.message}\n#{e.backtrace.join("\n")}" }
        ADK::Event.new(role: :agent, content: { status: :error, error_message: e.message })
      end
    end

    # Returns the root agent in the hierarchy (the topmost agent with no parent)
    # @return [ADK::Agent] The root agent in the hierarchy
    def root_agent
      return self if @parent_agent.nil?

      @parent_agent.root_agent
    end

    # Finds an agent with the given name in the hierarchy using DFS
    # @param name_sym [Symbol] The name of the agent to find (as a symbol)
    # @return [ADK::Agent, nil] The agent with the given name, or nil if not found
    def find_agent(name_sym)
      # Convert to symbol if string provided
      name_sym = name_sym.to_sym if name_sym.is_a?(String)

      # Check if this is the agent we're looking for
      return self if @name.to_sym == name_sym

      # Search sub-agents recursively
      @sub_agents.each do |sub_agent|
        found = sub_agent.find_agent(name_sym)
        return found if found
      end

      # Not found in this branch
      nil
    end

    # Finds a direct sub-agent with the given name
    # @param name_sym [Symbol] The name of the sub-agent to find
    # @return [ADK::Agent, nil] The sub-agent with the given name, or nil if not found
    def find_sub_agent(name_sym)
      # Convert to symbol if string provided
      name_sym = name_sym.to_sym if name_sym.is_a?(String)

      # Handle the case where @sub_agents is a hash (key: name => value: agent)
      if @sub_agents.is_a?(Hash)
        return @sub_agents[name_sym]
      end

      # Handle the case where @sub_agents is an array of Agent objects
      if @sub_agents.is_a?(Array)
        return @sub_agents.find { |sub_agent| sub_agent.name.to_sym == name_sym }
      end

      # No sub-agents or invalid type
      ADK.logger.warn("No sub-agents found or invalid sub_agents type: #{@sub_agents.class}")
      nil
    end

    # Transfers control to another agent, executing a task with the same session context.
    # This is a public version of the private transfer_to method
    #
    # @param target_agent_name [Symbol] The name of the target agent to delegate to
    # @param task [String] The task to delegate to the target agent
    # @param session_id [String] The current session ID
    # @param session_service [ADK::SessionService::Base] The session service instance
    # @return [Hash] A standard result hash { status: :success/:error, result/error_message: ... }
    def transfer_to(target_agent_name, task, session_id, session_service)
      # Call the private transfer_to method if it exists
      if self.private_methods.include?(:transfer_to)
        self.send(:transfer_to, target_agent_name, task, session_id, session_service)
      else
        # Fallback implementation that manually does what transfer_to would do

        # Verify the target agent is in the delegation_targets list if defined
        if @definition.respond_to?(:delegation_targets) && @definition.delegation_targets&.any?
          unless @definition.delegation_targets.include?(target_agent_name)
            error_msg = "Agent '#{target_agent_name}' is not in the delegation targets for '#{@name}'"
            ADK.logger.error(error_msg)
            return { status: :error, error_message: error_msg, error_class: 'InvalidDelegationTarget' }
          end
        end

        # Find the target agent in the agent hierarchy, starting from the root
        target_agent = root_agent.find_agent(target_agent_name)

        # If not found in hierarchy, try to instantiate from definition store
        unless target_agent
          ADK.logger.info("Target agent '#{target_agent_name}' not found in hierarchy. Attempting to load from definition store.")

          begin
            # Try to find the definition in the global registry
            target_def = ADK::GlobalDefinitionRegistry.find(target_agent_name)

            unless target_def
              error_msg = "Target agent definition '#{target_agent_name}' not found in registry"
              ADK.logger.error(error_msg)
              return { status: :error, error_message: error_msg, error_class: 'AgentDefinitionNotFound' }
            end

            # Create a new agent instance from the definition
            target_agent = ADK::Agent.new(
              definition: target_def,
              session_service: session_service
            )
          rescue StandardError => e
            error_msg = "Failed to instantiate target agent '#{target_agent_name}': #{e.message}"
            ADK.logger.error("#{error_msg}\n#{e.backtrace.join("\n")}")
            return { status: :error, error_message: error_msg, error_class: e.class.name }
          end
        end

        # Verify the target agent exists
        unless target_agent
          error_msg = "Target agent '#{target_agent_name}' not found in hierarchy or definition store"
          ADK.logger.error(error_msg)
          return { status: :error, error_message: error_msg, error_class: 'AgentNotFound' }
        end

        # Start the target agent if it's not already running
        target_agent.start unless target_agent.running?

        # Execute the delegated task
        begin
          ADK.logger.info("Executing delegated task on agent '#{target_agent_name}': #{task}")

          # Call run_task with the same session context
          result_event = target_agent.run_task(
            session_id: session_id,
            user_input: task,
            session_service: session_service
          )

          # Extract and format the result
          result_content = result_event.respond_to?(:content) ? result_event.content : result_event

          return {
            status: :success,
            target_agent: target_agent_name.to_s,
            result: result_content
          }
        rescue StandardError => e
          error_msg = "Error executing task on target agent '#{target_agent_name}': #{e.message}"
          ADK.logger.error("#{error_msg}\n#{e.backtrace.join("\n")}")
          return { status: :error, error_message: error_msg, error_class: e.class.name }
        end
      end
    end

    private

    # Build the agent-specific authentication configuration hash for ToolContext
    # @return [Hash, nil] The auth config hash or nil if no auth configured
    def build_agent_auth_config
      return nil if @auth_credential_names.empty? &&
                    @auth_url_mappings.empty? &&
                    @auth_scheme_assignments.empty? &&
                    @auth_credential_assignments.empty?

      {
        credential_names: @auth_credential_names,
        url_mappings: @auth_url_mappings,
        scheme_assignments: @auth_scheme_assignments,
        credential_assignments: @auth_credential_assignments
      }
    end

    # Helper method to consistently determine the tool name from a tool class.
    # Uses metadata, then deprecated @tool_name, then inferred_name.
    def get_tool_name_from_class(tool_class)
      return nil unless tool_class.is_a?(Class) && tool_class < ADK::Tool

      begin
        metadata = tool_class.tool_metadata
      rescue StandardError => e
        ADK.logger.error("Error calling tool_metadata on #{tool_class}: #{e.class} - #{e.message} - Backtrace: #{e.backtrace.first(3).join(' | ')}")
        metadata = {} # Default to empty hash if metadata call fails, for diagnosis
      end
      name = metadata[:name]&.to_sym

      if name.nil? || name == :''
        # Check deprecated @tool_name (instance variable on the class itself)
        if tool_class.instance_variable_defined?(:@tool_name)
          name = tool_class.instance_variable_get(:@tool_name)&.to_sym
          # ADK.logger.debug { "get_tool_name_from_class: Using name from deprecated @tool_name for #{tool_class}: #{name.inspect}" } if name
        end

        # If still no name, try inferred_name as a primary fallback if metadata[:name] is missing
        if (name.nil? || name == '') && tool_class.respond_to?(:inferred_name)
          name = tool_class.inferred_name
          # ADK.logger.debug { "get_tool_name_from_class: Using inferred_name for #{tool_class}: #{name.inspect}" } if name
        end
      end

      (name && name != :'') ? name : nil
    end

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
      ADK.logger.debug('Finished tool discovery.')
    end

    # --- REFACTORED: execute_plan now returns hash { details: [...], last_result: original_hash } ---
    # Executes a plan, logging tool request/result events via the session service.
    # @param plan [Hash, Array] The plan from the planner, either as a hash with :thought_process and :steps, or as an array of steps.
    # @param session [ADK::Session] The current session object.
    # @param session_service [Object] The session service instance.
    # @return [Hash] { details: Array<Hash>, last_result: Hash } or { details: Hash, last_result: nil } on planning errors.
    def execute_plan(plan, session, session_service, invocation_id)
      session_id = session.id

      # Extract steps based on the plan format
      steps = nil
      thought_process = nil

      # Handle new plan structure with thought_process and steps
      if plan.is_a?(Hash) && plan[:steps].is_a?(Array)
        steps = plan[:steps]
        thought_process = plan[:thought_process]
        ADK.logger.info("Plan thought process: #{thought_process}") if thought_process
      elsif plan.is_a?(Array)
        # For backward compatibility with old format
        steps = plan
      else
        msg = 'Invalid plan received from planner (not an Array or properly structured Hash).'
        ADK.logger.error("#{msg} Plan: #{plan.inspect}")
        return { details: { status: :error, error_message: msg }, last_result: nil }
      end

      # --- Continue with original logic, using 'steps' variable ---
      unless steps.is_a?(Array)
        msg = 'Invalid steps structure in plan (not an Array).'
        ADK.logger.error("#{msg} Steps: #{steps.inspect}")
        return { details: { status: :error, error_message: msg }, last_result: nil }
      end

      # --- Handle Empty Plan based on Fallback Mode ---
      if steps.empty?
        if @fallback_mode == :echo
          if @tool_registry.find_class(:echo)
            ADK.logger.warn("Plan is empty. Falling back to echo mode for session '#{session_id}'.")
            # Reconstruct the plan to be a single echo step
            # We need the original user input for this - fetch it from the session
            # Find the *last* user event in case of corrections/multiple turns
            original_user_input = session.events.reverse.find { |e|
              e.role == :user
            }&.content || '[Original input not found]'
            steps = [{ tool: :echo, params: { message: original_user_input } }]
            ADK.logger.debug("Reconstructed plan for echo fallback: #{steps.inspect}")
            # Now continue execution with the modified plan
          else
            # Echo tool not available, default to error mode
            msg = 'Planning failed and Echo fallback tool is not available to this agent.'
            ADK.logger.warn(msg)
            return { details: { status: :error, error_message: msg }, last_result: nil }
          end
        else # Default or :error mode
          msg = 'I cannot fulfill this request with the available tools (empty plan).'
          ADK.logger.warn(msg)
          return { details: { status: :error, error_message: msg }, last_result: nil }
        end
      end
      # --- End Handle Empty Plan ---

      ADK.logger.debug("Executing plan with #{steps.length} step(s) for session '#{session_id}': #{steps.inspect}")
      previous_step_result_hash = nil
      plan_execution_details = []
      last_successful_or_pending_result = nil # <-- Store the original last hash

      steps.each_with_index do |step, index|
        # Log the step type for clarity
        step_type_desc = step[:step_type] == :sequential_sub_agent ?
                        "sequential sub-agent '#{step[:sub_agent_name]}'" :
                        "tool '#{step[:tool]}'"
        ADK.logger.debug("Executing step #{index + 1}/#{steps.length}: #{step_type_desc}")
        ADK.logger.debug("  Step details: #{step.inspect}")
        ADK.logger.debug("  Input (result hash from previous step): #{previous_step_result_hash.inspect}")

        # --- Input Injection Logic (Updated for job_id) ---
        current_params = step[:params].dup
        current_params.transform_values! do |value|
          injection_value = nil
          if value.is_a?(String) && value.match?(/\[Result from step \d+\]|\[Result from previous step\]/i)
            if previous_step_result_hash && %i[success pending].include?(previous_step_result_hash[:status])
              # Prioritize :result, then :job_id (was workflow_id), then :message
              if previous_step_result_hash.key?(:result)
                prev_result = previous_step_result_hash[:result]
                if prev_result.is_a?(Hash) && prev_result.key?(:status) && prev_result.key?(:result) # AgentTool nested result
                  injection_value = prev_result[:result]
                  ADK.logger.debug('Injecting nested result...')
                else
                  injection_value = prev_result
                  ADK.logger.debug('Injecting direct result...')
                end
              elsif previous_step_result_hash.key?(:job_id) # <-- CHANGED from workflow_id
                injection_value = previous_step_result_hash[:job_id]
                ADK.logger.debug('Injecting job_id from previous step...')
              elsif previous_step_result_hash.key?(:message)
                injection_value = previous_step_result_hash[:message]
                ADK.logger.debug('Injecting message from previous step...')
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
        current_result_hash = execute_step(step_with_injected_params, session, session_service, invocation_id)

        # --- Sanitize for plan_details --- #
        sanitized_result_for_plan = {}
        if current_result_hash.is_a?(Hash)
          sanitized_result_for_plan[:status] = current_result_hash[:status]
          # Always include error keys, defaulting to nil if not present
          sanitized_result_for_plan[:error_message] = current_result_hash[:error_message] # Defaults to nil if key missing
          sanitized_result_for_plan[:error_class] = current_result_hash[:error_class] # Defaults to nil if key missing
          # Include other relevant keys if present
          sanitized_result_for_plan[:job_id] = current_result_hash[:job_id] if current_result_hash.key?(:job_id)
          sanitized_result_for_plan[:message] = current_result_hash[:message] if current_result_hash.key?(:message)
          # Only include :result value if it's simple
          result_val = current_result_hash[:result]
          if result_val.is_a?(String) || result_val.is_a?(Numeric) || [true, false, nil].include?(result_val)
            sanitized_result_for_plan[:result] = result_val
          elsif current_result_hash.key?(:result) # It exists but is complex
            sanitized_result_for_plan[:result] = '[Complex Result Structure]'
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
    # @param invocation_id [String] The ID of the current agent invocation.
    # @return [Hash] A standard result hash { status: ..., result/error_message/job_id: ... }.
    def execute_step(step, session, session_service, invocation_id = nil)
      session_id = session.id

      # --- Basic validation ---
      unless step.is_a?(Hash) && step[:tool] && step[:params].is_a?(Hash)
        error_msg = "Invalid step format. Expected { tool: :symbol, params: {...} }"
        ADK.logger.error(error_msg)
        return { status: :error, error_message: error_msg }
      end

      tool_name = step[:tool].to_sym
      params = step[:params].to_h

      # --- Intercept Delegation Tools (MAS) ---
      # If the model outputs "agent_transfer_to_xyz", map it to "delegate_task"
      if tool_name.to_s.start_with?('agent_transfer_to_')
        target_agent_name = tool_name.to_s.sub('agent_transfer_to_', '')
        ADK.logger.info("Intercepted delegation tool '#{tool_name}'. Mapping to 'delegate_task' for target '#{target_agent_name}'.")
        
        # Remap tool name
        tool_name = :delegate_task
        
        # Remap params: ensure target_agent_name is set
        params[:target_agent_name] = target_agent_name
        
        # Ensure 'task' param exists (model should provide it, but handle aliasing/defaults if needed)
        # The prompt says: - task (string, required)
        unless params.key?(:task)
          # Fallback: if model used a different key like 'message' or 'input', map it to 'task'
          if params.key?(:message)
            params[:task] = params.delete(:message)
          elsif params.key?(:input)
            params[:task] = params.delete(:input)
          end
        end
      end
      # --- End Delegation Interception ---

      # --- Get the tool from our registry ---
      tool = @tool_registry.create_instance(tool_name)
      unless tool
        error_msg = "Tool '#{tool_name}' not found in available tools."
        ADK.logger.error(error_msg)
        return { status: :error, error_message: error_msg }
      end

      # --- Prepare tool context with invocation_id and auth config ---
      tool_context = ADK::ToolContext.new(
        session_id: session.id,
        user_id: session.user_id,
        app_name: session.app_name,
        session_service: session_service,
        tool_registry: @tool_registry,
        invocation_id: invocation_id,
        agent_auth_config: build_agent_auth_config
      )

      # --- Log the tool request event ---
      tool_request_event = ADK::Event.new(
        role: :tool_request,
        tool_name: tool_name,
        content: params
      )
      session_service.append_event(session_id: session_id, event: tool_request_event)

      # --- Execute before_tool_callback if defined ---
      if @before_tool_callback.is_a?(Proc)
        ADK.logger.debug { "Agent '#{@name}': Executing before_tool_callback for tool '#{tool_name}'." }

        begin
          # Execute the callback and check if it returns a result
          override_result = @before_tool_callback.call(tool, params.dup, tool_context)

          # If the callback returns a result (not nil), use it instead of normal tool execution
          if override_result
            ADK.logger.info { "Agent '#{@name}': before_tool_callback provided an override result for tool '#{tool_name}'." }

            # Create a tool result event with the override result and any state changes
            tool_result_event = ADK::Event.new(
              role: :tool_result,
              tool_name: tool_name,
              content: override_result,
              state_delta: tool_context.pending_state_delta
            )
            session_service.append_event(session_id: session_id, event: tool_result_event)

            return override_result
          end
        rescue StandardError => e
          ADK.logger.error { "Agent '#{@name}': Error in before_tool_callback for tool '#{tool_name}': #{e.message}\n#{e.backtrace.join("\n")}" }

          error_result = {
            status: :error,
            error_message: "Error in before_tool_callback: #{e.message}",
            error_class: e.class.name
          }

          # Create a tool result event with the error
          tool_result_event = ADK::Event.new(
            role: :tool_result,
            tool_name: tool_name,
            content: error_result,
            state_delta: tool_context.pending_state_delta
          )
          session_service.append_event(session_id: session_id, event: tool_result_event)

          return error_result
        end
      end

      # --- Execute the tool ---
      begin
        ADK.logger.debug { "Executing tool '#{tool_name}' with params #{params.inspect}" }
        final_tool_name_to_execute = tool_name

        # For delegate_task tool, capture the delegate to show in logs
        if tool_name == :delegate_task && params[:agent_name]
          final_tool_name_to_execute = "#{tool_name} -> #{params[:agent_name]}"
        end

        result = tool.execute(params, tool_context)

        # --- Execute after_tool_callback if defined ---
        if @after_tool_callback.is_a?(Proc)
          ADK.logger.debug { "Agent '#{@name}': Executing after_tool_callback for tool '#{final_tool_name_to_execute}'." }

          begin
            # Execute the callback and let it modify the result if needed
            modified_result = @after_tool_callback.call(tool, params.dup, tool_context, result.dup)

            # If the callback returned a modified result, use it
            if modified_result && modified_result != result
              ADK.logger.info { "Agent '#{@name}': after_tool_callback modified the result for tool '#{final_tool_name_to_execute}'." }
              result = modified_result
            end
          rescue StandardError => e
            ADK.logger.error { "Agent '#{@name}': Error in after_tool_callback for tool '#{final_tool_name_to_execute}': #{e.message}\n#{e.backtrace.join("\n")}" }
            # Don't override the result completely on error, just log it
          end
        end

        # --- Log the tool result event ---
        tool_result_event = ADK::Event.new(
          role: :tool_result,
          tool_name: tool_name,
          content: result,
          state_delta: tool_context.pending_state_delta
        )
        session_service.append_event(session_id: session_id, event: tool_result_event)

        return result
      rescue StandardError => e
        ADK.logger.error { "Error executing tool '#{tool_name}': #{e.message}\n#{e.backtrace.join("\n")}" }

        error_result = {
          status: :error,
          error_message: "Tool '#{tool_name}' execution error: #{e.message}",
          exception: e.class.name
        }

        # Create a tool result event with the error
        tool_result_event = ADK::Event.new(
          role: :tool_result,
          tool_name: tool_name,
          content: error_result
        )
        session_service.append_event(session_id: session_id, event: tool_result_event)

        return error_result
      end
    end

    # Connects to all configured MCP servers.
    def connect_mcp_servers
      # Return early if no MCP servers configured
      return if @mcp_servers_config.nil? || @mcp_servers_config.empty?

      @mcp_servers_config.each do |config|
        # Transform keys to symbols for the client
        symbolized_config = config.transform_keys(&:to_sym)
        ADK.logger.info("Attempting to connect to MCP server: #{symbolized_config.inspect}")
        begin
          # --- FIXED: Check using STRING key 'type' --- >
          unless %w[stdio sse].include?(symbolized_config[:type])
            # --- FIXED: Log the actual value found using string key ---\
            ADK.logger.error("Unsupported MCP server type specified: #{symbolized_config[:type].inspect}. Skipping configuration: #{symbolized_config.inspect}")
            next # Skip to the next server config
          end
          # <-----------------------------

          # --- NEW: Explicitly convert known string type values to symbols ---
          if symbolized_config[:type] == 'stdio'
            symbolized_config[:type] = :stdio
          elsif symbolized_config[:type] == 'sse'
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
      return if @mcp_clients.nil? || @mcp_clients.empty?

      @mcp_clients.each do |client|
        begin
          ADK.logger.info('Disconnecting MCP client...')
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

    # --- Session Service Initialization Helpers --- #
    def initialize_session_service_from_definition
      # When initialized from definition (worker), rely on ADK global config by default
      # unless a specific service was passed in.
      ADK.config.session_service
    end

    def initialize_session_service_from_args
      # When initialized from args (direct use), rely on ADK global config.
      ADK.config.session_service
    end
    # --- End Session Service Initialization Helpers --- #

    # Helper method to check for circular dependencies in the agent hierarchy
    # @param new_sub_agent_name [Symbol] The name of the new sub-agent to check for cycles
    # @raise [ADK::ConfigurationError] If a circular dependency is detected
    private def _check_circular_dependency(new_sub_agent_name)
      # Direct self-reference check
      if new_sub_agent_name == @name
        raise ADK::ConfigurationError, "Circular dependency detected: Agent '#{@name}' cannot include itself as a sub-agent"
      end

      # Check if the sub-agent would create an indirect circular reference
      # by traversing up the parent chain (backwards check)
      current_agent = self
      ancestry_path = [@name]

      while (parent = current_agent.parent_agent)
        # If any parent has the same name as the new sub-agent, it's a circular reference
        if parent.name == new_sub_agent_name
          circular_path = [new_sub_agent_name] + ancestry_path
          raise ADK::ConfigurationError, "Circular dependency detected: #{circular_path.join(' → ')}"
        end

        ancestry_path.unshift(parent.name)
        current_agent = parent
      end
    end

    # --- MAS: Store result in session state if output_key is defined --- #
    def _store_output_in_session(event, session_id, session_service)
      return unless @definition.respond_to?(:output_key) && @definition.output_key && event

      # Get the content, which now should be the last_result only
      output_value = event.content

      # If the result has plan_details missing, add it (for backward compatibility with tests)
      # This may happen when execute_plan changed to return {details: [...], last_result: {...}}
      if !output_value.key?(:plan_details) && !output_value.key?('plan_details')
        # Create a rich result that includes plan_details if possible
        result_with_details = {}
        result_with_details.merge!(output_value)

        # Try to add a placeholder plan_details array if missing
        result_with_details[:plan_details] = []

        # Use this enhanced result
        output_value = result_with_details
      end

      serialized_value = begin
        # If the value is a Hash or Array, deep transform keys and symbolized values
        if output_value.is_a?(Hash) || output_value.is_a?(Array)
          # Convert to JSON and back to remove symbols
          JSON.parse(output_value.to_json)
        else
          # For other values, just pass through
          output_value
        end
      rescue => e
        # If serialization fails, log and return the original
        ADK.logger.warn("Agent '#{@name}': Failed to serialize output value: #{e.message}. Using original value.")
        output_value
      end

      ADK.logger.info("Agent '#{@name}' storing output to session state with key '#{@definition.output_key}' for session '#{session_id}'.")

      begin
        # Ensure session_service has set_state. Add if missing for base/inmemory.
        if session_service.respond_to?(:set_state)
          session_service.set_state(session_id: session_id, key: @definition.output_key, value: serialized_value)
        else
          ADK.logger.warn("Agent '#{@name}': Session service does not support :set_state. Cannot store output for key '#{@definition.output_key}'.")
        end
      rescue StandardError => e
        ADK.logger.error("Agent '#{@name}': Failed to set state for key '#{@definition.output_key}' in session '#{session_id}': #{e.class} - #{e.message}")
      end
    end
    # --- End MAS State Management ---
  end # End Agent class
end # End ADK module
