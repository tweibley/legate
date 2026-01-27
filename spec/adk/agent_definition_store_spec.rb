# File: spec/adk/agent_definition_store_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/agent_definition_store'
require 'redis'
require 'json'

RSpec.describe ADK::AgentDefinitionStore do
  let(:mock_redis) { instance_double(Redis) }
  let(:test_agent_name) { :test_agent_one }
  let(:test_agent_def) do
    {
      description: 'Test Agent One Desc',
      tools: %w[calculator echo],
      model: 'gemini-test',
      instruction: 'Initial instruction.',
      fallback_mode: :error, # Default fallback mode
      mcp_servers_json: '[{\"url\":\"http://localhost:8080\"}]',
      webhook_enabled: true,
      webhook_secret: 'secret123'
    }
  end
  let(:default_loaded_values) do # Expected values after loading if not explicitly set or if defaults apply
    {
      instruction: nil, # Or empty string depending on save logic for nil
      fallback_mode: :error,
      mcp_servers_json: '[]',
      webhook_enabled: false,
      webhook_secret: nil # Or empty string
    }
  end
  let(:test_agent_def_loaded) do # What test_agent_def looks like after being saved and loaded
    test_agent_def.merge( # .to_s conversion for some fields happens on save, then back to type on load
      tools: test_agent_def[:tools].map(&:to_s), # tools are stringified on save, parsed back
      fallback_mode: test_agent_def[:fallback_mode].to_sym, # Stored as string, loaded as symbol
      webhook_enabled: test_agent_def[:webhook_enabled] # Stored as 'true'/'false', loaded as boolean
    )
  end

  let(:test_agent_name_str) { test_agent_name.to_s }
  let(:redis_key) { described_class.agent_redis_key(test_agent_name_str) }
  let(:redis_set_key) { described_class::REDIS_AGENTS_SET_KEY }

  before do
    # Reset in-memory store before each test
    described_class.reset!
    # Mock Redis connection
    allow(Redis).to receive(:new).and_return(mock_redis)
    # Mock logger
    allow(ADK.logger).to receive(:debug)
    allow(ADK.logger).to receive(:info)
    allow(ADK.logger).to receive(:warn)
    allow(ADK.logger).to receive(:error)
    # Mock Redis commands used by the store
    allow(mock_redis).to receive(:multi).and_yield(mock_redis) # Simulate multi block
    allow(mock_redis).to receive(:pipelined).and_yield(mock_redis)
    allow(mock_redis).to receive(:hmset).and_return('OK')
    allow(mock_redis).to receive(:sadd).and_return(1)
    allow(mock_redis).to receive(:hmget).and_return([])
    allow(mock_redis).to receive(:smembers).and_return([])
    allow(mock_redis).to receive(:del).and_return(1)
    allow(mock_redis).to receive(:srem).and_return(1)
    allow(mock_redis).to receive(:close)
  end

  describe '.register' do
    it 'stores a valid definition in memory' do
      expect(described_class.register(test_agent_name, test_agent_def)).to be true
      # Register stringifies tools and potentially types other fields
      registered_def = described_class.find(test_agent_name)
      expect(registered_def[:description]).to eq(test_agent_def[:description])
      expect(registered_def[:tools]).to eq(test_agent_def[:tools].map(&:to_s))
      expect(registered_def[:model]).to eq(test_agent_def[:model])
      expect(registered_def[:instruction]).to eq(test_agent_def[:instruction])
      expect(registered_def[:fallback_mode]).to eq(test_agent_def[:fallback_mode].to_sym) # Stored as symbol
      expect(registered_def[:webhook_enabled]).to eq(test_agent_def[:webhook_enabled]) # Stored as boolean
    end

    it 'converts tool names to strings' do
      described_class.register(:sym_tools, { description: 'd', tools: %i[echo calculator], fallback_mode: :error, webhook_enabled: false })
      expect(described_class.find(:sym_tools)[:tools]).to eq(%w[echo calculator])
    end

    it 'handles non-array tools gracefully' do
      described_class.register(:str_tools, { description: 'd', tools: 'echo', fallback_mode: :error, webhook_enabled: false })
      expect(described_class.find(:str_tools)[:tools]).to eq(['echo'])
    end

    it 'returns false and warns for invalid definition hash' do
      expect(ADK.logger).to receive(:warn).with(/Invalid definition hash/)
      expect(described_class.register(:invalid, { tools: ['calc'] })).to be false
      expect(described_class.find(:invalid)).to be_nil
    end
  end

  describe '.find' do
    it 'returns a registered definition' do
      described_class.register(test_agent_name, test_agent_def)
      # Find returns the hash as it was registered (after initial processing by .register)
      found_def = described_class.find(test_agent_name)
      expect(found_def[:description]).to eq(test_agent_def[:description])
      expect(found_def[:tools]).to eq(test_agent_def[:tools].map(&:to_s)) # register stringifies tools
      expect(found_def[:model]).to eq(test_agent_def[:model])
      expect(found_def[:instruction]).to eq(test_agent_def[:instruction])
      expect(found_def[:fallback_mode]).to eq(test_agent_def[:fallback_mode].to_sym)
      expect(found_def[:webhook_enabled]).to eq(test_agent_def[:webhook_enabled])
    end

    it 'returns nil for an unregistered definition' do
      expect(described_class.find(:not_found)).to be_nil
    end
  end

  describe '.remove' do
    it 'removes a definition from the in-memory store' do
      described_class.register(test_agent_name, test_agent_def)
      expect(described_class.find(test_agent_name)).not_to be_nil
      described_class.remove(test_agent_name)
      expect(described_class.find(test_agent_name)).to be_nil
    end

    it 'does nothing if the definition does not exist' do
      expect { described_class.remove(:not_there) }.not_to change { described_class.all.count }
    end
  end

  describe '.all' do
    it 'returns a hash of all registered definitions' do
      def2 = { description: 'Agent Two', tools: ['echo'], model: 'm2', instruction: nil, fallback_mode: :warn, mcp_servers_json: '[]', webhook_enabled: true, webhook_secret: 's' }
      described_class.register(:agent1, test_agent_def)
      described_class.register(:agent2, def2)

      all_defs = described_class.all
      expect(all_defs.keys).to contain_exactly(:agent1, :agent2)
      expect(all_defs[:agent1][:tools]).to eq(test_agent_def[:tools].map(&:to_s))
      expect(all_defs[:agent2][:tools]).to eq(def2[:tools].map(&:to_s))
      expect(all_defs[:agent2][:fallback_mode]).to eq(def2[:fallback_mode].to_sym)
      expect(all_defs[:agent1][:description]).to eq(test_agent_def[:description])
      expect(all_defs[:agent2][:webhook_enabled]).to eq(def2[:webhook_enabled])
    end

    it 'returns an empty hash when no definitions are registered' do
      expect(described_class.all).to eq({})
    end

    it 'returns a copy, not the original hash' do
      described_class.register(:agent1, test_agent_def)
      all_defs = described_class.all
      all_defs.delete(:agent1)
      expect(described_class.find(:agent1)).not_to be_nil # Original should be unchanged
    end
  end

  describe '.reset!' do
    it 'clears the in-memory store' do
      described_class.register(test_agent_name, test_agent_def)
      expect(described_class.all).not_to be_empty
      described_class.reset!
      expect(described_class.all).to be_empty
    end
  end

  describe '.save_to_redis' do
    let(:expected_redis_data) do
      {
        'description' => test_agent_def[:description].to_s,
        'tools' => test_agent_def[:tools].to_json,
        'model' => test_agent_def[:model].to_s,
        'instruction' => test_agent_def[:instruction].to_s,
        'fallback_mode' => test_agent_def[:fallback_mode].to_s,
        'mcp_servers_json' => test_agent_def[:mcp_servers_json].to_s,
        'webhook_enabled' => test_agent_def[:webhook_enabled].to_s,
        'webhook_secret' => test_agent_def[:webhook_secret].to_s
      }
    end

    it 'saves the definition hash and agent name to Redis' do
      expect(mock_redis).to receive(:hmset).with(redis_key, expected_redis_data).and_return('OK')
      expect(mock_redis).to receive(:sadd).with(redis_set_key, test_agent_name_str).and_return(1)
      expect(described_class.save_to_redis(test_agent_name, test_agent_def)).to be true
    end

    it 'returns false and logs error on Redis failure' do
      expect(mock_redis).to receive(:hmset).and_raise(Redis::BaseError, 'Connection failed')
      expect(ADK.logger).to receive(:error).with(/Failed to save .* to Redis: Connection failed/)
      expect(described_class.save_to_redis(test_agent_name, test_agent_def)).to be false
    end
  end

  describe '.load_from_redis' do
    it 'loads and parses a definition from Redis' do
      redis_data = [
        test_agent_def[:description].to_s,
        test_agent_def[:tools].to_json,
        test_agent_def[:model].to_s,
        test_agent_def[:instruction].to_s,
        test_agent_def[:fallback_mode].to_s,
        test_agent_def[:mcp_servers_json].to_s,
        test_agent_def[:webhook_enabled].to_s,
        test_agent_def[:webhook_secret].to_s
      ]
      fields_to_load = %w[description tools model instruction fallback_mode mcp_servers_json webhook_enabled webhook_secret]
      expect(mock_redis).to receive(:hmget).with(redis_key, *fields_to_load).and_return(redis_data)
      loaded_def = described_class.load_from_redis(test_agent_name)
      expect(loaded_def).to eq(test_agent_def_loaded)
    end

    it 'returns nil if agent not found in Redis' do
      fields_to_load = %w[description tools model instruction fallback_mode mcp_servers_json webhook_enabled webhook_secret]
      # Simulate not found: description (index 0) is nil
      not_found_data = [nil] + Array.new(fields_to_load.length - 1)
      expect(mock_redis).to receive(:hmget).with(redis_key, *fields_to_load).and_return(not_found_data)
      expect(described_class.load_from_redis(test_agent_name)).to be_nil
    end

    it 'handles missing model with default' do
      fields_to_load = %w[description tools model instruction fallback_mode mcp_servers_json webhook_enabled webhook_secret]
      redis_data_missing_model = [
        test_agent_def[:description].to_s,
        test_agent_def[:tools].to_json,
        nil, # Model is nil
        default_loaded_values[:instruction].to_s,
        default_loaded_values[:fallback_mode].to_s,
        default_loaded_values[:mcp_servers_json].to_s,
        default_loaded_values[:webhook_enabled].to_s,
        default_loaded_values[:webhook_secret].to_s
      ]
      expect(mock_redis).to receive(:hmget).with(redis_key, *fields_to_load).and_return(redis_data_missing_model)
      loaded_def = described_class.load_from_redis(test_agent_name)
      expect(loaded_def[:model]).to eq(ADK::Agent::DEFAULT_MODEL)
      expect(loaded_def[:description]).to eq(test_agent_def[:description])
      expect(loaded_def[:tools]).to eq(test_agent_def[:tools]) # Assuming tools are present
      expect(loaded_def[:fallback_mode]).to eq(default_loaded_values[:fallback_mode])
    end

    it 'handles invalid tools JSON gracefully' do
      fields_to_load = %w[description tools model instruction fallback_mode mcp_servers_json webhook_enabled webhook_secret]
      redis_data_invalid_tools = [
        test_agent_def[:description].to_s,
        '[invalid JSON', # Invalid tools JSON
        test_agent_def[:model].to_s,
        default_loaded_values[:instruction].to_s,
        default_loaded_values[:fallback_mode].to_s,
        default_loaded_values[:mcp_servers_json].to_s,
        default_loaded_values[:webhook_enabled].to_s,
        default_loaded_values[:webhook_secret].to_s
      ]
      expect(mock_redis).to receive(:hmget).with(redis_key, *fields_to_load).and_return(redis_data_invalid_tools)
      expect(ADK.logger).to receive(:error).with(/Failed to parse tools JSON.*invalid/)
      loaded_def = described_class.load_from_redis(test_agent_name)
      expect(loaded_def[:tools]).to eq([]) # Should return empty array
      expect(loaded_def[:description]).to eq(test_agent_def[:description])
      expect(loaded_def[:model]).to eq(test_agent_def[:model])
      expect(loaded_def[:fallback_mode]).to eq(default_loaded_values[:fallback_mode])
    end

    it 'returns nil and logs error on Redis connection failure' do
      expect(mock_redis).to receive(:hmget).and_raise(Redis::BaseError, 'Connection refused')
      expect(ADK.logger).to receive(:error).with(/Failed to load .* from Redis: Connection refused/)
      expect(described_class.load_from_redis(test_agent_name)).to be_nil
    end
  end

  describe '.load_all_from_redis' do
    let(:agent2_name) { :agent_two }
    let(:agent2_def) { { description: 'Agent Two', tools: ['echo'], model: 'm2', instruction: 'Agent two instruction', fallback_mode: :continue, mcp_servers_json: '[]', webhook_enabled: false, webhook_secret: nil } }
    let(:agent_names) { [test_agent_name.to_s, agent2_name.to_s] }
    let(:redis_data1) do
      [
        test_agent_def[:description].to_s, test_agent_def[:tools].to_json, test_agent_def[:model].to_s,
        test_agent_def[:instruction].to_s, test_agent_def[:fallback_mode].to_s,
        test_agent_def[:mcp_servers_json].to_s, test_agent_def[:webhook_enabled].to_s,
        test_agent_def[:webhook_secret].to_s
      ]
    end
    let(:redis_data2) do
      [
        agent2_def[:description].to_s, agent2_def[:tools].to_json, agent2_def[:model].to_s,
        agent2_def[:instruction].to_s, agent2_def[:fallback_mode].to_s,
        agent2_def[:mcp_servers_json].to_s, agent2_def[:webhook_enabled].to_s,
        agent2_def[:webhook_secret].to_s
      ]
    end
    let(:fields_to_load_all) { %w[description tools model instruction fallback_mode mcp_servers_json webhook_enabled webhook_secret] }

    before do
      allow(mock_redis).to receive(:smembers).with(redis_set_key).and_return(agent_names)
      # Ensure pipelined is called with the correct number of hmget calls
      # and that each hmget asks for all fields.
      # The return value of the pipelined block should be an array of arrays,
      # where each inner array is the result of one hmget.
      allow(mock_redis).to receive(:pipelined) do |&block|
        # Create a spy for the pipeline object if needed, or just ensure hmget is called correctly
        # For simplicity, directly return the expected structure.
        # This mock assumes the block calls hmget twice.
        # In a real scenario, you might use a spy to verify calls on the yielded pipeline object.
        # For now, just returning the data directly as the test expects it.
        # The block passed to `pipelined` in the SUT will queue commands.
        # The `and_return` for `pipelined` should be the result of *executing* those commands.
        [redis_data1, redis_data2] # This is what the SUT's `redis.pipelined do ... end` returns
      end
      # Explicitly mock each hmget call if the above isn't specific enough for what pipelined does.
      # However, the `allow(mock_redis).to receive(:pipelined).and_return(...)` is usually sufficient
      # if the SUT correctly uses the pipeline object passed to its block.
    end

    it 'loads all definitions from Redis into memory' do
      loaded_count = described_class.load_all_from_redis
      expect(loaded_count).to eq(2)
      # Definitions are registered with stringified tool names

      loaded_agent1 = described_class.find(test_agent_name)
      expect(loaded_agent1[:description]).to eq(test_agent_def[:description])
      expect(loaded_agent1[:tools]).to eq(test_agent_def[:tools].map(&:to_s))
      expect(loaded_agent1[:model]).to eq(test_agent_def[:model])
      expect(loaded_agent1[:instruction]).to eq(test_agent_def[:instruction])
      expect(loaded_agent1[:fallback_mode]).to eq(test_agent_def[:fallback_mode].to_sym)
      expect(loaded_agent1[:mcp_servers_json]).to eq(test_agent_def[:mcp_servers_json])
      expect(loaded_agent1[:webhook_enabled]).to eq(test_agent_def[:webhook_enabled])
      expect(loaded_agent1[:webhook_secret]).to eq(test_agent_def[:webhook_secret])

      loaded_agent2 = described_class.find(agent2_name)
      expect(loaded_agent2[:description]).to eq(agent2_def[:description])
      expect(loaded_agent2[:tools]).to eq(agent2_def[:tools].map(&:to_s))
      expect(loaded_agent2[:model]).to eq(agent2_def[:model])
      expect(loaded_agent2[:instruction]).to eq(agent2_def[:instruction])
      expect(loaded_agent2[:fallback_mode]).to eq(agent2_def[:fallback_mode].to_sym)
      expect(loaded_agent2[:webhook_enabled]).to eq(agent2_def[:webhook_enabled])
    end

    it 'clears existing definitions before loading' do
      described_class.register(:pre_existing, { description: 'old', fallback_mode: :error, webhook_enabled: false })
      described_class.load_all_from_redis
      expect(described_class.find(:pre_existing)).to be_nil
    end

    it 'handles errors during loading gracefully' do
      allow(mock_redis).to receive(:smembers).and_raise(Redis::BaseError, 'SMEMBERS failed')
      expect(ADK.logger).to receive(:error).with(/Failed to load all definitions from Redis: SMEMBERS failed/)
      expect(described_class.load_all_from_redis).to eq(0)
      expect(described_class.all).to be_empty
    end
  end

  describe '.all_names' do
    it 'returns a list of all agent names from Redis' do
      expect(mock_redis).to receive(:smembers).with(redis_set_key).and_return([test_agent_name_str])
      expect(described_class.all_names).to eq([test_agent_name_str])
    end

    it 'returns an empty array and logs error on Redis failure' do
      expect(mock_redis).to receive(:smembers).and_raise(Redis::BaseError, 'Connection failed')
      expect(ADK.logger).to receive(:error).with(/Failed to get all agent names: Connection failed/)
      expect(described_class.all_names).to eq([])
    end
  end

  describe '.delete_from_redis' do
    it 'removes the definition hash and set member from Redis' do
      expect(mock_redis).to receive(:del).with(redis_key).and_return(1)
      expect(mock_redis).to receive(:srem).with(redis_set_key, test_agent_name_str).and_return(1)
      expect(described_class.delete_from_redis(test_agent_name)).to be true
    end

    it 'returns false and logs error on Redis failure' do
      expect(mock_redis).to receive(:del).and_raise(Redis::BaseError, 'Connection failed')
      expect(ADK.logger).to receive(:error).with(/Failed to delete .* from Redis: Connection failed/)
      expect(described_class.delete_from_redis(test_agent_name)).to be false
    end
  end
end
