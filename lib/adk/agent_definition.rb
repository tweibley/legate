# frozen_string_literal: true

require 'set'
require 'forwardable'
require 'json'
require_relative 'errors'

module ADK
  # Defines the blueprint for an Agent, including its identity, instructions, and capabilities.
  #
  # AgentDefinition uses a DSL (Domain Specific Language) to configure agent properties
  # such as name, description, tools, model parameters, and behavior callbacks.
  # These definitions are then used to instantiate {ADK::Agent} objects.
  #
  # @example Defining a simple agent
  #   definition = ADK::AgentDefinition.new.define do |a|
  #     a.name :my_agent
  #     a.description 'A helpful assistant'
  #     a.instruction 'You are a helpful assistant.'
  #     a.use_tool :echo
  #     a.model_name 'gemini-1.5-flash'
  #     a.temperature 0.7
  #   end
  #
  #   agent = ADK::Agent.new(definition: definition)
  #
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
    # @return [Symbol] The type of agent (:llm, :sequential, :parallel, :loop). Defaults to :llm.
    attr_reader :agent_type
    # @return [Set<Symbol>] A set of names of sub-agents to execute in sequence (for SequentialAgent).
    attr_reader :sequential_sub_agent_names
    # @return [Set<Symbol>] A set of names of sub-agents to execute in parallel (for ParallelAgent).
    attr_reader :parallel_sub_agent_names
    # @return [Set<Symbol>] A set of names of sub-agents to execute in each loop iteration (for LoopAgent).
    attr_reader :loop_sub_agent_names
    # @return [Integer, nil] The maximum number of loop iterations (for LoopAgent).
    attr_reader :loop_max_iterations
    # @return [Symbol, nil] The key in the session state to check for loop condition (for LoopAgent).
    attr_reader :loop_condition_state_key
    # @return [Object, nil] The expected value for loop condition (for LoopAgent).
    attr_reader :loop_condition_expected_value
    # @return [Set<Symbol>] A set of names of agents that this agent can delegate tasks to via LLM planning.
    attr_reader :delegation_targets

    # --- Authentication Attributes ---
    # @return [Set<Symbol>] A set of credential names this agent can use.
    attr_reader :auth_credential_names
    # @return [Array<Hash>] URL pattern to scheme/credential mappings for this agent.
    attr_reader :auth_url_mappings
    # @return [Hash<Symbol, Symbol>] Service to scheme name assignments.
    attr_reader :auth_scheme_assignments
    # @return [Hash<Symbol, Symbol>] Service to credential name assignments.
    attr_reader :auth_credential_assignments

    # --- Callback Attributes ---
    # @return [Proc, nil] Callback run before agent execution begins
    attr_reader :before_agent_callback
    # @return [Proc, nil] Callback run after agent execution completes
    attr_reader :after_agent_callback
    # @return [Proc, nil] Callback run before LLM model interaction
    attr_reader :before_model_callback
    # @return [Proc, nil] Callback run after LLM model interaction
    attr_reader :after_model_callback
    # @return [Proc, nil] Callback run before any tool execution
    attr_reader :before_tool_callback
    # @return [Proc, nil] Callback run after any tool execution
    attr_reader :after_tool_callback

    # --- End Callback Attributes ---

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
      @sub_agent_names = Set.new # MAS attribute for sub-agent definitions
      @output_key = nil # MAS attribute for state management
      # --- MAS Workflow Agent Attributes ---
      @agent_type = :llm # Default agent type
      @sequential_sub_agent_names = Set.new # For SequentialAgent
      @parallel_sub_agent_names = Set.new # For ParallelAgent
      @loop_sub_agent_names = Set.new # For LoopAgent
      @loop_max_iterations = nil # Maximum number of loop iterations
      @loop_condition_state_key = nil # State key to check in loop condition
      @loop_condition_expected_value = nil # Expected value for loop condition
      @delegation_targets = Set.new # Agent names that this agent can delegate to
      # -----------------------

      # --- Authentication Attributes ---
      @auth_credential_names = Set.new # Credential names this agent can use
      @auth_url_mappings = [] # URL pattern to scheme/credential mappings
      @auth_scheme_assignments = {} # Service to scheme assignments
      @auth_credential_assignments = {} # Service to credential assignments
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
        sub_agent_names: @sub_agent_names.to_a, # MAS attribute
        output_key: @output_key, # MAS attribute
        # Adding new MAS attributes for agent hierarchy and workflow
        agent_type: @agent_type || :llm, # Default to :llm if not set
        sequential_sub_agent_names: @sequential_sub_agent_names&.to_a || [],
        parallel_sub_agent_names: @parallel_sub_agent_names&.to_a || [],
        loop_sub_agent_names: @loop_sub_agent_names&.to_a || [],
        loop_max_iterations: @loop_max_iterations,
        loop_condition_state_key: @loop_condition_state_key,
        loop_condition_expected_value: @loop_condition_expected_value,
        delegation_targets: @delegation_targets&.to_a || [],
        # --- Authentication fields ---
        auth_credential_names: @auth_credential_names&.to_a || [],
        auth_url_mappings: (@auth_url_mappings || []).map do |m|
          {
            pattern: m[:pattern].is_a?(Regexp) ? m[:pattern].source : m[:pattern],
            pattern_type: m[:pattern].is_a?(Regexp) ? 'regexp' : 'string',
            scheme_name: m[:scheme_name]&.to_s,
            credential_name: m[:credential_name]&.to_s
          }
        end,
        auth_scheme_assignments: (@auth_scheme_assignments || {}).transform_keys(&:to_s).transform_values(&:to_s),
        auth_credential_assignments: (@auth_credential_assignments || {}).transform_keys(&:to_s).transform_values(&:to_s)
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

      # --- MAS Workflow Agent Type ---
      # Sets the agent type
      # @param type [Symbol] The agent type (:llm, :sequential, :parallel, :loop)
      def agent_type(type)
        valid_types = %i[llm sequential parallel loop]
        unless valid_types.include?(type.to_sym)
          raise ArgumentError, "Agent type must be one of: #{valid_types.join(', ')}. Got: #{type}"
        end

        @definition.instance_variable_set(:@agent_type, type.to_sym)
      end

      # --- SequentialAgent Configuration ---
      # Define sequential sub-agent names in order of execution
      # @param names [Array<Symbol>] Names of sub-agents to execute in sequence
      def sequential_sub_agents(*names)
        flat_names = names.flatten.map(&:to_sym)
        # Log a warning if the array is empty but don't raise an error
        ADK.logger.warn("Empty sequential sub-agents list for agent '#{@definition.name}'") if flat_names.empty?

        @definition.instance_variable_set(:@sequential_sub_agent_names, Set.new(flat_names))
      end

      # --- ParallelAgent Configuration ---
      # Define parallel sub-agent names to execute concurrently
      # @param names [Array<Symbol>] Names of sub-agents to execute in parallel
      def parallel_sub_agents(*names)
        flat_names = names.flatten.map(&:to_sym)
        # Log a warning if the array is empty but don't raise an error
        ADK.logger.warn("Empty parallel sub-agents list for agent '#{@definition.name}'") if flat_names.empty?

        @definition.instance_variable_set(:@parallel_sub_agent_names, Set.new(flat_names))
      end

      # --- LoopAgent Configuration ---
      # Define loop sub-agent names in order of execution within each loop iteration
      # @param names [Array<Symbol>] Names of sub-agents to execute in each loop iteration
      def loop_sub_agents(*names)
        flat_names = names.flatten.map(&:to_sym)
        # Log a warning if the array is empty but don't raise an error
        ADK.logger.warn("Empty loop sub-agents list for agent '#{@definition.name}'") if flat_names.empty?

        @definition.instance_variable_set(:@loop_sub_agent_names, Set.new(flat_names))
      end

      # Set maximum number of loop iterations
      # @param max [Integer] The maximum number of iterations
      def loop_max_iterations(max)
        unless max.is_a?(Integer) && max > 0
          raise ArgumentError, "Maximum iterations must be a positive integer. Got: #{max}"
        end

        @definition.instance_variable_set(:@loop_max_iterations, max)
      end

      # Set the loop condition state key and expected value
      # @param key [Symbol] The key in the session state to check
      # @param value [Object] The expected value that indicates loop completion
      def loop_condition(key, value)
        raise ArgumentError, 'Loop condition key must be a Symbol.' unless key.is_a?(Symbol)

        @definition.instance_variable_set(:@loop_condition_state_key, key)
        @definition.instance_variable_set(:@loop_condition_expected_value, value)
      end

      # --- Delegation Configuration ---
      # Define agent names that this agent can delegate tasks to via LLM planning
      # @param names [Array<Symbol>] Names of agents that can be delegation targets
      def can_delegate_to(*names)
        flat_names = names.flatten.map(&:to_sym)
        # Log a warning if the array is empty but don't raise an error
        ADK.logger.warn("Empty delegation targets list for agent '#{@definition.name}'") if flat_names.empty?

        @definition.instance_variable_set(:@delegation_targets, Set.new(flat_names))
      end
      # --- End MAS Attributes DSL ---

      # --- Authentication DSL Methods ---

      # Associate a registered credential with this agent
      # @param credential_name [Symbol] Name of a registered credential
      # @example
      #   use_credential :google_maps_api
      #   use_credential :openai_key
      def use_credential(credential_name)
        raise ArgumentError, 'Credential name must be a Symbol.' unless credential_name.is_a?(Symbol)

        @definition.instance_variable_get(:@auth_credential_names) << credential_name
      end

      # Map a URL pattern to an authentication scheme and credential
      # @param url_pattern [String, Regexp] URL pattern to match
      # @param scheme [Symbol] Scheme type or name to use
      # @param credential [Symbol] Credential name to use
      # @example
      #   auth_mapping 'https://maps.googleapis.com/*', scheme: :api_key, credential: :google_maps_api
      #   auth_mapping /api\.openai\.com/, scheme: :http_bearer, credential: :openai_key
      def auth_mapping(url_pattern, scheme:, credential:)
        unless url_pattern.is_a?(String) || url_pattern.is_a?(Regexp)
          raise ArgumentError, 'URL pattern must be a String or Regexp.'
        end
        raise ArgumentError, 'Scheme must be a Symbol.' unless scheme.is_a?(Symbol)
        raise ArgumentError, 'Credential must be a Symbol.' unless credential.is_a?(Symbol)

        @definition.instance_variable_get(:@auth_url_mappings) << {
          pattern: url_pattern,
          scheme_name: scheme,
          credential_name: credential
        }
      end

      # Assign a scheme for a named service
      # @param service [Symbol] Service identifier (e.g., :google_maps, :openai)
      # @param scheme [Symbol] Scheme name to use for this service
      # @example
      #   auth_scheme :google_maps, :api_key
      #   auth_scheme :openai, :http_bearer
      def auth_scheme(service, scheme)
        raise ArgumentError, 'Service must be a Symbol.' unless service.is_a?(Symbol)
        raise ArgumentError, 'Scheme must be a Symbol.' unless scheme.is_a?(Symbol)

        @definition.instance_variable_get(:@auth_scheme_assignments)[service] = scheme
      end

      # Assign a credential for a named service
      # @param service [Symbol] Service identifier (e.g., :google_maps, :openai)
      # @param credential [Symbol] Credential name to use for this service
      # @example
      #   auth_credential :google_maps, :google_maps_api
      #   auth_credential :openai, :openai_key
      def auth_credential(service, credential)
        raise ArgumentError, 'Service must be a Symbol.' unless service.is_a?(Symbol)
        raise ArgumentError, 'Credential must be a Symbol.' unless credential.is_a?(Symbol)

        @definition.instance_variable_get(:@auth_credential_assignments)[service] = credential
      end

      # --- End Authentication DSL Methods ---

      # --- Callback DSL Methods ---

      # Sets the callback to run before agent execution
      # @param block [Proc] The callback code to run
      # @yieldparam context [ADK::Callbacks::CallbackContext] Context for state management
      # @yieldreturn [Hash, nil] Optional hash to override normal execution
      def before_agent_callback(&block)
        raise ArgumentError, 'Callback must be a Proc or lambda.' unless block.is_a?(Proc)

        @definition.instance_variable_set(:@before_agent_callback, block)
      end

      # Sets the callback to run after agent execution
      # @param block [Proc] The callback code to run
      # @yieldparam context [ADK::Callbacks::CallbackContext] Context for state management
      # @yieldparam result [Hash] The agent's result hash that can be modified
      # @yieldreturn [Hash, nil] Optional hash to replace the agent's result
      def after_agent_callback(&block)
        raise ArgumentError, 'Callback must be a Proc or lambda.' unless block.is_a?(Proc)

        @definition.instance_variable_set(:@after_agent_callback, block)
      end

      # Sets the callback to run before model interaction
      # @param block [Proc] The callback code to run
      # @yieldparam context [ADK::Callbacks::CallbackContext] Context for state management
      # @yieldparam llm_request [Hash] The request parameters being sent to the model
      # @yieldreturn [Hash, nil] Optional hash to override normal model execution
      def before_model_callback(&block)
        raise ArgumentError, 'Callback must be a Proc or lambda.' unless block.is_a?(Proc)

        @definition.instance_variable_set(:@before_model_callback, block)
      end

      # Sets the callback to run after model interaction
      # @param block [Proc] The callback code to run
      # @yieldparam context [ADK::Callbacks::CallbackContext] Context for state management
      # @yieldparam plan [Hash] The plan returned by the model that can be modified
      # @yieldreturn [Hash, nil] Optional hash to replace the model's plan
      def after_model_callback(&block)
        raise ArgumentError, 'Callback must be a Proc or lambda.' unless block.is_a?(Proc)

        @definition.instance_variable_set(:@after_model_callback, block)
      end

      # Sets the callback to run before tool execution
      # @param block [Proc] The callback code to run
      # @yieldparam tool [ADK::Tool] The tool instance being executed
      # @yieldparam params [Hash] The parameters being passed to the tool
      # @yieldparam context [ADK::ToolContext] Context for tool execution and state management
      # @yieldreturn [Hash, nil] Optional hash to override normal tool execution
      def before_tool_callback(&block)
        raise ArgumentError, 'Callback must be a Proc or lambda.' unless block.is_a?(Proc)

        @definition.instance_variable_set(:@before_tool_callback, block)
      end

      # Sets the callback to run after tool execution
      # @param block [Proc] The callback code to run
      # @yieldparam tool [ADK::Tool] The tool instance that was executed
      # @yieldparam params [Hash] The parameters that were passed to the tool
      # @yieldparam context [ADK::ToolContext] Context for tool execution and state management
      # @yieldparam result [Hash] The tool's result hash that can be modified
      # @yieldreturn [Hash, nil] Optional hash to replace the tool's result
      def after_tool_callback(&block)
        raise ArgumentError, 'Callback must be a Proc or lambda.' unless block.is_a?(Proc)

        @definition.instance_variable_set(:@after_tool_callback, block)
      end

      # --- End Callback DSL Methods ---
    end
    private_constant :DefinitionProxy

    # Class method to create an AgentDefinition instance from a hash.
    # This is typically used when loading a definition from a persistent store.
    # @param hash_data [Hash] The hash containing agent definition attributes.
    # @return [ADK::AgentDefinition, nil] A new AgentDefinition instance or nil on error.
    def self.from_hash(hash_data)
      return nil unless hash_data.is_a?(Hash)

      definition = new

      # Helper method to convert array values to Sets if present in the source hash
      convert_to_set = lambda do |key, default = nil|
        if hash_data.key?(key)
          val = hash_data[key]
          val.is_a?(Array) ? Set.new(val.map(&:to_sym)) : (val.nil? ? default : Set.new([val.to_sym]))
        else
          default || Set.new
        end
      end

      # Map string or symbol keys to our keys
      definition.instance_variable_set(:@name, hash_data[:name]&.to_sym || hash_data['name']&.to_sym)
      definition.instance_variable_set(:@description, hash_data[:description]&.to_s || hash_data['description']&.to_s || '')
      definition.instance_variable_set(:@instruction, hash_data[:instruction]&.to_s || hash_data['instruction']&.to_s || '')

      # Handle tools/tool_names (expected to be an array of strings or symbols)
      tool_names = nil
      if hash_data.key?(:tool_names) || hash_data.key?('tool_names')
        tool_names = hash_data[:tool_names] || hash_data['tool_names']
      elsif hash_data.key?(:tools) || hash_data.key?('tools')
        tool_names = hash_data[:tools] || hash_data['tools']
      end

      # Convert tool_names to a Set of symbols (always ensure it's a Set)
      if tool_names.is_a?(Array)
        definition.instance_variable_set(:@tool_names, Set.new(tool_names.map(&:to_sym)))
      elsif tool_names.is_a?(String)
        # Special case: if it's a JSON string, try to parse it
        begin
          parsed_tools = JSON.parse(tool_names)
          if parsed_tools.is_a?(Array)
            definition.instance_variable_set(:@tool_names, Set.new(parsed_tools.map(&:to_sym)))
          else
            definition.instance_variable_set(:@tool_names, Set.new)
          end
        rescue JSON::ParserError
          # Not valid JSON, treat as single tool name
          definition.instance_variable_set(:@tool_names, Set.new([tool_names.to_sym]))
        end
      else
        # No valid tools provided, use empty set
        definition.instance_variable_set(:@tool_names, Set.new)
      end

      # Process model_name (string or symbol)
      model_name = hash_data[:model_name] || hash_data['model_name'] || hash_data[:model] || hash_data['model']
      definition.instance_variable_set(:@model_name, model_name&.to_sym)

      # Process temperature (float)
      temp_value = hash_data[:temperature] || hash_data['temperature']
      definition.instance_variable_set(:@temperature, temp_value&.to_f)

      # --- Process webhook fields ---
      # Boolean conversion helper for webhook_enabled
      wb_enabled = hash_data[:webhook_enabled] || hash_data['webhook_enabled']
      wb_enabled = wb_enabled.to_s.downcase == 'true' if wb_enabled.is_a?(String)
      definition.instance_variable_set(:@webhook_enabled, !!wb_enabled) # Force to boolean

      # webhook_validator can be symbol or nil
      wb_validator = hash_data[:webhook_validator] || hash_data['webhook_validator']
      definition.instance_variable_set(:@webhook_validator, wb_validator.is_a?(Symbol) ? wb_validator : nil)

      # webhook_secret is a string or nil
      wb_secret = hash_data[:webhook_secret] || hash_data['webhook_secret']
      # Special case: '<present>' is a placeholder used in to_h when the secret exists
      definition.instance_variable_set(:@webhook_secret, wb_secret == '<present>' ? wb_secret : wb_secret)

      # webhook_transformer and webhook_session_extractor are Procs (can't be serialized)
      # Always nil when recreated from a hash
      definition.instance_variable_set(:@webhook_transformer, nil)
      definition.instance_variable_set(:@webhook_session_extractor, nil)

      # --- Process MCP servers ---
      # MCP servers can be array of hashes, or JSON string
      mcp_value = hash_data[:mcp_servers] || hash_data['mcp_servers'] || hash_data[:mcp_servers_json] || hash_data['mcp_servers_json']
      if mcp_value.is_a?(String)
        begin
          parsed_mcp = JSON.parse(mcp_value)
          definition.instance_variable_set(:@mcp_servers, parsed_mcp.is_a?(Array) ? parsed_mcp : [])
        rescue JSON::ParserError
          # Not valid JSON, use empty array
          definition.instance_variable_set(:@mcp_servers, [])
        end
      elsif mcp_value.is_a?(Array)
        definition.instance_variable_set(:@mcp_servers, mcp_value)
      else
        definition.instance_variable_set(:@mcp_servers, [])
      end

      # --- Process fallback_mode (convert to symbol) ---
      fallback = hash_data[:fallback_mode] || hash_data['fallback_mode']
      if fallback.is_a?(String) || fallback.is_a?(Symbol)
        fb_sym = fallback.to_sym
        definition.instance_variable_set(:@fallback_mode, fb_sym == :echo ? :echo : :error)
      else
        definition.instance_variable_set(:@fallback_mode, :error) # Default
      end

      # --- Process MAS attributes ---
      # Sub-agent names (convert to Set of symbols)
      definition.instance_variable_set(:@sub_agent_names, convert_to_set.call(:sub_agent_names))

      # Output key (convert to symbol if present)
      output_key = hash_data[:output_key] || hash_data['output_key']
      definition.instance_variable_set(:@output_key, output_key&.to_sym)

      # --- MAS Workflow Agent Attributes ---
      # Agent type (convert to symbol, default to :llm)
      agent_type = hash_data[:agent_type] || hash_data['agent_type'] || :llm
      if agent_type.is_a?(String) || agent_type.is_a?(Symbol)
        agent_type_sym = agent_type.to_sym
        valid_types = %i[llm sequential parallel loop]
        # If invalid type, use default :llm
        agent_type_sym = :llm unless valid_types.include?(agent_type_sym)
        definition.instance_variable_set(:@agent_type, agent_type_sym)
      else
        definition.instance_variable_set(:@agent_type, :llm) # Default
      end

      # Workflow-specific sub-agent lists
      definition.instance_variable_set(:@sequential_sub_agent_names, convert_to_set.call(:sequential_sub_agent_names))
      definition.instance_variable_set(:@parallel_sub_agent_names, convert_to_set.call(:parallel_sub_agent_names))
      definition.instance_variable_set(:@loop_sub_agent_names, convert_to_set.call(:loop_sub_agent_names))

      # Loop configuration
      loop_max = hash_data[:loop_max_iterations] || hash_data['loop_max_iterations']
      definition.instance_variable_set(:@loop_max_iterations, loop_max&.to_i)

      loop_key = hash_data[:loop_condition_state_key] || hash_data['loop_condition_state_key']
      definition.instance_variable_set(:@loop_condition_state_key, loop_key&.to_sym)

      loop_value = hash_data[:loop_condition_expected_value] || hash_data['loop_condition_expected_value']
      definition.instance_variable_set(:@loop_condition_expected_value, loop_value)

      # Delegation targets
      definition.instance_variable_set(:@delegation_targets, convert_to_set.call(:delegation_targets))

      # --- Authentication fields ---
      # Auth credential names (convert to Set of symbols)
      definition.instance_variable_set(:@auth_credential_names, convert_to_set.call(:auth_credential_names))

      # Auth URL mappings (array of hashes)
      auth_mappings_raw = hash_data[:auth_url_mappings] || hash_data['auth_url_mappings'] || []
      if auth_mappings_raw.is_a?(String)
        begin
          auth_mappings_raw = JSON.parse(auth_mappings_raw)
        rescue JSON::ParserError
          auth_mappings_raw = []
        end
      end
      auth_url_mappings = (auth_mappings_raw || []).map do |m|
        pattern = m['pattern'] || m[:pattern]
        pattern_type = m['pattern_type'] || m[:pattern_type]
        # Convert back to Regexp if it was serialized as such
        if pattern_type == 'regexp' && pattern.is_a?(String)
          begin
            pattern = Regexp.new(pattern)
          rescue RegexpError
            # Keep as string if invalid regexp
          end
        end
        {
          pattern: pattern,
          scheme_name: (m['scheme_name'] || m[:scheme_name])&.to_sym,
          credential_name: (m['credential_name'] || m[:credential_name])&.to_sym
        }
      end
      definition.instance_variable_set(:@auth_url_mappings, auth_url_mappings)

      # Auth scheme assignments (hash of symbol -> symbol)
      auth_scheme_raw = hash_data[:auth_scheme_assignments] || hash_data['auth_scheme_assignments'] || {}
      if auth_scheme_raw.is_a?(String)
        begin
          auth_scheme_raw = JSON.parse(auth_scheme_raw)
        rescue JSON::ParserError
          auth_scheme_raw = {}
        end
      end
      auth_scheme_assignments = (auth_scheme_raw || {}).transform_keys(&:to_sym).transform_values(&:to_sym)
      definition.instance_variable_set(:@auth_scheme_assignments, auth_scheme_assignments)

      # Auth credential assignments (hash of symbol -> symbol)
      auth_cred_raw = hash_data[:auth_credential_assignments] || hash_data['auth_credential_assignments'] || {}
      if auth_cred_raw.is_a?(String)
        begin
          auth_cred_raw = JSON.parse(auth_cred_raw)
        rescue JSON::ParserError
          auth_cred_raw = {}
        end
      end
      auth_credential_assignments = (auth_cred_raw || {}).transform_keys(&:to_sym).transform_values(&:to_sym)
      definition.instance_variable_set(:@auth_credential_assignments, auth_credential_assignments)

      definition
    end
  end
end
