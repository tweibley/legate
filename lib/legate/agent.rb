# File: lib/legate/agent.rb
# frozen_string_literal: true

require 'logger'
require 'concurrent'
require 'did_you_mean' # for "did you mean" suggestions on unknown tool names
require 'pathname' # Added for path manipulation
require_relative 'tool_context'
# NOTE: Requires are handled by lib/legate.rb
require_relative 'planner'
require_relative 'tool_registry'
require_relative 'agent_definition'
require_relative 'mcp/client'
require_relative 'mcp/tool_wrapper'
require 'forwardable'
require 'json'
require_relative 'global_definition_registry'
require_relative 'global_tool_manager' # Added
require_relative 'tool_loader'
require 'securerandom'

module Legate
  # Represents the static definition of an Agent, including its name,
  # description, instructions, tools, and model configuration.

  # Agent class represents an AI agent that can perform tasks using tools and a planner.
  # It operates within the context of a session managed by a SessionService.
  class Agent
    DEFAULT_MODEL = 'gemini-3.5-flash' # Default Gemini model (supports structured output)

    attr_reader :name, :description, :planner, :logger, :model_name, :state, :tool_registry, :fallback_mode, :instruction, :definition, :session_service, :sub_agents # Added session_service to attr_reader
    # MAS Attributes
    attr_reader :parent_agent # The parent agent in a hierarchy, if any   # A collection of sub-agents

    # --- Callback Instance Variables ---
    attr_reader :before_agent_callback, :after_agent_callback,
                :before_model_callback, :after_model_callback,
                :before_tool_callback, :after_tool_callback

    # --- End Callback Instance Variables ---

    # --- Authentication Instance Variables ---
    attr_reader :auth_credential_names, :auth_url_mappings,
                :auth_scheme_assignments, :auth_credential_assignments

    # --- End Authentication Instance Variables ---

    # --- Class Method for Configuration DSL ---
    # Provides a block-based DSL for configuring and creating an Agent instance.
    #
    # The DSL is positional (method-call style), not assignment. The resulting
    # definition is registered globally in {GlobalDefinitionRegistry} as a side
    # effect, then returned.
    #
    # @example
    #   definition = Legate::Agent.define do |a|
    #     a.name :news_agent
    #     a.description 'Summarizes news articles.'
    #     a.instruction 'Summarize the article the user provides.'
    #     a.model_name 'gemini-3.5-flash'
    #     a.use_tool :echo
    #     a.fallback_mode :echo
    #   end
    #
    # @yieldparam a [Legate::AgentDefinition::DefinitionProxy] The proxy object to configure the definition.
    # @return [Legate::AgentDefinition] The validated, globally-registered definition.
    # @raise [ArgumentError] if the block is not provided or required attributes are missing.
    def self.define(&block)
      raise ArgumentError, 'Legate::Agent.define requires a block.' unless block_given?

      # 1. Create a new AgentDefinition
      definition = Legate::AgentDefinition.new

      # 2. Evaluate the block within the definition's proxy DSL
      # Use the definition instance's define method which takes the block
      # This also handles internal validation via validate!
      begin
        definition.define(&block)
      rescue ArgumentError => e
        # Re-raise DSL validation errors immediately
        raise e
      end

      # 3. Register the validated definition in the GlobalDefinitionRegistry
      begin
        GlobalDefinitionRegistry.register(definition)
        agent_name = definition.instance_variable_get(:@name)
        Legate.logger.info("Agent definition '#{agent_name}' registered in GlobalDefinitionRegistry.")
      rescue ArgumentError => e
        agent_name_for_log = definition.instance_variable_get(:@name) || 'unknown'
        Legate.logger.error("Failed to register definition '#{agent_name_for_log}': #{e.class} - #{e.message}")
        raise e
      rescue StandardError => e
        agent_name_for_log = definition.instance_variable_get(:@name) || 'unknown'
        Legate.logger.error("Unexpected error registering definition '#{agent_name_for_log}': #{e.class} - #{e.message}")
        raise Legate::StoreError, "Unexpected error registering definition '#{agent_name_for_log}': #{e.message}"
      end

      definition # Return the definition instance
    end
    # --- End Class Method ---

    # Initializes a new agent instance.
    # An agent MUST be initialized with a valid Legate::AgentDefinition object.
    #
    # @param definition [Legate::AgentDefinition] The agent definition object.
    # @param session_service [Legate::SessionService::Base, nil] Optional: Pre-initialized session service.
    # @param planner_override [Legate::Planner, nil] Optional: A specific planner instance to override the default.
    # @param sub_agents [Array<Legate::Agent>, nil] Optional: An array of pre-initialized sub-agent instances. If provided, these will be used instead of instantiating from `definition.sub_agent_names`.
    def initialize(definition:, session_service: nil, planner_override: nil, sub_agents: nil)
      unless definition.is_a?(Legate::AgentDefinition)
        raise ArgumentError,
              "Agent must be initialized with an Legate::AgentDefinition object. Received: #{definition.class}"
      end
      # Perform a more thorough check if it looks like a definition
      unless definition.respond_to?(:name) && definition.respond_to?(:description) &&
             definition.respond_to?(:instruction) && definition.respond_to?(:tool_names) &&
             definition.respond_to?(:model_name) && definition.respond_to?(:fallback_mode) &&
             definition.respond_to?(:mcp_servers)
        raise ArgumentError,
              'Provided definition object does not appear to be a valid Legate::AgentDefinition (missing required attributes/methods).'
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
      raise Legate::ConfigurationError, "Circular dependency detected: Agent '#{@name}' cannot include itself as a sub-agent" if definition.respond_to?(:sub_agent_names) && definition.sub_agent_names&.any? && definition.sub_agent_names.include?(@name)

      @description = definition.description
      @instruction = definition.instruction
      @model_name = definition.model_name || DEFAULT_MODEL
      @fallback_mode = definition.fallback_mode # Assumes :error is default in AgentDefinition
      @selected_tool_names = definition.tool_names.to_a # Tool names are directly from definition

      # MAS Attributes Initialization
      @parent_agent = nil # Will be set by parent if this is a sub-agent
      @sub_agents = []    # Will be populated if this agent has sub-agents defined

      @session_service = session_service || Legate.config.session_service
      @state = :idle

      Legate.logger.info("Initializing agent '#{@name}' from provided definition object...")

      setup_tool_registry(definition)
      setup_mcp_config(definition)

      @selected_tool_names = @definition.tool_names.to_a
      @mcp_manager = Legate::Mcp::ConnectionManager.new(
        tool_registry: @tool_registry,
        selected_tool_names: @selected_tool_names,
        agent_name: @name
      )
      @plan_executor = Legate::PlanExecutor.new(self)

      @planner = planner_override || Legate::Planner.new(agent: self, model_name: @model_name)

      unless @session_service&.respond_to?(:get_session) && @session_service.respond_to?(:append_event)
        raise ConfigurationError,
              "Agent '#{@name}' requires a valid Session Service (must respond to :get_session, :append_event)."
      end
      raise ConfigurationError, "Agent '#{@name}' requires a valid Planner (must respond to :plan)." unless @planner&.respond_to?(:plan)

      Legate.logger.debug {
        "Agent '#{@name}' initialized with #{@tool_registry.tools.count} tools: [#{@tool_registry.tools.keys.join(', ')}]"
      }

      setup_sub_agents(definition, sub_agents)
    end

    # Adds a tool instance OR class to the agent's registry
    # @param tool [Legate::Tool, Class<Legate::Tool>] The tool instance or class to add
    # @return [Boolean] True if the tool was added, false otherwise
    def add_tool(tool)
      # Check if it's a valid tool instance or class
      is_tool_instance = tool.is_a?(Legate::Tool)
      is_tool_class = tool.is_a?(Class) && tool < Legate::Tool

      unless is_tool_instance || is_tool_class
        Legate.logger.error("Agent '#{name}' add_tool: Attempted to add invalid tool: #{tool.inspect}")
        return false
      end

      # Determine the actual tool class
      tool_class = is_tool_class ? tool : tool.class

      # --- Determine Tool Name with Fallbacks --- #
      tool_name = get_tool_name_from_class(tool_class) # Use the new helper
      # --- End Determine Tool Name --- #

      # Validate name was found
      unless tool_name # The helper returns nil if no valid name is found
        Legate.logger.error("Agent '#{name}' add_tool: Could not determine tool name for class #{tool_class}. Cannot add tool.")
        return false # Explicitly return false
      end

      # Check for overwrite
      Legate.logger.warn("Agent '#{name}': Tool '#{tool_name}' already added. Overwriting with class #{tool_class}.") if @tool_registry.find_class(tool_name)

      # Register the class using the determined name
      Legate.logger.debug("Agent '#{name}' add_tool: Registering tool_name=#{tool_name.inspect} with class=#{tool_class.inspect} in registry=#{@tool_registry.object_id}")
      registration_result = @tool_registry.register(tool_name, tool_class)
      Legate.logger.debug("Agent '#{name}' add_tool: Registry after registration for #{tool_name.inspect}: #{@tool_registry.tools.keys.inspect}")

      # Explicitly return the boolean result from the registry
      registration_result
    end

    # Returns the list of tools registered with this agent
    # @return [Array<Legate::Tool>] Array of tool instances
    def tools
      @tool_registry.tools.values.map do |tool_class|
        # Get name reliably using the new helper method
        tool_name = get_tool_name_from_class(tool_class)
        if tool_name
          @tool_registry.create_instance(tool_name)
        else
          # This branch should ideally not be hit frequently if registration robustly requires a name.
          Legate.logger.warn("Agent '#{name}': Skipping tool instance creation for class #{tool_class} as its name could not be determined post-registration.")
          nil
        end
      end.compact
    end

    # Finds a tool instance by name
    # @param tool_name [Symbol] The name of the tool to find
    # @return [Legate::Tool, nil] The tool instance if found, nil otherwise
    def find_tool(tool_name)
      @tool_registry.create_instance(tool_name.to_sym)
    end

    # Registers a tool class with the agent's specific registry.
    # @param tool_class [Class] The tool class to register (must inherit from Legate::Tool).
    # @return [Boolean] True if registration was successful, false otherwise.
    def register_tool_class(tool_class)
      Legate.logger.debug("[register_tool_class] Registering class: #{tool_class.inspect} (Object ID: #{tool_class.object_id})")
      # Basic validation
      unless tool_class < Legate::Tool
        Legate.logger.error("Agent '#{name}': Attempted to register invalid object (must inherit from Legate::Tool): #{tool_class.inspect}")
        return false
      end

      # Get name via metadata method
      tool_name = get_tool_name_from_class(tool_class) # Use the new helper
      Legate.logger.debug("[register_tool_class] Determined tool name: #{tool_name.inspect} for class #{tool_class.inspect}")

      unless tool_name # Helper returns nil if no valid name
        # Use logger method, not direct access
        Legate.logger.error("Agent '#{name}': Could not determine tool name for class #{tool_class}. Cannot register.") # Consistent error message
        return false
      end

      Legate.logger.warn("Agent '#{name}': Tool '#{tool_name}' already registered. Overwriting.") if @tool_registry.find_class(tool_name)

      # Register with the instance registry
      @tool_registry.register(tool_name, tool_class)
      true # Return true on success
    end

    # --- Runtime State Methods (unchanged) ---
    def start
      return if running? # Prevent starting multiple times

      Legate.logger.info("Starting agent '#{name}' runtime...")
      @state = :running

      # Connect to MCP Servers and register tools
      connect_mcp_servers

      Legate.logger.info("Agent '#{name}' runtime started.")
    end

    def stop
      return unless running?

      Legate.logger.info("Stopping agent '#{name}' runtime...")
      @state = :stopped

      # Disconnect MCP Clients
      disconnect_mcp_servers

      Legate.logger.info("Agent '#{name}' runtime stopped.")
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
    # @return [Class<Legate::Tool>, nil]
    def find_tool_class(tool_name)
      @tool_registry.find_class(tool_name.to_sym)
    end

    # One-shot convenience runner: starts the agent if needed, creates (or
    # reuses) a session on the agent's own session service, runs the task, and
    # returns the final event. The friendly path over the explicit
    # start/create_session/run_task/stop dance.
    #
    #   answer = agent.ask('What is 2 + 2?').answer
    #   agent.ask('Search ruby') { |event| puts event.role } # live progress (R3)
    #
    # Lazy-starts but does NOT auto-stop — stopping tears down MCP connections
    # that are costly to re-establish, and an agent typically answers many asks.
    # Call #stop when done (or let process exit reclaim it).
    #
    # @param user_input [String] the user's request
    # @param user_id [String] identity for the auto-created session
    # @param session_id [String, nil] reuse an existing session to continue a conversation
    # @yieldparam event [Legate::Event] optional live progress (forwarded to run_task's on_event)
    # @return [Legate::Event] the final agent event (use #answer / #success?)
    def ask(user_input, user_id: 'default', session_id: nil, &on_event)
      start unless running?
      session_id ||= @session_service.create_session(app_name: name.to_s, user_id: user_id).id
      run_task(session_id: session_id, user_input: user_input,
               session_service: @session_service, on_event: on_event)
    end

    # @param on_event [Proc, nil] optional callback invoked with each
    #   Legate::Event as it is appended during the run (user, tool_request,
    #   tool_result, final agent) — for streaming progress (R3). The final event
    #   is still returned; non-streaming callers pass nothing and are unaffected.
    # @return [Legate::Event] The final agent event.
    def run_task(session_id:, user_input:, session_service:, on_event: nil)
      # --- Pre-execution Checks --- #
      unless running?
        err_msg = "Agent '#{name}' is not running. Call agent.start before run_task, " \
                  'or use agent.ask (which starts automatically).'
        Legate.logger.error(err_msg)
        return Legate::Event.new(role: :agent, content: { status: :error, error_message: err_msg })
      end

      session = session_service.get_session(session_id: session_id)
      unless session
        err_msg = "Session not found: #{session_id}"
        Legate.logger.error(err_msg)
        # Even if session isn't found, return an event for consistency?
        return Legate::Event.new(role: :agent, content: { status: :error, error_message: err_msg })
      end
      # ----------------- #

      # Generate invocation_id for this run and create callback context
      invocation_id = SecureRandom.uuid
      callback_context = nil

      # R3: stream lifecycle events to the optional on_event callback as they're
      # appended. Torn down in the ensure below so the subscription can't leak.
      event_subscription = subscribe_events(session_service, session_id, on_event)

      begin
        # Create callback context for callbacks to use
        callback_context = Legate::Callbacks::CallbackContext.new(
          agent_name: @name,
          invocation_id: invocation_id,
          session_id: session_id,
          user_id: session.user_id,
          app_name: session.app_name,
          session_service: session_service
        )

        # Execute before_agent_callback if defined
        if @definition.respond_to?(:before_agent_callback) && @definition.before_agent_callback
          Legate.logger.debug { "Agent '#{@name}': Executing before_agent_callback." }

          # Execute the callback and check if it returns a result
          begin
            override_result = @definition.before_agent_callback.call(callback_context)

            # If the callback returns a result (not nil), use it instead of normal execution
            if override_result
              Legate.logger.info { "Agent '#{@name}': before_agent_callback provided an override result." }

              # Apply any pending state changes from the callback
              apply_pending_state(callback_context, session_id, session_service)

              # Create an agent event with the override result
              final_agent_event = Legate::Event.new(role: :agent, content: override_result)
              session_service.append_event(session_id: session_id, event: final_agent_event)

              # Store the output if configured
              _store_output_in_session(final_agent_event, session_id, session_service)

              return final_agent_event
            end
          rescue StandardError => e
            Legate.logger.error { "Agent '#{@name}': Error in before_agent_callback: #{e.message}\n#{e.backtrace.join("\n")}" }
            return record_error_event(session_id, session_service, "Error in before_agent_callback: #{e.message}")
          end

          # Apply any pending state changes from the callback if execution continues
          apply_pending_state(callback_context, session_id, session_service, clear: true)
        end

        # --- Normal Execution Flow --- #
        # Create a user-message event for this turn
        user_message_event = Legate::Event.new(
          role: :user,
          content: user_input
        )
        session_service.append_event(session_id: session_id, event: user_message_event)

        # Produce the result via the configured strategy. :plan (default) asks
        # the planner for one upfront plan and runs it; :react drives an agentic
        # observe->think->act loop. Both return the same { details:, last_result: }
        # shape, so the final-event handling below is strategy-agnostic.
        result_hash =
          if react_strategy?
            run_react_loop(user_input, session, session_service, invocation_id)
          else
            plan = @planner.plan(user_input, invocation_id)
            execute_plan(plan, session, session_service, invocation_id)
          end

        # Create an agent event with the result
        final_agent_event = Legate::Event.new(role: :agent, content: result_hash[:last_result] || result_hash)
        session_service.append_event(session_id: session_id, event: final_agent_event)

        # Execute after_agent_callback if defined
        if @definition.respond_to?(:after_agent_callback) && @definition.after_agent_callback
          Legate.logger.debug { "Agent '#{@name}': Executing after_agent_callback." }

          begin
            # Execute the callback and let it modify the result if needed
            # Pass the actual result (last_result) to the callback, not the full hash with details
            modified_result = @definition.after_agent_callback.call(callback_context, result_hash[:last_result] || result_hash)

            # If the callback returned a modified result, use it
            if modified_result && modified_result != (result_hash[:last_result] || result_hash)
              Legate.logger.info { "Agent '#{@name}': after_agent_callback modified the result." }

              # Create a new agent event with the modified result
              final_agent_event = Legate::Event.new(role: :agent, content: modified_result)
              session_service.append_event(session_id: session_id, event: final_agent_event)
            end
          rescue StandardError => e
            Legate.logger.error { "Agent '#{@name}': Error in after_agent_callback: #{e.message}\n#{e.backtrace.join("\n")}" }
            # Don't override the result completely on error, just log it
          end

          # Apply the callback's pending state changes exactly once (whether or
          # not it modified the result).
          apply_pending_state(callback_context, session_id, session_service)
        end

        # Store the output if configured
        _store_output_in_session(final_agent_event, session_id, session_service)

        # Return the final agent event
        final_agent_event
      rescue StandardError => e
        # Handle any other errors during execution. Record the failure in the
        # session so its history reflects what the caller saw (the success and
        # callback paths already append their events).
        Legate.logger.error { "Agent '#{@name}' runtime error: #{e.message}\n#{e.backtrace.join("\n")}" }
        record_error_event(session_id, session_service, e.message)
      ensure
        session_service.unsubscribe(event_subscription) if event_subscription && session_service.respond_to?(:unsubscribe)
      end
    end

    # Subscribes on_event (if given) to the session's appended events for the
    # duration of a run. Returns a handle for #run_task's ensure to remove, or
    # nil when there's nothing to stream / the service has no pub/sub.
    def subscribe_events(session_service, session_id, on_event)
      return nil unless on_event && session_service.respond_to?(:subscribe)

      session_service.subscribe(session_id, &on_event)
    end
    private :subscribe_events

    # Flushes a callback's accumulated state delta into the session via the
    # session service. Optionally clears the delta afterward (when execution
    # continues and the same context will be reused).
    def apply_pending_state(callback_context, session_id, session_service, clear: false)
      return if callback_context.pending_state_delta.empty?

      callback_context.pending_state_delta.each do |key, value|
        session_service.set_state(session_id: session_id, key: key, value: value)
      end
      callback_context.clear_pending_state_delta! if clear
    end

    # Builds an agent error event, records it in the session history (best-effort:
    # a failed append must not mask the original error), and returns it.
    # @return [Legate::Event] the error event
    def record_error_event(session_id, session_service, message)
      event = Legate::Event.new(role: :agent, content: { status: :error, error_message: message })
      begin
        session_service.append_event(session_id: session_id, event: event)
      rescue StandardError => e
        Legate.logger.error { "Agent '#{@name}': failed to record error event in session: #{e.message}" }
      end
      event
    end

    # Returns the root agent in the hierarchy (the topmost agent with no parent)
    # @return [Legate::Agent] The root agent in the hierarchy
    def root_agent
      return self if @parent_agent.nil?

      @parent_agent.root_agent
    end

    # Finds an agent with the given name in the hierarchy using DFS
    # @param name_sym [Symbol] The name of the agent to find (as a symbol)
    # @return [Legate::Agent, nil] The agent with the given name, or nil if not found
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
    # @return [Legate::Agent, nil] The sub-agent with the given name, or nil if not found
    def find_sub_agent(name_sym)
      # Convert to symbol if string provided
      name_sym = name_sym.to_sym if name_sym.is_a?(String)

      return nil unless @sub_agents.is_a?(Array)

      @sub_agents.find { |sub_agent| sub_agent.name.to_sym == name_sym }
    end

    # Transfers control to another agent, executing a task with the same session context.
    # This is a public version of the private transfer_to method
    #
    # @param target_agent_name [Symbol] The name of the target agent to delegate to
    # @param task [String] The task to delegate to the target agent
    # @param session_id [String] The current session ID
    # @param session_service [Legate::SessionService::Base] The session service instance
    # @return [Hash] A standard result hash { status: :success/:error, result/error_message: ... }
    def transfer_to(target_agent_name, task, session_id, session_service)
      # Verify the target agent is in the delegation_targets list if defined
      if @definition.respond_to?(:delegation_targets) && @definition.delegation_targets&.any? && !@definition.delegation_targets.include?(target_agent_name)
        error_msg = "Agent '#{target_agent_name}' is not in the delegation targets for '#{@name}'"
        Legate.logger.error(error_msg)
        return { status: :error, error_message: error_msg, error_class: 'InvalidDelegationTarget' }
      end

      # Find the target agent in the agent hierarchy, starting from the root
      target_agent = root_agent.find_agent(target_agent_name)

      # If not found in hierarchy, try to instantiate from definition store
      unless target_agent
        Legate.logger.info("Target agent '#{target_agent_name}' not found in hierarchy. Attempting to load from definition store.")

        begin
          # Try to find the definition in the global registry
          target_def = Legate::GlobalDefinitionRegistry.find(target_agent_name)

          unless target_def
            error_msg = "Target agent definition '#{target_agent_name}' not found in registry"
            Legate.logger.error(error_msg)
            return { status: :error, error_message: error_msg, error_class: 'AgentDefinitionNotFound' }
          end

          # Create a new agent instance from the definition
          target_agent = Legate::Agent.new(
            definition: target_def,
            session_service: session_service
          )
        rescue StandardError => e
          error_msg = "Failed to instantiate target agent '#{target_agent_name}': #{e.message}"
          Legate.logger.error("#{error_msg}\n#{e.backtrace.join("\n")}")
          return { status: :error, error_message: error_msg, error_class: e.class.name }
        end
      end

      # Verify the target agent exists
      unless target_agent
        error_msg = "Target agent '#{target_agent_name}' not found in hierarchy or definition store"
        Legate.logger.error(error_msg)
        return { status: :error, error_message: error_msg, error_class: 'AgentNotFound' }
      end

      # Start the target agent if it's not already running
      target_agent.start unless target_agent.running?

      # Execute the delegated task
      begin
        Legate.logger.info("Executing delegated task on agent '#{target_agent_name}': #{task}")

        # Call run_task with the same session context
        result_event = target_agent.run_task(
          session_id: session_id,
          user_input: task,
          session_service: session_service
        )

        # Extract and format the result
        result_content = result_event.respond_to?(:content) ? result_event.content : result_event

        {
          status: :success,
          target_agent: target_agent_name.to_s,
          result: result_content
        }
      rescue StandardError => e
        error_msg = "Error executing task on target agent '#{target_agent_name}': #{e.message}"
        Legate.logger.error("#{error_msg}\n#{e.backtrace.join("\n")}")
        { status: :error, error_message: error_msg, error_class: e.class.name }
      end
    end

    private

    def setup_tool_registry(definition)
      tool_classes_to_load = definition.tool_names.map { |tn| Legate::GlobalToolManager.find_class(tn) }.compact

      if tool_classes_to_load.length != definition.tool_names.length
        found_tool_names = tool_classes_to_load.map { |tc|
          begin
            tc.tool_metadata[:name].to_sym
          rescue StandardError
            nil
          end
        }.compact.to_set
        missing_tool_names = definition.tool_names.to_set - found_tool_names
        Legate.logger.warn(missing_tools_warning(missing_tool_names, definition)) if missing_tool_names.any?
      end

      @tool_registry = Legate::ToolRegistry.new
      Legate.logger.debug("Agent '#{@name}' created its ToolRegistry instance: #{@tool_registry.object_id}")

      tool_classes_to_load.each do |tool_class|
        Legate.logger.debug("[Agent Init '#{@name}'] Processing class from builder: #{tool_class.inspect} (Object ID: #{tool_class.object_id})")
        register_tool_class(tool_class)
      end

      return if @tool_registry.find_class(:check_job_status)

      begin
        require_relative 'tools/check_job_status_tool'
        register_tool_class(Legate::Tools::CheckJobStatusTool)
        Legate.logger.info("Automatically registered CheckJobStatusTool for agent '#{@name}'.")
      rescue LoadError => e
        Legate.logger.error("Failed to load CheckJobStatusTool: #{e.message}")
      end
    end

    # Builds an actionable warning for selected tools with no registered class:
    # a did-you-mean suggestion per name + the available tools. If the agent has
    # MCP servers configured, the names may be MCP tools (registered at connect
    # time), so the message softens rather than crying wolf.
    def missing_tools_warning(missing_tool_names, definition)
      available = Legate::GlobalToolManager.registered_tool_names.map(&:to_s).sort
      checker = DidYouMean::SpellChecker.new(dictionary: available)
      described = missing_tool_names.map do |name|
        suggestions = checker.correct(name.to_s)
        suggestions.empty? ? name.to_s : "#{name} (did you mean: #{suggestions.join(', ')}?)"
      end

      msg = "Agent '#{@name}': no registered tool for #{described.join('; ')}. " \
            "Available tools: #{available.join(', ')}."
      has_mcp = definition.respond_to?(:mcp_servers) && Array(definition.mcp_servers).any?
      msg + (has_mcp ? ' (MCP tools register when the agent connects, so this may be expected.)' : ' These tools will be unavailable.')
    end

    def setup_mcp_config(definition)
      mcp_servers_config_str = definition.mcp_servers || []
      if mcp_servers_config_str.is_a?(String) && !mcp_servers_config_str.strip.empty?
        # String-based MCP config parsing handled by existing logic
      elsif mcp_servers_config_str.is_a?(Array)
        @mcp_servers_config = mcp_servers_config_str
      else
        Legate.logger.debug("Agent '#{@name}': No valid MCP server config provided. Defaulting to empty array.")
        @mcp_servers_config = []
      end
    end

    def setup_sub_agents(definition, sub_agents)
      if sub_agents && !sub_agents.empty?
        link_provided_sub_agents(sub_agents)
      elsif definition.respond_to?(:sub_agent_names) && definition.sub_agent_names&.any?
        instantiate_sub_agents_from_definition(definition)
      end
    end

    # Sets this agent as the sub-agent's parent, or returns false if the sub-agent
    # already belongs to a different parent (the caller should then skip it).
    # Idempotent when the parent is already this agent.
    # @return [Boolean] true if linked (or already linked to self), false to skip
    def link_parent_or_skip(sub_agent)
      if sub_agent.parent_agent.nil?
        sub_agent.instance_variable_set(:@parent_agent, self)
        true
      elsif sub_agent.parent_agent == self
        true
      else
        Legate.logger.error("Agent '#{@name}': sub-agent '#{sub_agent.name}' already has a different parent: '#{sub_agent.parent_agent.name}'. Skipping.")
        false
      end
    end

    def link_provided_sub_agents(sub_agents)
      Legate.logger.info("Agent '#{@name}': Initializing with programmatically provided sub-agents (#{sub_agents.length} agents).")
      sub_agents.each do |sub_agent|
        unless sub_agent.is_a?(Legate::Agent)
          Legate.logger.warn("Agent '#{@name}': Item in provided sub_agents list is not an Legate::Agent. Skipping: #{sub_agent.inspect}")
          next
        end

        begin
          _check_circular_dependency(sub_agent.name)
        rescue Legate::ConfigurationError => e
          Legate.logger.error("Agent '#{@name}': #{e.message}")
          next
        end

        next unless link_parent_or_skip(sub_agent)

        if sub_agent.instance_variable_get(:@session_service).nil? && @session_service
          Legate.logger.debug("Agent '#{@name}': Setting session_service for programmatic sub-agent '#{sub_agent.name}' to match parent.")
          sub_agent.instance_variable_set(:@session_service, @session_service)
        elsif sub_agent.instance_variable_get(:@session_service) != @session_service && @session_service
          Legate.logger.warn("Agent '#{@name}': Programmatic sub-agent '#{sub_agent.name}' has a different session_service than parent.")
        end
        @sub_agents << sub_agent
        Legate.logger.info("Agent '#{@name}': Successfully instantiated and linked sub-agent '#{sub_agent.name}'.")
      end
      Legate.logger.info("Agent '#{@name}' finished linking programmatic sub-agents. Total sub-agents: #{@sub_agents.length}")
    end

    def instantiate_sub_agents_from_definition(definition)
      Legate.logger.info("Agent '#{@name}' attempting to instantiate sub-agents from definition: #{definition.sub_agent_names.to_a.inspect}")
      definition.sub_agent_names.each do |sub_agent_name|
        _check_circular_dependency(sub_agent_name)

        sub_agent_definition = Legate::GlobalDefinitionRegistry.find(sub_agent_name)
        unless sub_agent_definition
          Legate.logger.error("Agent '#{@name}': Could not find definition for sub-agent '#{sub_agent_name}' in GlobalDefinitionRegistry. Skipping.")
          next
        end

        Legate.logger.debug("Agent '#{@name}': Instantiating sub-agent '#{sub_agent_name}'...")
        sub_agent = Legate::Agent.new(definition: sub_agent_definition, session_service: @session_service)
        next unless link_parent_or_skip(sub_agent)

        @sub_agents << sub_agent
        Legate.logger.info("Agent '#{@name}': Successfully instantiated and linked sub-agent '#{sub_agent.name}'.")
      rescue ArgumentError => e
        Legate.logger.error("Agent '#{@name}': ArgumentError instantiating sub-agent '#{sub_agent_name}': #{e.message}")
      rescue StandardError => e
        Legate.logger.error("Agent '#{@name}': Unexpected error instantiating sub-agent '#{sub_agent_name}': #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      end
      Legate.logger.info("Agent '#{@name}' finished sub-agent instantiation. Total sub-agents: #{@sub_agents.length}")
    end

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
      return nil unless tool_class.is_a?(Class) && tool_class < Legate::Tool

      begin
        metadata = tool_class.tool_metadata
      rescue StandardError => e
        Legate.logger.error("Error calling tool_metadata on #{tool_class}: #{e.class} - #{e.message} - Backtrace: #{e.backtrace.first(3).join(' | ')}")
        metadata = {} # Default to empty hash if metadata call fails, for diagnosis
      end
      name = metadata[:name]&.to_sym

      if name.nil? || name == :''
        # Check deprecated @tool_name (instance variable on the class itself)
        if tool_class.instance_variable_defined?(:@tool_name)
          name = tool_class.instance_variable_get(:@tool_name)&.to_sym
          # Legate.logger.debug { "get_tool_name_from_class: Using name from deprecated @tool_name for #{tool_class}: #{name.inspect}" } if name
        end

        # If still no name, try inferred_name as a primary fallback if metadata[:name] is missing
        if (name.nil? || name == '') && tool_class.respond_to?(:inferred_name)
          name = tool_class.inferred_name
          # Legate.logger.debug { "get_tool_name_from_class: Using inferred_name for #{tool_class}: #{name.inspect}" } if name
        end
      end

      name && name != :'' ? name : nil
    end

    # --- REFACTORED: execute_plan now returns hash { details: [...], last_result: original_hash } ---
    # Executes a plan, logging tool request/result events via the session service.
    # @param plan [Hash, Array] The plan from the planner, either as a hash with :thought_process and :steps, or as an array of steps.
    # @param session [Legate::Session] The current session object.
    # @param session_service [Object] The session service instance.
    # @return [Hash] { details: Array<Hash>, last_result: Hash } or { details: Hash, last_result: nil } on planning errors.
    # Executes a planner-produced plan. Delegates to the agent's PlanExecutor;
    # kept here as the entry point called by #run_task.
    def execute_plan(plan, session, session_service, invocation_id)
      @plan_executor.execute_plan(plan, session, session_service, invocation_id)
    end

    # True when this agent should use the agentic ReAct loop instead of the
    # default plan-then-execute strategy.
    def react_strategy?
      @definition.respond_to?(:planning_strategy) && @definition.planning_strategy == :react
    end

    # Drives the agentic observe->think->act loop. Reuses the agent's existing
    # planner and PlanExecutor, so tool execution, event logging, and state
    # deltas behave identically to the default strategy.
    def run_react_loop(user_input, session, session_service, invocation_id)
      Legate::Agentic::Loop.new(
        planner: @planner,
        executor: @plan_executor,
        logger: Legate.logger
      ).run(
        user_input: user_input,
        session: session,
        session_service: session_service,
        invocation_id: invocation_id
      )
    end

    # --- REFACTORED: execute_step uses session context and passes it to tools ---
    # Executes a single step, logging :tool_request and :tool_result events via session service.
    # @param step [Hash] A hash like { tool: :symbol, params: {...} }.
    # @param session [Legate::Session] The current session object.
    # @param session_service [Object] The session service instance.
    # @param invocation_id [String] The ID of the current agent invocation.
    # @return [Hash] A standard result hash { status: ..., result/error_message/job_id: ... }.
    # Executes a single plan step. Delegates to the agent's PlanExecutor; kept
    # here as a private method because specs and the test-only custom_agent_patch
    # drive it via `send(:execute_step, ...)`.
    def execute_step(step, session, session_service, invocation_id = nil)
      @plan_executor.execute_step(step, session, session_service, invocation_id)
    end

    # Connects to all configured MCP servers.
    # Connects the agent's configured MCP servers and registers their tools.
    # Delegates to the agent's McpConnectionManager (kept as a lifecycle hook
    # called from #start and exercised directly in specs).
    def connect_mcp_servers
      @mcp_manager.connect(@mcp_servers_config)
    end

    # Disconnects all active MCP clients.
    def disconnect_mcp_servers
      @mcp_manager.disconnect
    end

    # Helper method to check for circular dependencies in the agent hierarchy
    # @param new_sub_agent_name [Symbol] The name of the new sub-agent to check for cycles
    # @raise [Legate::ConfigurationError] If a circular dependency is detected
    private def _check_circular_dependency(new_sub_agent_name)
      # Direct self-reference check
      raise Legate::ConfigurationError, "Circular dependency detected: Agent '#{@name}' cannot include itself as a sub-agent" if new_sub_agent_name == @name

      # Check if the sub-agent would create an indirect circular reference
      # by traversing up the parent chain (backwards check)
      current_agent = self
      ancestry_path = [@name]

      while (parent = current_agent.parent_agent)
        # If any parent has the same name as the new sub-agent, it's a circular reference
        if parent.name == new_sub_agent_name
          circular_path = [new_sub_agent_name] + ancestry_path
          raise Legate::ConfigurationError, "Circular dependency detected: #{circular_path.join(' → ')}"
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

      # For Hash results, ensure a plan_details key exists (back-compat). Non-Hash
      # results (a tool/callback returning a bare string, number, array, …) are
      # stored as-is — calling #key? on them would raise NoMethodError.
      needs_plan_details = output_value.is_a?(Hash) &&
                           !output_value.key?(:plan_details) && !output_value.key?('plan_details')
      output_value = output_value.merge(plan_details: []) if needs_plan_details

      serialized_value = begin
        # If the value is a Hash or Array, deep transform keys and symbolized values
        if output_value.is_a?(Hash) || output_value.is_a?(Array)
          # Convert to JSON and back to remove symbols
          JSON.parse(output_value.to_json)
        else
          # For other values, just pass through
          output_value
        end
      rescue StandardError => e
        # If serialization fails, log and return the original
        Legate.logger.warn("Agent '#{@name}': Failed to serialize output value: #{e.message}. Using original value.")
        output_value
      end

      Legate.logger.info("Agent '#{@name}' storing output to session state with key '#{@definition.output_key}' for session '#{session_id}'.")

      begin
        # Ensure session_service has set_state. Add if missing for base/inmemory.
        if session_service.respond_to?(:set_state)
          session_service.set_state(session_id: session_id, key: @definition.output_key, value: serialized_value)
        else
          Legate.logger.warn("Agent '#{@name}': Session service does not support :set_state. Cannot store output for key '#{@definition.output_key}'.")
        end
      rescue StandardError => e
        Legate.logger.error("Agent '#{@name}': Failed to set state for key '#{@definition.output_key}' in session '#{session_id}': #{e.class} - #{e.message}")
      end
    end
    # --- End MAS State Management ---
  end # End Agent class
end # End Legate module
