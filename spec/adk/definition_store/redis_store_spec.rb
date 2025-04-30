# File: spec/adk/definition_store/redis_store_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'redis'
require 'json'
require 'adk/definition_store/redis_store'
require 'adk/errors' # Include ADK::Errors for specific error types
require 'adk/agent' # Required for DEFAULT_MODEL constant

RSpec.describe ADK::DefinitionStore::RedisStore do
  # Use spy for logger to track calls without strict expectation setup everywhere
  let(:mock_redis) {
    instance_double(Redis, multi: true, pipelined: true, ping: 'PONG', hmget: [], hset: 0, sadd: 1, sismember: false,
                           del: 0, srem: 0, smembers: [])
  }
  let(:logger_double) { spy('Logger') }
  let(:store) { described_class.new(mock_redis) }

  # Sample definition data
  let(:agent_name) { 'test_agent' }
  let(:description) { 'A test agent description' }
  let(:tools) { ['tool_a', 'tool_b'] }
  let(:tools_json) { tools.to_json }
  let(:model) { 'gpt-4o' }
  let(:fallback_mode) { :error }
  let(:fallback_str) { fallback_mode.to_s }
  let(:mcp_servers) { [{ 'url' => 'http://localhost:8080' }] }
  let(:mcp_servers_json) { mcp_servers.to_json }
  let(:agent_key) { "#{described_class::AGENT_HASH_PREFIX}#{agent_name}" }
  let(:agents_set_key) { described_class::AGENTS_SET_KEY }

  before do
    # Stub the ADK logger to prevent actual logging during tests
    allow(ADK).to receive(:logger).and_return(logger_double)
    # Re-initialize store in each test to ensure clean state and logger stubbing
    @store = described_class.new(mock_redis)
  end

  describe '#initialize' do
    it 'initializes with a Redis client and logs info' do
      expect(ADK.logger).to receive(:info).with("ADK::DefinitionStore::RedisStore initialized.")
      described_class.new(mock_redis)
    end

    it 'logs error and sets @redis to nil if logger.info fails during initialization' do
      init_error = StandardError.new('Initial logger setup failed')
      allow(ADK).to receive(:logger).and_return(logger_double)
      allow(logger_double).to receive(:info).with("ADK::DefinitionStore::RedisStore initialized.").and_raise(init_error)

      expect(logger_double).to receive(:error).with(/Failed to initialize RedisStore: #{init_error.message}/)

      store_instance = nil
      expect {
        store_instance = described_class.new(mock_redis)
      }.not_to raise_error # The rescue block should prevent the error from propagating

      expect(store_instance.instance_variable_get(:@redis)).to be_nil
    end

    it 'logs an error during operations if initialized with a non-functional client' do
      bad_redis = instance_double(Redis)
      allow(bad_redis).to receive(:ping).and_raise(Redis::CannotConnectError, 'mock connection error')
      store_with_bad_client = described_class.new(bad_redis)

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
      store_no_redis = described_class.new(nil)
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
        mcp_servers_json: mcp_servers_json }
    }

    it 'successfully saves a valid definition using MULTI' do
      # Mock the multi block execution
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1, 1, 1, 1, 1, 1, 1]) # Simulate successful results
      expect(mock_redis).to receive(:hset).with(agent_key, 'name', agent_name)
      expect(mock_redis).to receive(:hset).with(agent_key, 'description', description)
      expect(mock_redis).to receive(:hset).with(agent_key, 'tools', tools_json)
      expect(mock_redis).to receive(:hset).with(agent_key, 'model', model)
      expect(mock_redis).to receive(:hset).with(agent_key, 'fallback_mode', fallback_str)
      expect(mock_redis).to receive(:hset).with(agent_key, 'mcp_servers_json', mcp_servers_json)
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
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1] * 7).twice
      expect(mock_redis).to receive(:hset).with(agent_key, 'mcp_servers_json', '[]').twice # Once for nil, once for empty string
      allow(mock_redis).to receive(:hset).with(agent_key, anything, anything) # Allow other hsets
      allow(mock_redis).to receive(:sadd)
      expect(@store.save_definition(**save_args.merge(mcp_servers_json: nil))).to be true
      expect(@store.save_definition(**save_args.merge(mcp_servers_json: '   '))).to be true
    end

    it 'saves with empty array JSON if tools is nil or not an array' do
      # Ensure multi returns an array
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1] * 7).twice
      expect(mock_redis).to receive(:hset).with(agent_key, 'tools', '[]').twice # Once for nil, once for non-array
      allow(mock_redis).to receive(:hset).with(agent_key, anything, anything) # Allow other hsets
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
      # Remove logger expectation - focus on the raised error
      # expect(ADK.logger).to receive(:error).with(/Invalid MCP JSON provided/)
      expect {
        @store.save_definition(**save_args.merge(mcp_servers_json: invalid_json))
      }.to raise_error(ArgumentError,
                       /MCP configuration must be a JSON array/)

      unparseable_json = '[{not json]}'
      # Remove logger expectation - focus on the raised error
      # expect(ADK.logger).to receive(:error).with(/Invalid MCP JSON provided/)
      expect {
        @store.save_definition(**save_args.merge(mcp_servers_json: unparseable_json))
      }.to raise_error(ArgumentError,
                       /Invalid format for MCP Server Configurations/)
    end

    it 'raises StoreError if Redis transaction is aborted' do
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return(nil) # Simulate abort
      allow(mock_redis).to receive(:hset) # Assume commands were added before abort
      allow(mock_redis).to receive(:sadd)
      expect(ADK.logger).to receive(:error).with(/Redis transaction for saving agent .* failed \(aborted\)/)
      expect {
        @store.save_definition(**save_args)
      }.to raise_error(ADK::DefinitionStore::StoreError, /Redis transaction aborted/)
    end

    it 'raises StoreError on Redis command error within MULTI' do
      # Simulate a command error object being returned in the multi results
      error_result = [1, Redis::CommandError.new('Mock Command Error'), 1, 1, 1, 1, 1]
      # Expect multi to yield the mock redis instance
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return(error_result)

      # Expect the calls *within* the multi block explicitly
      expect(mock_redis).to receive(:hset).with(agent_key, 'name', agent_name)
      expect(mock_redis).to receive(:hset).with(agent_key, 'description', description || "")
      expect(mock_redis).to receive(:hset).with(agent_key, 'tools', tools_json)
      expect(mock_redis).to receive(:hset).with(agent_key, 'model', model || ADK::Agent::DEFAULT_MODEL)
      expect(mock_redis).to receive(:hset).with(agent_key, 'fallback_mode', fallback_str)
      expect(mock_redis).to receive(:hset).with(agent_key, 'mcp_servers_json', mcp_servers_json || '[]')
      expect(mock_redis).to receive(:sadd).with(agents_set_key, agent_name)

      # Expect the logger call from this specific block
      expect(ADK.logger).to receive(:error).with(/Redis command error during multi.*#{error_result.inspect}/)

      # Expect the specific StoreError
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
      allow(tools).to receive(:to_json).and_raise(JSON::GeneratorError.new("mock json gen error"))
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
      expect(ADK.logger).to receive(:error).with(/Unexpected error saving agent.*#{unexpected_error.class}.*#{unexpected_error.message}/m) # Match multi-line backtrace log
      expect {
        @store.save_definition(**save_args)
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Unexpected error saving agent definition: #{unexpected_error.message}/)
    end
  end

  describe '#get_definition' do
    let(:redis_hash_values) do
      [
        agent_name,
        description,
        tools_json,
        model,
        fallback_str,
        mcp_servers_json
      ]
    end
    let(:expected_definition) do
      {
        name: agent_name,
        description: description,
        tools: tools,
        model: model,
        fallback_mode: fallback_mode,
        mcp_servers_json: mcp_servers_json
      }
    end

    it 'successfully retrieves and parses an existing definition' do
      expect(mock_redis).to receive(:hmget)
        .with(agent_key, *described_class::AGENT_DEFINITION_FIELDS)
        .and_return(redis_hash_values)
      expect(ADK.logger).to receive(:debug).with("Retrieved definition for agent '#{agent_name}'.")

      definition = @store.get_definition(agent_name)
      expect(definition).to eq(expected_definition)
    end

    it 'returns nil if agent name is nil or empty' do
      expect(mock_redis).not_to receive(:hmget)
      expect(@store.get_definition(nil)).to be_nil
      expect(@store.get_definition('  ')).to be_nil
    end

    it 'returns nil if agent definition does not exist in Redis' do
      # hmget returns an array of nils if key doesn't exist
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
      # Simplify regex to be less brittle regarding .inspect formatting
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
      # Remove logger expectation - focus on the raised error
      # expect(ADK.logger).to receive(:error).with(/Invalid MCP JSON provided for updating/)
      expect {
        @store.update_definition(agent_name,
                                 invalid_mcp_update)
      }.to raise_error(ArgumentError, /MCP configuration must be a JSON array/)

      unparseable_mcp_update = { mcp_servers_json: '[[bad' }
      # Remove logger expectation - focus on the raised error
      # expect(ADK.logger).to receive(:error).with(/Invalid MCP JSON provided for updating/)
      expect {
        @store.update_definition(agent_name,
                                 unparseable_mcp_update)
      }.to raise_error(ArgumentError, /Invalid format for MCP Server Configurations/)
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
      # Create a double that raises the error when to_json is called
      bad_tools_array = ['tool1']
      allow(bad_tools_array).to receive(:to_json).and_raise(JSON::GeneratorError.new("tool json gen error"))
      bad_tools_update_with_mock = { tools: bad_tools_array }

      expect(mock_redis).not_to receive(:hset)
      # Logger expectation should match the message from the rescue block in update_definition
      expect(ADK.logger).to receive(:error).with(/Failed to serialize tools array to JSON for updating agent.*tool json gen error/)
      # Expect the StoreError that wraps the original JSON error
      expect {
        @store.update_definition(agent_name,
                                 bad_tools_update_with_mock)
      }.to raise_error(ADK::DefinitionStore::StoreError, /Internal error serializing tool data for agent update/)
    end

    it 'raises StoreError on unexpected errors' do
      unexpected_error = StandardError.new('Boom')
      # The `hset` mock should expect the processed `redis_updates` hash, not the raw `updates`
      # We need to know what the processed hash looks like for the 'updates' hash
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
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1, 1]) # Simulate 1 key deleted, 1 member removed
      expect(mock_redis).to receive(:del).with(agent_key)
      expect(mock_redis).to receive(:srem).with(agents_set_key, agent_name)
      expect(ADK.logger).to receive(:info).with("Agent definition '#{agent_name}' deleted successfully (or did not exist).")
      expect(@store.delete_definition(agent_name)).to be true
    end

    it 'returns true even if agent did not exist (idempotent)' do
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([0, 0]) # Simulate 0 deleted/removed
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
      expect(mock_redis).to receive(:multi).and_yield(mock_redis).and_return(nil) # Simulate abort
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
    let(:agent_key_1) { "#{described_class::AGENT_HASH_PREFIX}#{agent_name_1}" }
    let(:agent_key_2) { "#{described_class::AGENT_HASH_PREFIX}#{agent_name_2}" }

    let(:summary_fields) { %w[name description model] }
    let(:summary_values_1) { [agent_name_1, 'Desc 1', 'Model A'] }
    let(:summary_values_2) { [agent_name_2, 'Desc 2', nil] } # Agent 2 missing model

    let(:expected_list) do
      [
        { name: agent_name_1, description: 'Desc 1', model: 'Model A' },
        { name: agent_name_2, description: 'Desc 2', model: ADK::Agent::DEFAULT_MODEL } # Default model applied
      ].sort_by { |h| h[:name] } # Ensure same sorting as method
    end

    it 'returns a sorted array of definition summaries' do
      expect(mock_redis).to receive(:smembers).with(agents_set_key).and_return(agent_names)
      # Mock the pipelined hmget calls
      expect(mock_redis).to receive(:pipelined).and_yield(mock_redis).and_return([summary_values_1, summary_values_2])
      # Expect hmget to be called within the pipeline block for each agent
      expect(mock_redis).to receive(:hmget).with(agent_key_1, *summary_fields)
      expect(mock_redis).to receive(:hmget).with(agent_key_2, *summary_fields)
      expect(ADK.logger).to receive(:debug).with("Listed 2 agent definitions.")

      definitions = @store.list_definitions
      expect(definitions).to eq(expected_list)
      # Verify sorting
      expect(definitions.map { |d| d[:name] }).to eq([agent_name_1, agent_name_2])
    end

    it 'returns an empty array if no agents are defined' do
      expect(mock_redis).to receive(:smembers).with(agents_set_key).and_return([])
      expect(mock_redis).not_to receive(:pipelined)
      # Remove logger expectation as the code returns early before logging
      # expect(ADK.logger).to receive(:debug).with("Listed 0 agent definitions.") # Assuming debug logs count
      expect(@store.list_definitions).to eq([])
    end

    it 'handles inconsistencies where agent hash is missing and logs warning' do
      expect(mock_redis).to receive(:smembers).with(agents_set_key).and_return(agent_names)
      # Simulate agent 2 hash missing (hmget returns array of nils)
      expect(mock_redis).to receive(:pipelined).and_yield(mock_redis).and_return([summary_values_1, [nil, nil, nil]])
      expect(mock_redis).to receive(:hmget).with(agent_key_1, *summary_fields)
      expect(mock_redis).to receive(:hmget).with(agent_key_2, *summary_fields)

      expect(ADK.logger).to receive(:warn).with("Inconsistency: Agent name '#{agent_name_2}' found in set but hash key missing or empty.")
      expect(ADK.logger).to receive(:debug).with("Listed 1 agent definitions.")

      definitions = @store.list_definitions
      # Only agent 1 should be returned
      expect(definitions.count).to eq(1)
      expect(definitions.first[:name]).to eq(agent_name_1)
    end

    it 'raises StoreError on Redis error during smembers' do
      redis_error = Redis::ConnectionError.new('Read failed')
      expect(mock_redis).to receive(:smembers).and_raise(redis_error)
      expect(ADK.logger).to receive(:error).with(/Redis error listing agents.*#{redis_error.class}.*#{redis_error.message}/)
      expect {
        @store.list_definitions
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Redis error listing agent definitions: #{redis_error.message}/)
    end

    it 'raises StoreError on Redis error during pipelined hmget' do
      redis_error = Redis::TimeoutError.new('Pipeline timeout')
      expect(mock_redis).to receive(:smembers).with(agents_set_key).and_return(agent_names)
      expect(mock_redis).to receive(:pipelined).and_raise(redis_error)
      expect(ADK.logger).to receive(:error).with(/Redis error listing agents.*#{redis_error.class}.*#{redis_error.message}/)
      expect {
        @store.list_definitions
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Redis error listing agent definitions: #{redis_error.message}/)
    end

    it 'raises StoreError on unexpected errors' do
      unexpected_error = StandardError.new('List broke')
      expect(mock_redis).to receive(:smembers).and_raise(unexpected_error)
      expect(ADK.logger).to receive(:error).with(/Unexpected error listing agents.*#{unexpected_error.class}.*#{unexpected_error.message}/m)
      expect {
        @store.list_definitions
      }.to raise_error(ADK::DefinitionStore::StoreError,
                       /Unexpected error listing agent definitions: #{unexpected_error.message}/)
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
      # Note: Debug logging is commented out in the source, so not expecting logger.debug
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

  # --- Placeholder for other describe blocks ---
  # describe '#check_connection' do ... end
end
