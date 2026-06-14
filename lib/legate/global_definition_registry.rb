# File: lib/legate/global_definition_registry.rb
# frozen_string_literal: true

require 'json'

module Legate
  # In-memory registry for AgentDefinition instances.
  # Serves as both the runtime definition registry (used by agents) and as a
  # drop-in replacement for the Redis-backed DefinitionStore used by the Web UI.
  #
  # Internal structure:
  #   @registry = { name_symbol => { definition: AgentDefinition, metadata: {} } }
  #
  # The `register`, `find`, `all`, and `clear!` methods maintain backward
  # compatibility with the original API. The new methods (`get_definition`,
  # `save_definition`, `update_definition`, `delete_definition`,
  # `list_definitions`, `check_connection`, `definition_exists?`) provide
  # the DefinitionStore interface the Web UI routes expect.
  module GlobalDefinitionRegistry
    @registry = {}
    @mutex = Mutex.new

    # ---------------------------------------------------------------------------
    # Original API (backward-compatible)
    # ---------------------------------------------------------------------------

    # Registers an AgentDefinition instance.
    # @param definition [Legate::AgentDefinition] The definition object to register.
    # @return [Boolean] true if registered successfully, false otherwise.
    def self.register(definition)
      unless definition.is_a?(Legate::AgentDefinition) && definition.name.is_a?(Symbol)
        Legate.logger.error("GlobalDefinitionRegistry: Invalid object passed to register: #{definition.inspect}")
        return false
      end

      name = definition.name
      @mutex.synchronize do
        if @registry.key?(name)
          Legate.logger.warn("GlobalDefinitionRegistry: Overwriting existing definition for agent :#{name}")
          # Preserve existing metadata when re-registering
          existing_metadata = @registry[name][:metadata] || {}
          @registry[name] = { definition: definition, metadata: existing_metadata }
        else
          @registry[name] = { definition: definition, metadata: {} }
        end
      end
      Legate.logger.debug("GlobalDefinitionRegistry: Registered definition for :#{name}")
      true
    end

    # Finds an AgentDefinition instance by name.
    # @param name [Symbol] The name of the agent definition.
    # @return [Legate::AgentDefinition, nil] The definition object or nil if not found.
    def self.find(name)
      unless name.is_a?(Symbol)
        Legate.logger.warn("GlobalDefinitionRegistry: Find called with non-symbol key: #{name.inspect}")
        return nil
      end
      entry = @mutex.synchronize { @registry[name] }
      entry&.[](:definition)
    end

    # Clears the registry (primarily for testing).
    def self.clear!
      @mutex.synchronize { @registry = {} }
      Legate.logger.debug('GlobalDefinitionRegistry: Cleared.')
    end

    # Returns the current registry hash mapping names to AgentDefinition objects.
    # @return [Hash{Symbol => Legate::AgentDefinition}]
    def self.all
      @mutex.synchronize do
        @registry.transform_values { |entry| entry[:definition] }.dup
      end
    end

    # ---------------------------------------------------------------------------
    # DefinitionStore-compatible API (used by Web UI routes)
    # ---------------------------------------------------------------------------

    # Retrieves a single agent definition as a hash with Web UI field names.
    #
    # Field name mapping from AgentDefinition#to_h:
    #   :tool_names  -> :tools       (Array of Symbols)
    #   :model_name  -> :model       (Symbol or nil)
    #   :mcp_servers -> :mcp_servers_json (JSON String)
    #
    # Metadata fields (e.g. :persistent_status, :last_run_at) are merged in.
    #
    # @param name [String, Symbol] The agent name.
    # @return [Hash, nil] A hash with symbol keys in Web UI format, or nil if not found.
    def self.get_definition(name)
      sym_name = normalize_name(name)
      return nil unless sym_name

      entry = @mutex.synchronize { @registry[sym_name] }
      return nil unless entry

      build_web_hash(entry)
    end

    # Saves a new agent definition. Supports two call signatures:
    #
    # 1. Keyword splat (from the create form):
    #      save_definition(name:, description:, tools:, model:, ...)
    #
    # 2. Two positional args (from the duplicate route):
    #      save_definition(new_name, definition_hash)
    #
    # @return [Boolean] true on success.
    def self.save_definition(*args, **kwargs)
      if args.length == 2
        # Positional form: save_definition(new_name, definition_hash)
        new_name = args[0]
        definition_hash = args[1]
        _save_from_hash(new_name, definition_hash)
      elsif args.empty? && !kwargs.empty?
        # Keyword form: save_definition(name:, description:, tools:, model:, ...)
        _save_from_keywords(**kwargs)
      else
        raise ArgumentError, 'save_definition expects either (name, hash) or keyword arguments'
      end
    end

    # Updates specific fields of an existing agent definition's metadata.
    # This is used for things like persistent_status, last_run_at, and also
    # for updating definition fields via the Web UI edit forms.
    #
    # @param name [String, Symbol] The agent name.
    # @param updates [Hash] A hash of field names to new values.
    # @return [Boolean] true if the agent was found and updated, false otherwise.
    def self.update_definition(name, updates)
      sym_name = normalize_name(name)
      return false unless sym_name

      @mutex.synchronize do
        entry = @registry[sym_name]
        return false unless entry

        definition = entry[:definition]
        # Snapshot for atomic rollback: a web edit that left the definition in a
        # state the constructor would reject (e.g. cleared instruction) used to
        # persist silently. We apply the batch, then validate! once and restore
        # the prior state on failure. (update_definition_field reassigns ivars
        # rather than mutating in place, so a shallow snapshot is a faithful
        # rollback.)
        ivar_snapshot = definition&.instance_variables&.to_h { |iv| [iv, definition.instance_variable_get(iv)] }
        metadata_snapshot = entry[:metadata].dup

        updates.each do |key, value|
          key_sym = key.to_sym
          # Check if this is a field that should update the AgentDefinition itself
          update_definition_field(definition, key_sym, value) if definition_field?(key_sym) && definition
          # Always store in metadata as well (for fields like persistent_status,
          # last_run_at, and as a cache for definition field overrides)
          entry[:metadata][key_sym] = value
        end

        if definition
          begin
            definition.validate!
          rescue StandardError => e
            ivar_snapshot.each { |iv, val| definition.instance_variable_set(iv, val) }
            entry[:metadata].replace(metadata_snapshot)
            Legate.logger.error("GlobalDefinitionRegistry: Rejected update for :#{sym_name} (would leave the definition invalid): #{e.message}")
            return false
          end
        end
      end

      Legate.logger.debug("GlobalDefinitionRegistry: Updated definition for :#{sym_name} with keys: #{updates.keys.join(', ')}")
      true
    end

    # Deletes an agent definition from the registry.
    # @param name [String, Symbol] The agent name.
    # @return [Boolean] true if deleted (or didn't exist), false on error.
    def self.delete_definition(name)
      sym_name = normalize_name(name)
      return true unless sym_name # Nothing to delete

      @mutex.synchronize { @registry.delete(sym_name) }
      Legate.logger.info("GlobalDefinitionRegistry: Deleted definition for :#{sym_name}")
      true
    end

    # Returns an array of hashes, each in the same format as get_definition output.
    # @return [Array<Hash>]
    def self.list_definitions
      entries = @mutex.synchronize { @registry.dup }
      entries.map { |_name, entry| build_web_hash(entry) }
             .compact
             .sort_by { |d| d[:name].to_s }
    end

    # Always returns true for the in-memory store (no external connection to check).
    # @return [Boolean] true
    def self.check_connection
      true
    end

    # Checks if an agent definition with the given name exists.
    # @param name [String, Symbol] The agent name.
    # @return [Boolean]
    def self.definition_exists?(name)
      sym_name = normalize_name(name)
      return false unless sym_name

      @mutex.synchronize { @registry.key?(sym_name) }
    end

    # ---------------------------------------------------------------------------
    # Private helpers
    # ---------------------------------------------------------------------------

    # Normalizes a name (String or Symbol) to a Symbol for internal use.
    # @param name [String, Symbol, nil]
    # @return [Symbol, nil]
    def self.normalize_name(name)
      return nil if name.nil?

      str = name.to_s.strip
      return nil if str.empty?

      str.to_sym
    end
    private_class_method :normalize_name

    # Builds a Web UI compatible hash from an internal registry entry.
    # Maps AgentDefinition field names to Web UI field names and merges metadata.
    def self.build_web_hash(entry)
      definition = entry[:definition]
      metadata = entry[:metadata] || {}

      if definition
        h = definition.to_h.dup

        # Map :tool_names -> :tools (array of symbols)
        h[:tools] = h.delete(:tool_names) || []
        h[:tools] = h[:tools].map(&:to_sym) if h[:tools].is_a?(Array)

        # Map :model_name -> :model
        h[:model] = h.delete(:model_name)

        # Convert :mcp_servers (Array) -> :mcp_servers_json (JSON String)
        mcp_array = h.delete(:mcp_servers) || []
        h[:mcp_servers_json] = mcp_array.is_a?(Array) ? mcp_array.to_json : '[]'

        # Ensure persistent_status defaults to 'stopped'
        h[:persistent_status] = metadata[:persistent_status] || 'stopped'

        # Merge all metadata fields (last_run_at, etc.)
        metadata.each do |key, value|
          # Metadata overrides definition fields for display purposes
          h[key] = value
        end

        # Ensure required defaults
        h[:fallback_mode] = h[:fallback_mode] || :error
        h[:instruction] ||= ''
        h[:agent_type] = h[:agent_type]&.to_sym || :llm
        h[:planning_strategy] = h[:planning_strategy]&.to_sym || :plan
        h[:sub_agent_names] ||= []
        h[:delegation_targets] ||= []
      else
        # Definition-less entry (created from hash via duplicate route)
        h = metadata.dup
        h[:persistent_status] ||= 'stopped'
        h[:fallback_mode] ||= :error
        h[:instruction] ||= ''
        h[:agent_type] = h[:agent_type]&.to_sym || :llm
        h[:planning_strategy] = h[:planning_strategy]&.to_sym || :plan
        h[:tools] ||= []
        h[:mcp_servers_json] ||= '[]'
        h[:sub_agent_names] ||= []
        h[:delegation_targets] ||= []
      end

      h
    end
    private_class_method :build_web_hash

    # Saves a definition from keyword arguments (create form).
    def self._save_from_keywords(name:, description: '', tools: [], model: nil,
                                 fallback_mode: :error, mcp_servers_json: '[]',
                                 instruction: '', webhook_enabled: false,
                                 webhook_secret: nil, agent_type: :llm,
                                 planning_strategy: :plan,
                                 sub_agent_names: [], sequential_sub_agent_names: [],
                                 parallel_sub_agent_names: [], loop_sub_agent_names: [],
                                 output_key: nil, delegation_targets: [],
                                 loop_max_iterations: nil, loop_condition_state_key: nil,
                                 loop_condition_expected_value: nil,
                                 auth_scheme_assignments: {}, auth_credential_assignments: {},
                                 auth_url_mappings: [])
      raise ArgumentError, 'Agent name cannot be empty.' if name.nil? || name.to_s.strip.empty?

      sym_name = name.to_s.strip.to_sym

      # Parse MCP servers JSON to array for AgentDefinition
      mcp_array = parse_mcp_json(mcp_servers_json)

      # Build a hash suitable for AgentDefinition.from_hash
      definition_data = {
        name: sym_name,
        description: description || '',
        instruction: instruction || '',
        tool_names: normalize_tools(tools),
        model_name: model,
        temperature: nil,
        fallback_mode: fallback_mode&.to_sym || :error,
        mcp_servers: mcp_array,
        webhook_enabled: !!webhook_enabled,
        webhook_secret: webhook_secret,
        agent_type: agent_type&.to_sym || :llm,
        planning_strategy: planning_strategy&.to_sym || :plan,
        sub_agent_names: Array(sub_agent_names).map(&:to_sym),
        output_key: output_key&.to_sym,
        sequential_sub_agent_names: Array(sequential_sub_agent_names).map(&:to_sym),
        parallel_sub_agent_names: Array(parallel_sub_agent_names).map(&:to_sym),
        loop_sub_agent_names: Array(loop_sub_agent_names).map(&:to_sym),
        delegation_targets: Array(delegation_targets).map(&:to_sym),
        loop_max_iterations: loop_max_iterations&.to_i,
        loop_condition_state_key: loop_condition_state_key&.to_sym,
        loop_condition_expected_value: loop_condition_expected_value,
        auth_scheme_assignments: auth_scheme_assignments || {},
        auth_credential_assignments: auth_credential_assignments || {},
        auth_url_mappings: auth_url_mappings || []
      }

      definition = Legate::AgentDefinition.from_hash(definition_data)

      @mutex.synchronize do
        @registry[sym_name] = {
          definition: definition,
          metadata: { persistent_status: 'stopped' }
        }
      end

      Legate.logger.info("GlobalDefinitionRegistry: Saved definition for :#{sym_name}")
      true
    end
    private_class_method :_save_from_keywords

    # Saves a definition from a name and hash (duplicate route).
    def self._save_from_hash(new_name, definition_hash)
      raise ArgumentError, 'Agent name cannot be empty.' if new_name.nil? || new_name.to_s.strip.empty?

      sym_name = new_name.to_s.strip.to_sym
      hash_data = definition_hash.is_a?(Hash) ? definition_hash.dup : {}

      # Normalize field names for AgentDefinition.from_hash compatibility
      hash_data[:name] = sym_name

      # Map Web UI field names back to AgentDefinition field names
      hash_data[:tool_names] = hash_data.delete(:tools) if hash_data.key?(:tools) && !hash_data.key?(:tool_names)
      hash_data[:model_name] = hash_data.delete(:model) if hash_data.key?(:model) && !hash_data.key?(:model_name)
      if hash_data.key?(:mcp_servers_json) && !hash_data.key?(:mcp_servers)
        mcp_json = hash_data.delete(:mcp_servers_json)
        hash_data[:mcp_servers] = parse_mcp_json(mcp_json)
      end

      # Normalize tools to symbols
      hash_data[:tool_names] = hash_data[:tool_names].map(&:to_sym) if hash_data[:tool_names].is_a?(Array)

      # Try to create an AgentDefinition from the hash
      definition = begin
        Legate::AgentDefinition.from_hash(hash_data)
      rescue StandardError => e
        Legate.logger.warn("GlobalDefinitionRegistry: Could not create AgentDefinition from hash for :#{sym_name}: #{e.message}")
        nil
      end

      # Extract metadata fields that are not part of AgentDefinition
      metadata = {}
      metadata_keys = %i[persistent_status last_run_at]
      metadata_keys.each do |mk|
        metadata[mk] = hash_data[mk] if hash_data.key?(mk)
      end
      metadata[:persistent_status] ||= 'stopped'

      @mutex.synchronize do
        @registry[sym_name] = {
          definition: definition,
          metadata: metadata
        }
      end

      Legate.logger.info("GlobalDefinitionRegistry: Saved definition for :#{sym_name} (from hash)")
      true
    end
    private_class_method :_save_from_hash

    # Parses an MCP servers JSON string into an array.
    def self.parse_mcp_json(mcp_json)
      return [] if mcp_json.nil? || mcp_json.to_s.strip.empty? || mcp_json.to_s.strip == '[]'

      if mcp_json.is_a?(String)
        begin
          parsed = JSON.parse(mcp_json)
          parsed.is_a?(Array) ? parsed : []
        rescue JSON::ParserError
          []
        end
      elsif mcp_json.is_a?(Array)
        mcp_json
      else
        []
      end
    end
    private_class_method :parse_mcp_json

    # Normalizes a tools value (could be array of strings, symbols, or JSON string).
    def self.normalize_tools(tools)
      if tools.is_a?(Array)
        tools.map(&:to_sym)
      elsif tools.is_a?(String)
        begin
          parsed = JSON.parse(tools)
          parsed.is_a?(Array) ? parsed.map(&:to_sym) : []
        rescue JSON::ParserError
          tools.strip.empty? ? [] : [tools.to_sym]
        end
      else
        []
      end
    end
    private_class_method :normalize_tools

    # Checks if a key corresponds to a field on AgentDefinition.
    DEFINITION_FIELDS = %i[
      description instruction tool_names model_name temperature
      fallback_mode mcp_servers webhook_enabled webhook_secret
      agent_type planning_strategy sub_agent_names output_key
      sequential_sub_agent_names parallel_sub_agent_names loop_sub_agent_names
      delegation_targets loop_max_iterations loop_condition_state_key
      loop_condition_expected_value auth_credential_names auth_url_mappings
      auth_scheme_assignments auth_credential_assignments
    ].freeze

    # Web UI uses different field names; map them to definition ivars.
    WEB_TO_DEFINITION_MAP = {
      tools: :tool_names,
      model: :model_name,
      mcp_servers_json: :mcp_servers
    }.freeze

    def self.definition_field?(key_sym)
      DEFINITION_FIELDS.include?(key_sym) || WEB_TO_DEFINITION_MAP.key?(key_sym)
    end
    private_class_method :definition_field?

    # Updates a field on an AgentDefinition instance via instance_variable_set.
    def self.update_definition_field(definition, key_sym, value)
      # Map web field names to definition ivar names
      ivar_name = WEB_TO_DEFINITION_MAP[key_sym] || key_sym

      case ivar_name
      when :tool_names
        tools = normalize_tools(value)
        definition.instance_variable_set(:@tool_names, Set.new(tools))
      when :model_name
        definition.instance_variable_set(:@model_name, value&.to_sym)
      when :mcp_servers
        if value.is_a?(String)
          definition.instance_variable_set(:@mcp_servers, parse_mcp_json(value))
        elsif value.is_a?(Array)
          definition.instance_variable_set(:@mcp_servers, value)
        end
      when :fallback_mode
        val_sym = value&.to_sym
        definition.instance_variable_set(:@fallback_mode, %i[error echo].include?(val_sym) ? val_sym : :error)
      when :agent_type
        val_sym = value&.to_sym
        valid = %i[llm sequential parallel loop]
        definition.instance_variable_set(:@agent_type, valid.include?(val_sym) ? val_sym : :llm)
      when :planning_strategy
        val_sym = value&.to_sym
        definition.instance_variable_set(:@planning_strategy, %i[plan react].include?(val_sym) ? val_sym : :plan)
      when :sub_agent_names, :sequential_sub_agent_names, :parallel_sub_agent_names,
           :loop_sub_agent_names, :delegation_targets, :auth_credential_names
        arr = value.is_a?(Array) ? value.map(&:to_sym) : []
        definition.instance_variable_set(:"@#{ivar_name}", Set.new(arr))
      when :output_key, :loop_condition_state_key
        definition.instance_variable_set(:"@#{ivar_name}", value&.to_sym)
      when :loop_max_iterations
        definition.instance_variable_set(:@loop_max_iterations, value&.to_i)
      when :temperature
        definition.instance_variable_set(:@temperature, value&.to_f)
      when :webhook_enabled
        definition.instance_variable_set(:@webhook_enabled, !!value)
      when :description, :instruction, :webhook_secret
        definition.instance_variable_set(:"@#{ivar_name}", value&.to_s)
      when :loop_condition_expected_value
        definition.instance_variable_set(:@loop_condition_expected_value, value)
      when :auth_url_mappings
        definition.instance_variable_set(:@auth_url_mappings, value.is_a?(Array) ? value : [])
      when :auth_scheme_assignments, :auth_credential_assignments
        definition.instance_variable_set(:"@#{ivar_name}", value.is_a?(Hash) ? value : {})
      end
    rescue StandardError => e
      Legate.logger.warn("GlobalDefinitionRegistry: Failed to update definition field :#{ivar_name}: #{e.message}")
    end
    private_class_method :update_definition_field
  end
end
