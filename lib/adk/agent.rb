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
require 'set'
require 'forwardable'
require 'json'
require_relative 'global_definition_registry'
require_relative 'global_tool_manager' # Added

module ADK
  class Error < StandardError; end unless defined?(ADK::Error)

  # Represents the static definition of an Agent, including its name,
  # description, instructions, tools, and model configuration.
  class AgentDefinition
    extend Forwardable

    # @return [Symbol] The unique name identifying this agent definition.
    attr_reader :name
    # @return [String] A description of the agent's purpose.
    attr_reader :description
    # @return [String] The core instructions given to the language model.
    attr_reader :instruction
    # @return [Set<Symbol>] A set of names of the tools available to this agent.
    attr_reader :tool_names
    # @return [String, nil] The specific model name to use (e.g., "gpt-4-turbo"). Overrides global default.
    attr_reader :model_name
    # @return [Float, nil] The temperature setting for the model. Overrides global default.
    attr_reader :temperature
    # @return [Boolean] Whether this agent can be triggered by webhooks. Defaults to false.
    attr_reader :webhook_enabled
    # @return [Symbol, Proc, nil] The validator (name or proc) for webhook requests.
    attr_reader :webhook_validator
    # @return [String, nil] The secret key for webhook validation.
    attr_reader :webhook_secret
    # @return [Proc, nil] The transformer proc for webhook payloads.
    attr_reader :webhook_transformer
    # @return [Proc, nil] The session extractor proc for webhook requests.
    attr_reader :webhook_session_extractor
    # @return [Symbol] The fallback mode (:error or :echo). Defaults to :error.
    attr_reader :fallback_mode
    # @return [Array<Hash>] Configuration for MCP servers. Defaults to [].
    attr_reader :mcp_servers
    # @return [Set<Symbol>] A set of names of sub-agent definitions to instantiate.
    attr_reader :sub_agent_names
    # @return [Symbol, nil] The key under which the agent's final output should be stored in the session state.
    attr_reader :output_key

    # Delegate common attributes to the definition proxy for easier access during definition
    # Only delegate methods needed *within* the define block
    def_delegators :@proxy, :use_tool

    def initialize
      @name = nil
      @description = ''
      @instruction = ''
      @tool_names = Set.new
      @model_name = nil
      @temperature = nil
      # --- Webhook Defaults ---
      @webhook_enabled = false
      @webhook_validator = nil
      @webhook_secret = nil
      @webhook_transformer = nil
      @webhook_session_extractor = nil
      @fallback_mode = :error # Default fallback mode
      @mcp_servers = [] # Default MCP servers
      @sub_agent_names = Set.new # MAS New attribute for sub-agent definitions
      @output_key = nil      # MAS New attribute for state management
      # -----------------------

      @proxy = DefinitionProxy.new(self)
    end

    # DSL method used within `Agent.define` block.
    # @param block [Proc] The block containing the definition DSL calls.
    def define(&block)
      @proxy.instance_eval(&block)
      validate!
      self
    end

    # Validates that the definition has all required fields.
    # @raise [ArgumentError] If validation fails.
    def validate!
      raise ArgumentError, 'Agent definition must have a name.' if @name.nil? || @name.to_s.strip.empty?
      raise ArgumentError, 'Agent name must be a Symbol.' unless @name.is_a?(Symbol)

      raise ArgumentError,
            "Agent '#{@name}' must have an instruction." if @instruction.nil? || @instruction.strip.empty?

      # Explicitly check instance variable to bypass potential method resolution issues
      if @webhook_enabled
        # raise ArgumentError, "Agent '#{@name}' enabled for webhooks must define a webhook_transformer." unless @webhook_transformer.is_a?(Proc)
        # raise ArgumentError, "Agent '#{@name}' enabled for webhooks must define a webhook_session_extractor." unless @webhook_session_extractor.is_a?(Proc)
        unless @webhook_transformer.is_a?(Proc)
          ADK.logger.warn { "Agent '#{@name}' is webhook_enabled but lacks a valid :webhook_transformer Proc." }
        end
        unless @webhook_session_extractor.is_a?(Proc)
          ADK.logger.warn { "Agent '#{@name}' is webhook_enabled but lacks a valid :webhook_session_extractor Proc." }
        end
      end
    end

    # Returns a hash representation suitable for logging or inspection.
    # @return [Hash]
    def to_h
      {
        name: @name,
        description: @description,
        instruction: @instruction,
        tool_names: @tool_names.to_a,
        model_name: @model_name,
        temperature: @temperature,
        webhook_enabled: @webhook_enabled,
        webhook_validator: @webhook_validator.is_a?(Proc) ? '<Proc>' : @webhook_validator,
        webhook_secret: @webhook_secret ? '<present>' : nil,
        webhook_transformer: @webhook_transformer.is_a?(Proc) ? '<Proc>' : nil,
        webhook_session_extractor: @webhook_session_extractor.is_a?(Proc) ? '<Proc>' : nil,
        fallback_mode: @fallback_mode,
        mcp_servers: @mcp_servers,
        sub_agent_names: @sub_agent_names.to_a, # MAS New attribute
        output_key: @output_key # MAS New attribute
      }
    end

    # Internal proxy class to provide a clean DSL within the `define` block.
    class DefinitionProxy
      def initialize(definition)
        @definition = definition
      end

      # Sets the agent name.
      # @param name [Symbol] Unique identifier for the agent.
      def name(name)
        raise ArgumentError, 'Agent name must be a Symbol.' unless name.is_a?(Symbol)

        @definition.instance_variable_set(:@name, name)
      end

      # Sets the agent description.
      # @param description [String]
      def description(description)
        @definition.instance_variable_set(:@description, description.to_s)
      end

      # Sets the agent's core instruction.
      # @param instruction [String]
      def instruction(instruction)
        @definition.instance_variable_set(:@instruction, instruction.to_s)
      end

      # Registers a tool for the agent to use.
      # @param tool_name [Symbol] The registered name of the tool.
      # @param options [Hash] Tool-specific options (currently unused).
      def use_tool(tool_name, _options = {})
        raise ArgumentError, 'Tool name must be a Symbol.' unless tool_name.is_a?(Symbol)

        # TODO: Validate tool_name against a global registry?
        @definition.instance_variable_get(:@tool_names) << tool_name
      end

      # Sets the specific model name for this agent.
      # @param model_name [String, Symbol]
      def model_name(model_name)
        @definition.instance_variable_set(:@model_name, model_name.to_sym)
      end

      # Sets the temperature for this agent.
      # @param temperature [Float]
      def temperature(temperature)
        @definition.instance_variable_set(:@temperature, temperature.to_f)
      end

      # --- Webhook Configuration DSL ---

      # Enables or disables webhook triggering for this agent.
      # @param enabled [Boolean]
      def webhook_enabled(enabled)
        @definition.instance_variable_set(:@webhook_enabled, !!enabled)
      end

      # Sets the validator for webhook requests.
      # @param validator [Symbol, Proc, nil] The name of a registered validator, a Proc, or nil.
      def webhook_validator(validator)
        # Allow nil, Symbol, or Proc
        unless validator.nil? || validator.is_a?(Symbol) || validator.is_a?(Proc)
          raise ArgumentError, 'webhook_validator must be a Symbol, a Proc, or nil.'
        end

        @definition.instance_variable_set(:@webhook_validator, validator)
      end

      # Sets the secret key for webhook validation.
      # @param secret [String]
      def webhook_secret(secret)
        @definition.instance_variable_set(:@webhook_secret, secret)
      end

      # Sets the transformer proc for webhook payloads.
      # @param transformer_proc [Proc, nil] The transformer proc or nil.
      def webhook_transformer(transformer_proc)
        # Allow nil or Proc
        raise ArgumentError,
              'webhook_transformer must be a Proc or nil.' unless transformer_proc.nil? || transformer_proc.is_a?(Proc)

        @definition.instance_variable_set(:@webhook_transformer, transformer_proc)
      end

      # Sets the session extractor proc for webhook requests.
      # @param extractor_proc [Proc, nil] The extractor proc or nil.
      def webhook_session_extractor(extractor_proc)
        # Allow nil or Proc
        raise ArgumentError,
              'webhook_session_extractor must be a Proc or nil.' unless extractor_proc.nil? || extractor_proc.is_a?(Proc)

        @definition.instance_variable_set(:@webhook_session_extractor, extractor_proc)
      end

      # Sets the fallback mode for the agent.
      # @param mode [Symbol] :error or :echo.
      def fallback_mode(mode)
        valid_modes = %i[error echo]
        unless valid_modes.include?(mode)
          raise ArgumentError, "Invalid fallback_mode '#{mode}'. Must be one of: #{valid_modes.join(', ')}."
        end

        @definition.instance_variable_set(:@fallback_mode, mode)
      end

      # Configures MCP servers for the agent.
      # @param server_configs [Hash, Array<Hash>] MCP server configuration(s).
      def mcp_servers(*server_configs)
        configs = Array(server_configs).flatten.compact
        # Basic validation: Ensure it's an array of hashes?
        unless configs.all? { |c| c.is_a?(Hash) }
          raise ArgumentError, 'MCP server configurations must be provided as Hashes.'
        end

        @definition.instance_variable_set(:@mcp_servers, configs)
      end
      # -----------------------------

      # --- MAS Attributes DSL ---
      # Defines the names of sub-agents that should be instantiated under this agent.
      # @param names [Array<Symbol>] An array of sub-agent definition names.
      def sub_agents_define(*names)
        flat_names = names.flatten.map(&:to_sym)
        invalid_names = flat_names.reject { |n| n.is_a?(Symbol) }
        unless invalid_names.empty?
          raise ArgumentError, "Sub-agent names must all be Symbols. Invalid names: #{invalid_names.join(', ')}"
        end
        @definition.instance_variable_set(:@sub_agent_names, @definition.instance_variable_get(:@sub_agent_names).merge(flat_names))
      end

      # Sets the key under which the agent's final output should be stored in session state.
      # @param key_name [Symbol] The key name.
      def output_key(key_name)
        raise ArgumentError, 'Output key must be a Symbol.' unless key_name.is_a?(Symbol)
        @definition.instance_variable_set(:@output_key, key_name)
      end
      # --- End MAS Attributes DSL ---
    end
    private_constant :DefinitionProxy

    # Class method to create an AgentDefinition instance from a hash.
    # This is typically used when loading a definition from a persistent store.
    # @param hash_data [Hash] The hash containing agent definition attributes.
    # @return [ADK::AgentDefinition, nil] A new AgentDefinition instance or nil on error.
    def self.from_hash(hash_data)
      return nil unless hash_data.is_a?(Hash)

      definition = new
      proxy = DefinitionProxy.new(definition)

      proxy.name(hash_data[:name].to_sym) if hash_data[:name]
      proxy.description(hash_data[:description].to_s) if hash_data.key?(:description)
      proxy.instruction(hash_data[:instruction].to_s) if hash_data.key?(:instruction)
      proxy.model_name(hash_data[:model_name].to_sym) if hash_data[:model_name]
      proxy.temperature(hash_data[:temperature].to_f) if hash_data[:temperature]

      (hash_data[:tool_names] || []).each do |tn|
        proxy.use_tool(tn.to_sym) unless tn.to_s.strip.empty?
      end

      proxy.webhook_enabled(hash_data[:webhook_enabled]) if hash_data.key?(:webhook_enabled)

      # Webhook Validator
      validator_data = hash_data[:webhook_validator]
      if validator_data.is_a?(Symbol)
        proxy.webhook_validator(validator_data)
      elsif validator_data == '<Proc>' # String placeholder from to_h for a Proc
        proxy.webhook_validator(nil)    # Cannot reconstruct Proc, set to nil
      elsif validator_data.is_a?(String) # Assume it's a symbol stored as string e.g. "my_validator" or ":my_val"
        proxy.webhook_validator(validator_data.delete_prefix(':').to_sym)
      elsif hash_data.key?(:webhook_validator) && validator_data.nil? # Explicit nil in hash
        proxy.webhook_validator(nil)
      end

      # Webhook Transformer
      transformer_data = hash_data[:webhook_transformer]
      if transformer_data == '<Proc>' # String placeholder from to_h for a Proc
        proxy.webhook_transformer(nil)   # Cannot reconstruct Proc, set to nil
      elsif hash_data.key?(:webhook_transformer) && transformer_data.nil? # Explicit nil in hash
        proxy.webhook_transformer(nil)
      # If transformer_data is something else (e.g., unexpected string/type from hash),
      # the DefinitionProxy#webhook_transformer setter will raise an ArgumentError if it's not a Proc or nil.
      # This is the desired behavior - from_hash should not try to coerce invalid types.
      end

      # Webhook Session Extractor
      extractor_data = hash_data[:webhook_session_extractor]
      if extractor_data == '<Proc>' # String placeholder from to_h for a Proc
        proxy.webhook_session_extractor(nil) # Cannot reconstruct Proc, set to nil
      elsif hash_data.key?(:webhook_session_extractor) && extractor_data.nil? # Explicit nil in hash
        proxy.webhook_session_extractor(nil)
      end
      
      proxy.webhook_secret(hash_data[:webhook_secret]) if hash_data.key?(:webhook_secret)

      proxy.fallback_mode(hash_data[:fallback_mode].to_sym) if hash_data[:fallback_mode]

      mcp_servers_data = hash_data[:mcp_servers]
      if mcp_servers_data.is_a?(String)
        begin
          parsed_mcp_servers = JSON.parse(mcp_servers_data)
          proxy.mcp_servers(*(parsed_mcp_servers.is_a?(Array) ? parsed_mcp_servers : []))
        rescue JSON::ParserError => e
          ADK.logger.warn("Failed to parse mcp_servers JSON from hash_data for agent '#{hash_data[:name]}': #{e.message}")
          proxy.mcp_servers([]) # Default to empty if parsing fails
        end
      elsif mcp_servers_data.is_a?(Array)
        proxy.mcp_servers(*mcp_servers_data)
      end

      # MAS: Handle sub_agent_names
      if hash_data[:sub_agent_names].is_a?(Array)
        proxy.sub_agents_define(*(hash_data[:sub_agent_names].map(&:to_sym)))
      end

      # MAS: Handle output_key
      proxy.output_key(hash_data[:output_key].to_sym) if hash_data[:output_key]

      definition.validate!
      definition
    rescue ArgumentError => e # Catch validation errors or other argument errors from proxy setters
      ADK.logger.error("ArgumentError creating AgentDefinition from hash for agent '#{hash_data[:name]}': #{e.message}. Hash: #{hash_data.inspect}")
      nil
    rescue => e
      ADK.logger.error("Unexpected error creating AgentDefinition from hash for agent '#{hash_data[:name]}': #{e.class} - #{e.message}. Hash: #{hash_data.inspect}")
      ADK.logger.error(e.backtrace.first(5).join("\n"))
      nil
    end
  end

  # Agent class represents an AI agent that can perform tasks using tools and a planner.
  # It operates within the context of a session managed by a SessionService.
  class Agent
    DEFAULT_MODEL = 'gemini-2.0-flash' # Updated default model

    attr_reader :name, :description, :planner, :logger, :model_name, :state, :tool_registry, :fallback_mode,
                :instruction, :definition, :session_service # Added session_service to attr_reader
    # MAS Attributes
    attr_reader :parent_agent # The parent agent in a hierarchy, if any
    attr_reader :sub_agents   # A collection of sub-agents

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
          # Enforce single parent rule
          if sub_agent.parent_agent.nil?
            sub_agent.instance_variable_set(:@parent_agent, self)
          elsif sub_agent.parent_agent != self
            ADK.logger.error("Agent '#{@name}': Cannot adopt sub-agent '#{sub_agent.name}'. It already has a different parent: '#{sub_agent.parent_agent.name}'. Skipping this sub-agent.")
            next # Skip this sub-agent
          end
          # (If sub_agent.parent_agent == self, it's already correctly parented, do nothing extra here)

          # Verify session service consistency - only log warnings
          if sub_agent.instance_variable_get(:@session_service) != @session_service && @session_service # Warn if different and parent has one
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
            ADK.logger.info("Agent '#{@name}': Successfully instantiated and linked sub-agent '#{sub_agent_name}'.")
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
      # --------------------------- #

      # --- Log User Input --- #
      user_event = ADK::Event.new(role: :user, content: user_input)
      session_service.append_event(session_id: session_id, event: user_event)
      # ---------------------- #

      # --- Prepare for Planner --- #
      # Combine system instruction + history + latest input
      # (Assuming planner needs a simple string or specific format)
      # TODO: Refine message formatting based on Planner requirements
      history = session.events.map { |e|
        "#{e.role}: #{e.content.is_a?(Hash) ? e.content.inspect : e.content}"
      }.join("\n")
      planner_input = [self.instruction, history, "user: #{user_input}"].compact.join("\n\n")
      # ------------------------- #

      # --- Plan and Execute --- #
      final_agent_event = nil
      begin
        plan = @planner.plan(planner_input)
        execution_result = execute_plan(plan, session, session_service)

        # --- Create Final Agent Event --- #
        # execution_result = { details: plan_details, last_result: original_hash_or_nil }
        final_content = execution_result[:last_result] || execution_result[:details]

        # Merge plan details into the final content if it's a hash
        if final_content.is_a?(Hash)
          final_content = final_content.merge(plan_details: execution_result[:details])
        else # Should not happen if execute_plan returns error hash correctly
          ADK.logger.error("Unexpected result format from execute_plan: #{final_content.inspect}")
          final_content = { status: :error, error_message: 'Internal error processing plan result.',
                            result: final_content }
          final_content = final_content.merge(plan_details: execution_result[:details]) if execution_result[:details]
        end

        final_agent_event = ADK::Event.new(role: :agent, content: final_content)
        # ---------------------------- #
      rescue StandardError => e
        # Handle critical errors during planning or execution itself
        ADK.logger.error("Critical error during run_task for session '#{session_id}': #{e.class} - #{e.message}\nBacktrace: #{e.backtrace.join("\n")}")
        error_content = { status: :error, error_message: "An internal error occurred: #{e.message}" }
        # Attempt to add plan details if available from a partial execution
        # error_content = error_content.merge(plan_details: execution_result[:details]) if execution_result && execution_result[:details]
        final_agent_event = ADK::Event.new(role: :agent, content: error_content)
      end
      # ------------------------ #

      # --- Log Final Agent Event --- #
      begin
        session_service.append_event(session_id: session_id, event: final_agent_event)
      rescue StandardError => e
        # Log failure to append the *final* event, but still return it
        ADK.logger.error("Failed to append final agent event for session '#{session_id}': #{e.class} - #{e.message}")
      end
      # --------------------------- #

      # --- MAS: Store result in session state if output_key is defined --- #
      if @definition.respond_to?(:output_key) && @definition.output_key && final_agent_event
        output_value = final_agent_event.content # Store the entire content hash
        ADK.logger.info("Agent '#{@name}' storing output to session state with key '#{@definition.output_key}' for session '#{session_id}'. Value: #{output_value.inspect}")
        begin
          # Ensure session_service has set_state. Add if missing for base/inmemory.
          if session_service.respond_to?(:set_state)
            session_service.set_state(session_id: session_id, key: @definition.output_key, value: output_value)
          else
            ADK.logger.warn("Agent '#{@name}': Session service does not support :set_state. Cannot store output for key '#{@definition.output_key}'.")
          end
        rescue StandardError => e
          ADK.logger.error("Agent '#{@name}': Failed to set state for key '#{@definition.output_key}' in session '#{session_id}': #{e.class} - #{e.message}")
        end
      end
      # --- End MAS State Management --- #

      return final_agent_event
    end

    private

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
    # @param plan [Array<Hash>] Plan from the planner.
    # @param session [ADK::Session] The current session object.
    # @param session_service [Object] The session service instance.
    # @return [Hash] { details: Array<Hash>, last_result: Hash } or { details: Hash, last_result: nil } on planning errors.
    def execute_plan(plan, session, session_service)
      session_id = session.id

      unless plan.is_a?(Array)
        msg = 'Invalid plan received from planner (not an Array).'
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
            }&.content || '[Original input not found]'
            plan = [{ tool: :echo, params: { message: original_user_input } }]
            ADK.logger.debug("Reconstructed plan for echo fallback: #{plan.inspect}")
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
        current_result_hash = execute_step(step_with_injected_params, session, session_service)

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
          unless result_hash.is_a?(Hash) && result_hash.key?(:status) && %i[success
                                                                            pending].include?(result_hash[:status])
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
  end # End Agent class
end # End ADK module
