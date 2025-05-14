# File: spec/adk/definition_store/redis_store_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'redis'
require 'json'
require 'adk/definition_store/redis_store'
require 'adk/errors' # Include ADK::Errors for specific error types
require 'adk/agent' # Required for DEFAULT_MODEL constant
require 'logger'

RSpec.describe ADK::DefinitionStore::RedisStore do
  # Use spy for logger to track calls without strict expectation setup everywhere
  let(:mock_redis) {
    instance_double(Redis, multi: true, pipelined: true, ping: 'PONG', hmget: [], hset: 0, sadd: 1, sismember: false,
                           del: 0, srem: 0, smembers: [])
  }
  let(:logger_double) { spy('Logger') }
  let(:store) { described_class.new(redis_client: mock_redis) }

  # Sample definition data
  let(:agent_name) { 'test_agent' }
  let(:description) { 'A test agent description' }
  let(:tools) { %w[tool_a tool_b] }
  let(:tools_json) { tools.to_json }
  let(:model) { 'gpt-4o' }
  let(:fallback_mode) { :error }
  let(:fallback_str) { fallback_mode.to_s }
  let(:mcp_servers) { [{ 'url' => 'http://localhost:8080' }] }
  let(:mcp_servers_json) { mcp_servers.to_json }
  let(:agent_key) { "#{described_class::AGENT_HASH_PREFIX}#{agent_name}" }
  let(:agents_set_key) { described_class::AGENTS_SET_KEY }
  let(:webhook_enabled) { false }
  let(:webhook_secret) { nil }

  before do
    # Stub the ADK logger to prevent actual logging during tests
    allow(ADK).to receive(:logger).and_return(logger_double)
    # Re-initialize store in each test to ensure clean state and logger stubbing
    @store = described_class.new(redis_client: mock_redis)
  end

  describe '#initialize' do
    it 'initializes with a Redis client and logs info' do
      expect(ADK.logger).to receive(:info).with('ADK::DefinitionStore::RedisStore initialized.')
      described_class.new(redis_client: mock_redis)
    end

    it 'logs error and sets @redis to nil if logger.info fails during initialization' do
      init_error = StandardError.new('Initial logger setup failed')
      allow(ADK).to receive(:logger).and_return(logger_double)
      allow(logger_double).to receive(:info).with('ADK::DefinitionStore::RedisStore initialized.').and_raise(init_error)

      expect(logger_double).to receive(:error).with(/Failed to initialize RedisStore: #{init_error.message}/)

      store_instance = nil
      expect {
        store_instance = described_class.new(redis_client: mock_redis)
      }.not_to raise_error # The rescue block should prevent the error from propagating

      expect(store_instance.instance_variable_get(:@redis)).to be_nil
    end

    it 'logs an error during operations if initialized with a non-functional client' do
      bad_redis = instance_double(Redis)
      allow(bad_redis).to receive(:ping).and_raise(Redis::CannotConnectError, 'mock connection error')
      store_with_bad_client = described_class.new(redis_client: bad_redis)

      expect(ADK.logger).to receive(:error).with(/Redis connection check failed: Redis::CannotConnectError - mock connection error/)
      expect(store_with_bad_client.check_connection).to be false

      allow(bad_redis).to receive(:sismember).and_raise(Redis::CannotConnectError, 'mock connection error')
      expect(ADK.logger).to receive(:error).with(/Redis error checking agent existence.*Redis::CannotConnectError.*mock connection error/)
      expect {
        store_with_bad_client.definition_exists?('any_agent')
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Redis error checking agent existence/)
    end

    it 'raises ConfigurationError if redis client is nil when methods are called' do
      store_no_redis = described_class.new(redis_client: nil)
      expect {
        store_no_redis.save_definition(name: agent_name, description: description, tools: tools, model: model,
                                       fallback_mode: fallback_mode, mcp_servers_json: mcp_servers_json)
      }.to raise_error(ADK::DefinitionStore::ConfigurationError, /Redis client not available/)
      expect {
        store_no_redis.get_definition(agent_name)
      }.to raise_error(ADK::DefinitionStore::ConfigurationError,
                       /Redis client not available/)
      expect {
        store_no_redis.update_definition(agent_name,
                                         {})
      }.to raise_error(ADK::DefinitionStore::ConfigurationError, /Redis client not available/)
      expect {
        store_no_redis.delete_definition(agent_name)
      }.to raise_error(ADK::DefinitionStore::ConfigurationError,
                       /Redis client not available/)
      expect {
        store_no_redis.list_definitions
      }.to raise_error(ADK::DefinitionStore::ConfigurationError,
                       /Redis client not available/)
      expect {
        store_no_redis.definition_exists?(agent_name)
      }.to raise_error(ADK::DefinitionStore::ConfigurationError,
                       /Redis client not available/)
      expect {
        store_no_redis.check_connection
      }.to raise_error(ADK::DefinitionStore::ConfigurationError,
                       /Redis client not available/)
    end
  end

  describe '#save_definition' do
    let(:save_args) {
      { name: agent_name, description: description, tools: tools, model: model, fallback_mode: fallback_mode,
        mcp_servers_json: mcp_servers_json, webhook_enabled: webhook_enabled, webhook_secret: webhook_secret,
        agent_type: :sequential }
    }

    it 'successfully saves a valid definition using MULTI' do
      # Mock the multi block execution
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]) # Simulate successful results
      expect(mock_redis).to receive(:hset).with(agent_key, 'name', agent_name)
      expect(mock_redis).to receive(:hset).with(agent_key, 'description', description)
      expect(mock_redis).to receive(:hset).with(agent_key, 'tools', tools_json)
      expect(mock_redis).to receive(:hset).with(agent_key, 'model', model)
      expect(mock_redis).to receive(:hset).with(agent_key, 'fallback_mode', fallback_str)
      expect(mock_redis).to receive(:hset).with(agent_key, 'mcp_servers_json', mcp_servers_json)
      expect(mock_redis).to receive(:hset).with(agent_key, 'instruction', '') # Expect default instruction
      expect(mock_redis).to receive(:hset).with(agent_key, 'webhook_enabled', webhook_enabled.to_s)
      expect(mock_redis).to receive(:hset).with(agent_key, 'webhook_secret', webhook_secret || '')
      expect(mock_redis).to receive(:hset).with(agent_key, 'persistent_status', 'stopped')
      expect(mock_redis).to receive(:hset).with(agent_key, 'agent_type', 'sequential') # Check agent_type is saved
      expect(mock_redis).to receive(:sadd).with(agents_set_key, agent_name)
      expect(ADK.logger).to receive(:info).with("Agent definition '#{agent_name}' saved successfully.")

      expect(@store.save_definition(**save_args)).to be true
    end

    it 'saves with default model if model is nil' do
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1, 1, 1, 1, 1, 1, 1])
      expect(mock_redis).to receive(:hset).with(agent_key, 'model', ADK::Agent::DEFAULT_MODEL) # Check default
      allow(mock_redis).to receive(:hset) # Allow other hsets
      allow(mock_redis).to receive(:sadd)
      expect(@store.save_definition(**save_args.merge(model: nil))).to be true
    end

    it 'saves with empty array JSON if mcp_servers_json is nil or empty' do
      # Ensure multi returns an array, not true, fixing NoMethodError: undefined method `any?` for true
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1] * 8).twice # Now 8 commands (with instruction)
      expect(mock_redis).to receive(:hset).with(agent_key, 'mcp_servers_json', '[]').twice # Once for nil, once for empty string
      allow(mock_redis).to receive(:hset) # Allow other hsets
      allow(mock_redis).to receive(:sadd)
      expect(@store.save_definition(**save_args.merge(mcp_servers_json: nil))).to be true
      expect(@store.save_definition(**save_args.merge(mcp_servers_json: '   '))).to be true
    end

    it 'saves with empty array JSON if tools is nil or not an array' do
      # Ensure multi returns an array
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1] * 8).twice # 8 commands
      expect(mock_redis).to receive(:hset).with(agent_key, 'tools', '[]').twice # Once for nil, once for non-array
      allow(mock_redis).to receive(:hset) # Allow other hsets
      allow(mock_redis).to receive(:sadd)
      expect(@store.save_definition(**save_args.merge(tools: nil))).to be true
      expect(@store.save_definition(**save_args.merge(tools: 'not-an-array'))).to be true
    end

    it 'raises ArgumentError if name is nil or empty' do
      expect {
        @store.save_definition(**save_args.merge(name: nil))
      }.to raise_error(ArgumentError, /Agent name cannot be empty/)
      expect {
        @store.save_definition(**save_args.merge(name: '  '))
      }.to raise_error(ArgumentError, /Agent name cannot be empty/)
    end

    it 'raises ArgumentError for invalid MCP JSON' do
      invalid_json = '{"url": "bad"}' # Not an array
      expect {
        @store.save_definition(**save_args.merge(mcp_servers_json: invalid_json))
      }.to raise_error(ArgumentError,
                       /MCP configuration must be a JSON array/)

      unparseable_json = '[{not json]}'
      expect {
        @store.save_definition(**save_args.merge(mcp_servers_json: unparseable_json))
      }.to raise_error(ArgumentError,
                       /Invalid format for MCP Server Configurations/)
    end

    it 'raises StoreError if Redis transaction is aborted' do
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return(nil) # Simulate abort
      allow(mock_redis).to receive(:hset)
      allow(mock_redis).to receive(:sadd)
      expect(ADK.logger).to receive(:error).with(/Redis transaction for saving agent .* failed \(aborted\)/)
      expect {
        @store.save_definition(**save_args)
      }.to raise_error(ADK::DefinitionStore::StoreError, /Redis transaction aborted/)
    end

    it 'raises StoreError on Redis command error within MULTI' do
      # Simulate a command error object being returned in the multi results
      error_result = [1, Redis::CommandError.new('Mock Command Error'), 1, 1, 1, 1, 1, 1] # 8 results
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return(error_result)

      # Expect the calls *within* the multi block explicitly
      expect(mock_redis).to receive(:hset).with(agent_key, 'name', agent_name)
      expect(mock_redis).to receive(:hset).with(agent_key, 'description', description || '')
      expect(mock_redis).to receive(:hset).with(agent_key, 'tools', tools_json)
      expect(mock_redis).to receive(:hset).with(agent_key, 'model', model || ADK::Agent::DEFAULT_MODEL)
      expect(mock_redis).to receive(:hset).with(agent_key, 'fallback_mode', fallback_str)
      expect(mock_redis).to receive(:hset).with(agent_key, 'mcp_servers_json', mcp_servers_json || '[]')
      expect(mock_redis).to receive(:hset).with(agent_key, 'instruction', '') # Expect default instruction
      expect(mock_redis).to receive(:hset).with(agent_key, 'webhook_enabled', webhook_enabled.to_s)
      expect(mock_redis).to receive(:hset).with(agent_key, 'webhook_secret', webhook_secret || '')
      expect(mock_redis).to receive(:sadd).with(agents_set_key, agent_name)

      expect(ADK.logger).to receive(:error).with(/Redis command error during multi.*#{error_result.inspect}/)
      expect {
        @store.save_definition(**save_args)
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Redis command error while saving agent '#{agent_name}'./)
    end

    it 'raises StoreError on generic Redis error' do
      redis_error = Redis::ConnectionError.new('Cannot connect')
      expect(mock_redis).to receive(:multi).and_raise(redis_error)
      expect(ADK.logger).to receive(:error).with(/Redis error saving agent.*#{redis_error.class}.*#{redis_error.message}/)
      expect {
        @store.save_definition(**save_args)
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Redis error saving agent definition: #{redis_error.message}/)
    end

    it 'raises StoreError on JSON generation error for tools' do
      allow(tools).to receive(:to_json).and_raise(JSON::GeneratorError.new('mock json gen error'))
      expect(mock_redis).not_to receive(:multi)
      expect(ADK.logger).to receive(:error).with(/Failed to serialize tools array.*mock json gen error/)
      expect {
        @store.save_definition(**save_args)
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Internal error serializing tool data/)
    end

    it 'raises StoreError on unexpected errors' do
      unexpected_error = StandardError.new('Something unexpected')
      expect(mock_redis).to receive(:multi).and_raise(unexpected_error)
      expect(ADK.logger).to receive(:error).with(/Unexpected error saving agent.*#{unexpected_error.class}.*#{unexpected_error.message}/m)
      expect {
        @store.save_definition(**save_args)
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Unexpected error saving agent definition: #{unexpected_error.message}/)
    end

    it 'saves with default llm agent_type if not specified' do
      # Setup multi to return success but don't verify all calls
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
      # Allow any hset calls
      allow(mock_redis).to receive(:hset)
      # But specifically expect agent_type to be set to 'llm'
      expect(mock_redis).to receive(:hset).with(agent_key, 'agent_type', 'llm')
      allow(mock_redis).to receive(:sadd)
      expect(@store.save_definition(**save_args.merge(agent_type: nil))).to be true
    end
  end

  describe '#get_definition' do
    let(:redis_hash_values) do
      # Ensure this array aligns with AGENT_DEFINITION_FIELDS order
      [
        agent_name,          # name
        description,         # description
        tools_json,          # tools
        model,               # model
        fallback_str,        # fallback_mode
        mcp_servers_json,    # mcp_servers_json
        '',                  # instruction (default empty string)
        webhook_enabled.to_s, # webhook_enabled
        webhook_secret || '', # webhook_secret
        'stopped',           # persistent_status
        'sequential'         # agent_type
      ]
    end
    let(:expected_definition) do
      {
        name: agent_name.to_sym, # Should return symbol
        description: description,
        tools: tools.map(&:to_sym), # Should return symbols
        model: model,
        fallback_mode: fallback_mode,
        mcp_servers_json: mcp_servers_json,
        instruction: '',
        webhook_enabled: webhook_enabled,
        webhook_secret: webhook_secret,
        persistent_status: 'stopped',
        agent_type: :sequential
      }
    end

    # This test needs adjustment based on whether get_definition should symbolize keys/values
    it 'successfully retrieves and parses an existing definition' do
      # Expected data including default instruction and assuming get_definition symbolizes keys and tool names
      expected_definition_get = {
        name: :test_agent, # Symbolized
        description: 'A test agent description',
        model: 'gpt-4o',
        instruction: '', # Expect default empty string
        tools: %i[tool_a tool_b], # Symbolized
        fallback_mode: :error,
        mcp_servers_json: JSON.generate([{ url: 'http://localhost:8080' }]),
        webhook_enabled: false,
        webhook_secret: nil,
        persistent_status: 'stopped',
        agent_type: :sequential
      }
      # Mock redis values corresponding to the expected hash
      redis_values_get = [
        'test_agent',
        'A test agent description',
        '["tool_a", "tool_b"]', # Tools as JSON string
        'gpt-4o',
        'error', # Fallback mode as string
        JSON.generate([{ url: 'http://localhost:8080' }]),
        '', # Instruction
        'false',
        '',
        'stopped',
        'sequential'
      ]

      expect(mock_redis).to receive(:hmget)
        .with("#{described_class::AGENT_HASH_PREFIX}test_agent", *described_class::AGENT_DEFINITION_FIELDS)
        .and_return(redis_values_get)
      expect(ADK.logger).to receive(:debug).with("Retrieved definition for agent 'test_agent'.")

      definition = @store.get_definition('test_agent')
      expect(definition).to eq(expected_definition_get)
    end

    it 'returns nil if agent name is nil or empty' do
      expect(mock_redis).not_to receive(:hmget)
      expect(@store.get_definition(nil)).to be_nil
      expect(@store.get_definition('  ')).to be_nil
    end

    it 'returns nil if agent definition does not exist in Redis' do
      expect(mock_redis).to receive(:hmget)
        .with(agent_key, *described_class::AGENT_DEFINITION_FIELDS)
        .and_return([nil] * described_class::AGENT_DEFINITION_FIELDS.length)
      expect(@store.get_definition(agent_name)).to be_nil
    end

    it 'uses default model if model field is missing from Redis' do
      values_missing_model = redis_hash_values.dup
      model_index = described_class::AGENT_DEFINITION_FIELDS.index('model')
      values_missing_model[model_index] = nil

      expect(mock_redis).to receive(:hmget).and_return(values_missing_model)
      definition = @store.get_definition(agent_name)
      expect(definition[:model]).to eq(ADK::Agent::DEFAULT_MODEL)
    end

    it 'uses default empty array JSON if mcp_servers_json is missing' do
      values_missing_mcp = redis_hash_values.dup
      mcp_index = described_class::AGENT_DEFINITION_FIELDS.index('mcp_servers_json')
      values_missing_mcp[mcp_index] = nil

      expect(mock_redis).to receive(:hmget).and_return(values_missing_mcp)
      definition = @store.get_definition(agent_name)
      expect(definition[:mcp_servers_json]).to eq('[]')
    end

    it 'returns empty array for tools if tools field is missing or empty JSON' do
      values_missing_tools = redis_hash_values.dup
      tools_index = described_class::AGENT_DEFINITION_FIELDS.index('tools')
      values_missing_tools[tools_index] = nil
      expect(mock_redis).to receive(:hmget).and_return(values_missing_tools)
      expect(@store.get_definition(agent_name)[:tools]).to eq([])

      values_empty_tools_json = redis_hash_values.dup
      values_empty_tools_json[tools_index] = '[]'
      expect(mock_redis).to receive(:hmget).and_return(values_empty_tools_json)
      expect(@store.get_definition(agent_name)[:tools]).to eq([])
    end

    it 'correctly parses fallback_mode symbol' do
      values_echo_fallback = redis_hash_values.dup
      fallback_index = described_class::AGENT_DEFINITION_FIELDS.index('fallback_mode')
      values_echo_fallback[fallback_index] = 'echo'
      expect(mock_redis).to receive(:hmget).and_return(values_echo_fallback)
      expect(@store.get_definition(agent_name)[:fallback_mode]).to eq(:echo)

      values_other_fallback = redis_hash_values.dup
      values_other_fallback[fallback_index] = 'something_else' # Defaults to :error
      expect(mock_redis).to receive(:hmget).and_return(values_other_fallback)
      expect(@store.get_definition(agent_name)[:fallback_mode]).to eq(:error)
    end

    it 'correctly parses agent_type symbol' do
      values_sequential = redis_hash_values.dup
      agent_type_index = described_class::AGENT_DEFINITION_FIELDS.index('agent_type')
      values_sequential[agent_type_index] = 'sequential'
      expect(mock_redis).to receive(:hmget).and_return(values_sequential)
      expect(@store.get_definition(agent_name)[:agent_type]).to eq(:sequential)

      values_invalid_type = redis_hash_values.dup
      values_invalid_type[agent_type_index] = 'invalid_type' # Defaults to :llm
      expect(mock_redis).to receive(:hmget).and_return(values_invalid_type)
      expect(@store.get_definition(agent_name)[:agent_type]).to eq(:llm)

      values_missing_type = redis_hash_values.dup
      values_missing_type[agent_type_index] = nil # Defaults to :llm
      expect(mock_redis).to receive(:hmget).and_return(values_missing_type)
      expect(@store.get_definition(agent_name)[:agent_type]).to eq(:llm)
    end

    it 'raises StoreError on Redis error' do
      redis_error = Redis::TimeoutError.new('Timeout')
      expect(mock_redis).to receive(:hmget).and_raise(redis_error)
      expect(ADK.logger).to receive(:error).with(/Redis error getting agent.*#{redis_error.class}.*#{redis_error.message}/)
      expect {
        @store.get_definition(agent_name)
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Redis error getting agent definition: #{redis_error.message}/)
    end

    it 'raises StoreError on JSON parsing error for tools' do
      bad_tools_json_values = redis_hash_values.dup
      tools_index = described_class::AGENT_DEFINITION_FIELDS.index('tools')
      bad_tools_json_values[tools_index] = '[not json'
      expect(mock_redis).to receive(:hmget).and_return(bad_tools_json_values)
      expect(ADK.logger).to receive(:error).with(/Failed to parse JSON fields for agent '#{agent_name}'.*unexpected token at 'not json'/)
      expect {
        @store.get_definition(agent_name)
      }.to raise_error(ADK::DefinitionStore::StoreError, /Error parsing stored JSON data/)
    end

    it 'raises StoreError on unexpected errors' do
      unexpected_error = StandardError.new('Something went wrong')
      expect(mock_redis).to receive(:hmget).and_raise(unexpected_error)
      expect(ADK.logger).to receive(:error).with(/Unexpected error getting agent.*#{unexpected_error.class}.*#{unexpected_error.message}/m)
      expect {
        @store.get_definition(agent_name)
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Unexpected error getting agent definition: #{unexpected_error.message}/)
    end
  end

  describe '#update_definition' do
    let(:updates) { { description: 'New description', model: 'gpt-4-turbo' } }
    let(:updates_with_tools) { { tools: ['new_tool'], fallback_mode: :echo } }
    let(:updates_with_mcp) { { mcp_servers_json: '[{"url": "http://new"}]' } }
    let(:redis_update_payload) { { 'description' => 'New description', 'model' => 'gpt-4-turbo' } }

    before do
      # Assume agent exists by default for update tests
      allow(@store).to receive(:definition_exists?).with(agent_name).and_return(true)
    end

    it 'successfully updates specified fields' do
      expect(mock_redis).to receive(:hset).with(agent_key, redis_update_payload).and_return(0) # 0 means fields updated
      expect(ADK.logger).to receive(:info).with(/Agent definition .* updated successfully with fields: description, model/)
      expect(@store.update_definition(agent_name, updates)).to be true
    end

    it 'correctly serializes tools, mcp_servers_json, and fallback_mode' do
      # Tools & Fallback Mode
      tools_fallback_payload = { 'tools' => '["new_tool"]', 'fallback_mode' => 'echo' }
      expect(mock_redis).to receive(:hset).with(agent_key,
                                                tools_fallback_payload).and_return(tools_fallback_payload.keys.length)
      expect(ADK.logger).to receive(:info).with(/updated successfully with fields: tools, fallback_mode/)
      expect(@store.update_definition(agent_name, updates_with_tools)).to be true

      # MCP
      mcp_payload = { 'mcp_servers_json' => '[{"url": "http://new"}]' }
      expect(mock_redis).to receive(:hset).with(agent_key, mcp_payload).and_return(mcp_payload.keys.length)
      expect(ADK.logger).to receive(:info).with(/updated successfully with fields: mcp_servers_json/)
      expect(@store.update_definition(agent_name, updates_with_mcp)).to be true
    end

    it 'validates MCP JSON during update' do
      invalid_mcp_update = { mcp_servers_json: '{"not": "an array"}' }
      expect(mock_redis).not_to receive(:hset)
      expect {
        @store.update_definition(agent_name,
                                 invalid_mcp_update)
      }.to raise_error(ArgumentError, /MCP servers must be an array/)

      unparseable_mcp_update = { mcp_servers_json: '[[bad' }
      expect {
        @store.update_definition(agent_name,
                                 unparseable_mcp_update)
      }.to raise_error(ArgumentError, /Invalid MCP servers JSON/)
    end

    it 'returns false if agent does not exist' do
      allow(@store).to receive(:definition_exists?).with('non_existent_agent').and_return(false)
      expect(mock_redis).not_to receive(:hset)
      expect(ADK.logger).to receive(:warn).with("Attempted to update non-existent agent: 'non_existent_agent'")
      expect(@store.update_definition('non_existent_agent', updates)).to be false
    end

    it 'raises ArgumentError if agent name is nil or empty' do
      expect { @store.update_definition(nil, updates) }.to raise_error(ArgumentError, /Agent name cannot be empty/)
      expect { @store.update_definition('  ', updates) }.to raise_error(ArgumentError, /Agent name cannot be empty/)
    end

    it 'raises ArgumentError if updates hash is nil or empty' do
      expect { @store.update_definition(agent_name, nil) }.to raise_error(ArgumentError, /Updates hash cannot be empty/)
      expect { @store.update_definition(agent_name, {}) }.to raise_error(ArgumentError, /Updates hash cannot be empty/)
    end

    it 'ignores attempts to update the agent name and logs a warning' do
      update_with_name = { name: 'new_name', description: 'desc' }
      valid_payload = { 'description' => 'desc' }
      expect(mock_redis).to receive(:hset).with(agent_key, valid_payload).and_return(valid_payload.keys.length) # Only description update
      expect(ADK.logger).to receive(:warn).with("Attempted to update agent name for '#{agent_name}', which is not allowed.")
      expect(ADK.logger).to receive(:info).with(/updated successfully with fields: description/)
      expect(@store.update_definition(agent_name, update_with_name)).to be true
    end

    it 'ignores attempts to update unknown fields and logs a warning' do
      update_with_unknown = { unknown_field: 'value', description: 'desc' }
      valid_payload = { 'description' => 'desc' }
      expect(mock_redis).to receive(:hset).with(agent_key, valid_payload).and_return(valid_payload.keys.length) # Only description update
      expect(ADK.logger).to receive(:warn).with("Attempted to update unknown field 'unknown_field' for agent '#{agent_name}'. Ignoring.")
      expect(ADK.logger).to receive(:info).with(/updated successfully with fields: description/)
      expect(@store.update_definition(agent_name, update_with_unknown)).to be true
    end

    it 'returns false if only invalid/ignored fields are provided' do
      update_ignored_only = { name: 'new_name', unknown_field: 'value' }
      expect(mock_redis).not_to receive(:hset)
      expect(ADK.logger).to receive(:warn).with(/Attempted to update agent name/)
      expect(ADK.logger).to receive(:warn).with(/Attempted to update unknown field 'unknown_field'/)
      expect(@store.update_definition(agent_name, update_ignored_only)).to be false
    end

    it 'raises StoreError on Redis error during hset' do
      redis_error = Redis::CommandError.new('Update failed')
      expect(mock_redis).to receive(:hset).with(agent_key, redis_update_payload).and_raise(redis_error)
      expect(ADK.logger).to receive(:error).with(/Redis error updating agent.*#{redis_error.class}.*#{redis_error.message}/)
      expect {
        @store.update_definition(agent_name,
                                 updates)
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Redis error updating agent definition: #{redis_error.message}/)
    end

    it 'raises StoreError on JSON generation error for tools update' do
      bad_tools_update = { tools: ['tool1'] }
      bad_tools_array = ['tool1']
      allow(bad_tools_array).to receive(:to_json).and_raise(JSON::GeneratorError.new('tool json gen error'))
      bad_tools_update_with_mock = { tools: bad_tools_array }

      expect(mock_redis).not_to receive(:hset)
      expect(ADK.logger).to receive(:error).with("JSON error serializing tools for agent 'test_agent': tool json gen error")
      expect {
        @store.update_definition(agent_name,
                                 bad_tools_update_with_mock)
      }.to raise_error(ADK::DefinitionStore::StoreError, /Failed to serialize tools for agent/)
    end

    it 'raises StoreError on unexpected errors' do
      unexpected_error = StandardError.new('Boom')
      processed_updates = { 'description' => 'New description', 'model' => 'gpt-4-turbo' }
      expect(mock_redis).to receive(:hset).with(agent_key, processed_updates).and_raise(unexpected_error)
      expect(ADK.logger).to receive(:error).with(/Unexpected error updating agent.*#{unexpected_error.class}.*#{unexpected_error.message}/m)
      expect {
        @store.update_definition(agent_name,
                                 updates)
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Unexpected error updating agent definition: #{unexpected_error.message}/)
    end
  end

  describe '#delete_definition' do
    it 'successfully deletes an existing agent using MULTI' do
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1, 1])
      expect(mock_redis).to receive(:del).with(agent_key)
      expect(mock_redis).to receive(:srem).with(agents_set_key, agent_name)
      expect(ADK.logger).to receive(:info).with("Agent definition '#{agent_name}' deleted successfully (or did not exist).")
      expect(@store.delete_definition(agent_name)).to be true
    end

    it 'returns true even if agent did not exist (idempotent)' do
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([0, 0])
      expect(mock_redis).to receive(:del).with(agent_key)
      expect(mock_redis).to receive(:srem).with(agents_set_key, agent_name)
      expect(ADK.logger).to receive(:info).with("Agent definition '#{agent_name}' deleted successfully (or did not exist).")
      expect(@store.delete_definition(agent_name)).to be true
    end

    it 'returns true if agent name is nil or empty without calling Redis' do
      expect(mock_redis).not_to receive(:multi)
      expect(@store.delete_definition(nil)).to be true
      expect(@store.delete_definition('  ')).to be true
    end

    it 'raises StoreError if Redis transaction is aborted' do
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return(nil)
      allow(mock_redis).to receive(:del)
      allow(mock_redis).to receive(:srem)
      expect(ADK.logger).to receive(:error).with(/Redis transaction for deleting agent .* failed \(aborted\)/)
      expect {
        @store.delete_definition(agent_name)
      }.to raise_error(ADK::DefinitionStore::StoreError, /Redis transaction aborted/)
    end

    it 'raises StoreError on Redis error' do
      redis_error = Redis::ConnectionError.new('Write failed')
      expect(mock_redis).to receive(:multi).and_raise(redis_error)
      expect(ADK.logger).to receive(:error).with(/Redis error deleting agent.*#{redis_error.class}.*#{redis_error.message}/)
      expect {
        @store.delete_definition(agent_name)
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Redis error deleting agent definition: #{redis_error.message}/)
    end

    it 'raises StoreError on unexpected errors' do
      unexpected_error = StandardError.new('Gone wrong')
      expect(mock_redis).to receive(:multi).and_raise(unexpected_error)
      expect(ADK.logger).to receive(:error).with(/Unexpected error deleting agent.*#{unexpected_error.class}.*#{unexpected_error.message}/m)
      expect {
        @store.delete_definition(agent_name)
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Unexpected error deleting agent definition: #{unexpected_error.message}/)
    end
  end

  describe '#list_definitions' do
    let(:agent_name_1) { 'agent1' }
    let(:agent_name_2) { 'agent2' }
    let(:agent_names) { [agent_name_1, agent_name_2] }
    let(:agent_key_1) { @store.send(:agent_redis_key, agent_name_1) }
    let(:agent_key_2) { @store.send(:agent_redis_key, agent_name_2) }
    let(:all_fields) { ADK::DefinitionStore::RedisStore::AGENT_DEFINITION_FIELDS }
    # Correct mock data generation to return actual expected values for this test
    let(:summary_values_1) {
      # Simulating data fetched for agent1
      vals = {}
      vals['name'] = agent_name_1
      vals['description'] = 'Desc 1'
      vals['model'] = ADK::Agent::DEFAULT_MODEL
      vals['tools'] = '[]' # JSON string
      vals['fallback_mode'] = 'error'
      vals['mcp_servers_json'] = '[]'
      vals['instruction'] = ''
      vals['webhook_enabled'] = webhook_enabled.to_s
      vals['webhook_secret'] = webhook_secret || ''
      vals['persistent_status'] = nil
      vals['agent_type'] = 'llm' # Default agent type
      all_fields.map { |f| vals[f] } # Return values in correct order
    }
    let(:summary_values_2) {
      # Simulating data fetched for agent2
      vals = {}
      vals['name'] = agent_name_2
      vals['description'] = 'Desc 2'
      vals['model'] = ADK::Agent::DEFAULT_MODEL
      vals['tools'] = '[]'
      vals['fallback_mode'] = 'error'
      vals['mcp_servers_json'] = '[]'
      vals['instruction'] = ''
      vals['webhook_enabled'] = webhook_enabled.to_s
      vals['webhook_secret'] = webhook_secret || ''
      vals['persistent_status'] = nil
      vals['agent_type'] = 'llm' # Default agent type
      all_fields.map { |f| vals[f] }
    }
    let(:expected_list) do
      [
        {
          name: :agent1, # Expect symbols
          description: 'Desc 1',
          model: ADK::Agent::DEFAULT_MODEL,
          tools: [], # Expect empty array from JSON parse/default
          fallback_mode: :error, # Expect symbol from conversion
          mcp_servers_json: '[]',
          instruction: '',
          webhook_enabled: webhook_enabled.to_s,
          webhook_secret: webhook_secret || '',
          persistent_status: nil,
          agent_type: :llm # Default agent type
        },
        {
          name: :agent2, # Expect symbols
          description: 'Desc 2',
          model: ADK::Agent::DEFAULT_MODEL,
          tools: [],
          fallback_mode: :error,
          mcp_servers_json: '[]',
          instruction: '',
          webhook_enabled: webhook_enabled.to_s,
          webhook_secret: webhook_secret || '',
          persistent_status: nil,
          agent_type: :llm # Default agent type
        }
      ].sort_by { |h| h[:name] }
    end

    context 'when agents exist' do
      before do
        allow(mock_redis).to receive(:smembers).with(ADK::DefinitionStore::RedisStore::AGENTS_SET_KEY).and_return(agent_names)
        allow(mock_redis).to receive(:pipelined).and_yield(mock_redis).and_return([summary_values_1, summary_values_2])
        expect(mock_redis).to receive(:hmget).with(agent_key_1, *all_fields)
        expect(mock_redis).to receive(:hmget).with(agent_key_2, *all_fields)
      end

      it 'returns a sorted array of definition summaries' do
        expect(ADK.logger).to receive(:debug).with('Listed 2 agent definitions.')
        definitions = @store.list_definitions
        expect(definitions).to eq(expected_list)
        expect(definitions.map { |d| d[:name] }).to eq(%i[agent1 agent2]) # Verify sorting
      end
    end

    context 'when no agents are defined' do
      before do
        expect(mock_redis).to receive(:smembers).with(ADK::DefinitionStore::RedisStore::AGENTS_SET_KEY).and_return([])
        expect(mock_redis).not_to receive(:pipelined)
        # No hmget expectation
      end

      it 'returns an empty array' do
        expect(@store.list_definitions).to eq([])
      end
    end

    context 'handles inconsistencies where agent hash is missing and logs warning' do
      before do
        # Mock setup for inconsistency test
        agent_names_inc = %w[agent1 agent2] # Use different var name
        agent_key_1_inc = "#{ADK::DefinitionStore::RedisStore::AGENT_HASH_PREFIX}agent1"
        agent_key_2_inc = "#{ADK::DefinitionStore::RedisStore::AGENT_HASH_PREFIX}agent2"
        all_fields_inc = ADK::DefinitionStore::RedisStore::AGENT_DEFINITION_FIELDS
        # Agent 1 is missing (hmget returns nils)
        agent1_values = [nil] * all_fields_inc.count
        # Agent 2 exists
        agent2_values = all_fields_inc.map { |f| f == 'name' ? 'agent2' : "agent2_#{f}" }
        agent2_values[all_fields_inc.index('tools')] = '["tool_c"]'
        # Explicitly set agent_type to a valid value that will be converted to symbol
        agent2_values[all_fields_inc.index('agent_type')] = 'llm'

        expect(mock_redis).to receive(:smembers).with(ADK::DefinitionStore::RedisStore::AGENTS_SET_KEY).and_return(agent_names_inc)
        # Ensure pipelined returns an array containing the results for each agent
        allow(mock_redis).to receive(:pipelined).and_yield(mock_redis).and_return([agent1_values, agent2_values])
        # Expect hmget calls within the pipeline
        expect(mock_redis).to receive(:hmget).with(agent_key_1_inc, *all_fields_inc)
        expect(mock_redis).to receive(:hmget).with(agent_key_2_inc, *all_fields_inc)
      end

      it 'handles inconsistencies where agent hash is missing and logs warning' do
        # Expect warning log for agent1
        expect(ADK.logger).to receive(:warn).with("Inconsistency: Agent name 'agent1' found in set but hash key missing or empty.")
        expect(ADK.logger).to receive(:debug).with('Listed 1 agent definitions.') # Only agent 2 should be listed

        definitions = @store.list_definitions
        # Only agent 2 should be returned
        expect(definitions.count).to eq(1)
        expect(definitions.first[:name]).to eq(:agent2) # Expect symbol key
        expect(definitions.first[:description]).to eq('agent2_description')
        expect(definitions.first[:tools]).to eq([:tool_c]) # Expect symbolized tool names
        expect(definitions.first[:agent_type]).to eq(:llm) # Default agent type
      end
    end

    context 'on Redis error during smembers' do
      before do
        expect(mock_redis).to receive(:smembers).with(ADK::DefinitionStore::RedisStore::AGENTS_SET_KEY).and_raise(
          Redis::BaseError, 'Connection failed'
        )
        expect(mock_redis).not_to receive(:pipelined)
        # No hmget expectation
      end

      it 'raises StoreError' do
        expect { @store.list_definitions }.to raise_error(ADK::DefinitionStore::StoreError,
                                                          /Redis error listing agent definitions: Connection failed/)
      end
    end

    context 'on Redis error during pipelined hmget' do
      before do
        expect(mock_redis).to receive(:smembers).with(ADK::DefinitionStore::RedisStore::AGENTS_SET_KEY).and_return(['agent1'])
        expect(mock_redis).to receive(:pipelined).and_raise(Redis::BaseError, 'Pipeline failed')
        # No hmget expectation
      end

      it 'raises StoreError' do
        expect { @store.list_definitions }.to raise_error(ADK::DefinitionStore::StoreError,
                                                          /Redis error listing agent definitions: Pipeline failed/)
      end
    end

    context 'on unexpected errors' do
      let(:unexpected_error) { StandardError.new('List broke') }
      before do
        agent_names_mock = ['agent1']
        expect(mock_redis).to receive(:smembers).with(ADK::DefinitionStore::RedisStore::AGENTS_SET_KEY).and_return(agent_names_mock)
        # Simulate pipeline returning normally, but zip failing later
        expect(mock_redis).to receive(:pipelined).and_return([['value1']])
        # Stub zip on the specific array instance
        allow(agent_names_mock).to receive(:zip).and_raise(unexpected_error)
        # No hmget expectation
      end

      it 'raises StoreError' do
        expect { @store.list_definitions }.to raise_error(ADK::DefinitionStore::StoreError,
                                                          /Unexpected error listing agent definitions: List broke/)
      end
    end
  end

  describe '#definition_exists?' do
    it 'returns true if agent name exists in the set' do
      expect(mock_redis).to receive(:sismember).with(agents_set_key, agent_name).and_return(true)
      expect(ADK.logger).to receive(:debug).with("Checked existence for agent '#{agent_name}': true")
      expect(@store.definition_exists?(agent_name)).to be true
    end

    it 'returns false if agent name does not exist in the set' do
      expect(mock_redis).to receive(:sismember).with(agents_set_key, 'non_existent').and_return(false)
      expect(ADK.logger).to receive(:debug).with("Checked existence for agent 'non_existent': false")
      expect(@store.definition_exists?('non_existent')).to be false
    end

    it 'returns false if agent name is nil or empty without calling Redis' do
      expect(mock_redis).not_to receive(:sismember)
      expect(@store.definition_exists?(nil)).to be false
      expect(@store.definition_exists?('  ')).to be false
    end

    it 'raises StoreError on Redis error' do
      redis_error = Redis::CommandError.new('SISMEMBER failed')
      expect(mock_redis).to receive(:sismember).with(agents_set_key, agent_name).and_raise(redis_error)
      expect(ADK.logger).to receive(:error).with(/Redis error checking agent existence.*#{redis_error.class}.*#{redis_error.message}/)
      expect {
        @store.definition_exists?(agent_name)
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Redis error checking agent existence: #{redis_error.message}/)
    end

    it 'raises StoreError on unexpected errors' do
      unexpected_error = StandardError.new('Check broke')
      expect(mock_redis).to receive(:sismember).and_raise(unexpected_error)
      expect(ADK.logger).to receive(:error).with(/Unexpected error checking agent existence.*#{unexpected_error.class}.*#{unexpected_error.message}/m)
      expect {
        @store.definition_exists?(agent_name)
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Unexpected error checking agent existence: #{unexpected_error.message}/)
    end
  end

  describe '#check_connection' do
    it 'returns true if redis ping returns PONG' do
      expect(mock_redis).to receive(:ping).and_return('PONG')
      expect(@store.check_connection).to be true
    end

    it 'returns false if redis ping returns something other than PONG' do
      expect(mock_redis).to receive(:ping).and_return('Unexpected response')
      expect(@store.check_connection).to be false
    end

    it 'returns false and logs error if redis ping raises a Redis error' do
      redis_error = Redis::CannotConnectError.new('Connection failed')
      expect(mock_redis).to receive(:ping).and_raise(redis_error)
      expect(ADK.logger).to receive(:error).with("Redis connection check failed: #{redis_error.class} - #{redis_error.message}")
      expect(@store.check_connection).to be false
    end

    it 'returns false and logs error on unexpected errors' do
      unexpected_error = StandardError.new('Ping exploded')
      expect(mock_redis).to receive(:ping).and_raise(unexpected_error)
      expect(ADK.logger).to receive(:error).with(/Unexpected error during Redis connection check: #{unexpected_error.class}.*#{unexpected_error.message}/m)
      expect(@store.check_connection).to be false
    end
  end
end
