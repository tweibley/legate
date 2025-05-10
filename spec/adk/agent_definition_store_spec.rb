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
      tools: ['calculator', 'echo'],
      model: 'gemini-test'
    }
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
      expect(described_class.find(test_agent_name)).to eq(test_agent_def.merge(tools: ['calculator', 'echo'])) # Tools are stringified
    end

    it 'converts tool names to strings' do
      described_class.register(:sym_tools, { description: 'd', tools: [:echo, :calculator] })
      expect(described_class.find(:sym_tools)[:tools]).to eq(['echo', 'calculator'])
    end

    it 'handles non-array tools gracefully' do
      described_class.register(:str_tools, { description: 'd', tools: 'echo' })
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
      expect(described_class.find(test_agent_name)).to eq(test_agent_def)
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
      def2 = { description: 'Agent Two', tools: ['echo'], model: 'm2' }
      described_class.register(:agent1, test_agent_def)
      described_class.register(:agent2, def2)
      expect(described_class.all).to eq({ agent1: test_agent_def, agent2: def2.merge(tools: ['echo']) })
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
        'description' => test_agent_def[:description],
        'tools' => test_agent_def[:tools].to_json,
        'model' => test_agent_def[:model]
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
      redis_data = [test_agent_def[:description], test_agent_def[:tools].to_json, test_agent_def[:model]]
      expect(mock_redis).to receive(:hmget).with(redis_key, 'description', 'tools', 'model').and_return(redis_data)
      loaded_def = described_class.load_from_redis(test_agent_name)
      expect(loaded_def).to eq(test_agent_def)
    end

    it 'returns nil if agent not found in Redis' do
      expect(mock_redis).to receive(:hmget).with(redis_key, 'description', 'tools', 'model').and_return([nil, nil, nil])
      expect(described_class.load_from_redis(test_agent_name)).to be_nil
    end

    it 'handles missing model with default' do
      redis_data = [test_agent_def[:description], test_agent_def[:tools].to_json, nil] # Missing model
      expect(mock_redis).to receive(:hmget).with(redis_key, 'description', 'tools', 'model').and_return(redis_data)
      loaded_def = described_class.load_from_redis(test_agent_name)
      expect(loaded_def[:model]).to eq(ADK::Agent::DEFAULT_MODEL)
    end

    it 'handles invalid tools JSON gracefully' do
      redis_data = [test_agent_def[:description], '[invalid', test_agent_def[:model]]
      expect(mock_redis).to receive(:hmget).with(redis_key, 'description', 'tools', 'model').and_return(redis_data)
      expect(ADK.logger).to receive(:error).with(/Failed to parse tools JSON.*invalid/)
      loaded_def = described_class.load_from_redis(test_agent_name)
      expect(loaded_def[:tools]).to eq([]) # Should return empty array
      expect(loaded_def[:description]).to eq(test_agent_def[:description])
    end

    it 'returns nil and logs error on Redis connection failure' do
      expect(mock_redis).to receive(:hmget).and_raise(Redis::BaseError, 'Connection refused')
      expect(ADK.logger).to receive(:error).with(/Failed to load .* from Redis: Connection refused/)
      expect(described_class.load_from_redis(test_agent_name)).to be_nil
    end
  end

  describe '.load_all_from_redis' do
    let(:agent2_name) { :agent_two }
    let(:agent2_def) { { description: 'Agent Two', tools: ['echo'], model: 'm2' } }
    let(:agent_names) { [test_agent_name.to_s, agent2_name.to_s] }
    let(:redis_data1) { [test_agent_def[:description], test_agent_def[:tools].to_json, test_agent_def[:model]] }
    let(:redis_data2) { [agent2_def[:description], agent2_def[:tools].to_json, agent2_def[:model]] }

    before do
      allow(mock_redis).to receive(:smembers).with(redis_set_key).and_return(agent_names)
      # Mock pipelined hmget response correctly
      # It yields the pipeline object, then returns an array of results
      # corresponding to the commands queued within the block.
      allow(mock_redis).to receive(:pipelined).and_return([redis_data1, redis_data2])
    end

    it 'loads all definitions from Redis into memory' do
      loaded_count = described_class.load_all_from_redis
      expect(loaded_count).to eq(2)
      # Definitions are registered with stringified tool names
      expect(described_class.find(test_agent_name)).to eq(test_agent_def.merge(tools: ['calculator', 'echo']))
      expect(described_class.find(agent2_name)).to eq(agent2_def.merge(tools: ['echo']))
    end

    it 'clears existing definitions before loading' do
      described_class.register(:pre_existing, { description: 'old' })
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
