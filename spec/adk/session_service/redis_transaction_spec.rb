# frozen_string_literal: true

require 'spec_helper'
require 'redis'
require_relative '../../../lib/adk/session_service/redis'

RSpec.describe ADK::SessionService::Redis, 'Transaction Tests' do
  # Mock Redis client
  let(:mock_redis) { instance_double(Redis) }
  let(:session_ttl) { 3600 } # 1 hour for testing

  # Test data
  let(:app_name) { 'test_app' }
  let(:user_id) { 'user123' }
  let(:session_id) { SecureRandom.uuid }
  let(:initial_state) { { key: 'value' } }
  let(:initial_state_json) { JSON.generate(initial_state) }
  let(:state_delta) { { delta_key: 'delta_value' } }
  let(:event_with_delta) { ADK::Event.new(role: :agent, content: 'response', state_delta: state_delta) }
  let(:now) { Time.parse('2024-01-01T10:00:00Z') }

  # Redis keys
  let(:session_key) { service.send(:redis_session_key, session_id) }
  let(:events_key) { service.send(:redis_events_key, session_id) }

  # Service instance
  subject(:service) { described_class.new(redis_client: mock_redis, session_ttl: session_ttl) }

  # Session double
  let(:session) do
    instance_double(ADK::Session,
                    id: session_id,
                    app_name: app_name,
                    user_id: user_id,
                    state_to_h: initial_state,
                    updated_at: now,
                    add_event: event_with_delta,
                    update_state: nil)
  end

  before do
    allow(Time).to receive(:now).and_return(now)

    # Default Redis mock behavior
    allow(mock_redis).to receive(:exists?).with(session_key).and_return(true)
    allow(mock_redis).to receive(:watch).with(session_key).and_yield
    allow(mock_redis).to receive(:unwatch)
    allow(mock_redis).to receive(:hget).with(session_key, 'state').and_return(initial_state_json)

    # Fix the JSON parse expectations for all possible values
    allow(JSON).to receive(:generate).and_return('{}')
    allow(JSON).to receive(:generate).with(event_with_delta.to_h).and_return('{"event_json":"data"}')
    allow(JSON).to receive(:generate).with(initial_state).and_return(initial_state_json)
    allow(JSON).to receive(:parse).with(anything, symbolize_names: true).and_return({})
    allow(JSON).to receive(:parse).with(initial_state_json, symbolize_names: true).and_return(initial_state)

    allow(service).to receive(:get_session).and_return(session)
  end

  describe 'optimistic locking with WATCH/MULTI/EXEC' do
    context 'transaction succeeds on first attempt' do
      before do
        allow(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1, 1, 1, 1])
        allow(mock_redis).to receive(:rpush).with(events_key, anything).and_return(1)
        allow(mock_redis).to receive(:hset).with(session_key, anything, anything).and_return(1)
        allow(mock_redis).to receive(:expire).with(any_args).and_return(true)
      end

      it 'executes all Redis commands in the transaction' do
        expect(mock_redis).to receive(:watch).with(session_key).once
        expect(mock_redis).to receive(:multi).once
        expect(mock_redis).to receive(:rpush).with(events_key, anything).once
        expect(mock_redis).to receive(:hset).with(session_key, 'updated_at', anything).once
        expect(mock_redis).to receive(:hset).with(session_key, 'state', anything).once

        expect(service.append_event(session_id: session_id, event: event_with_delta)).to be true
      end
    end

    context 'with WATCH conflict' do
      before do
        # Setup all the commands that will be called inside multi block
        allow(mock_redis).to receive(:rpush).with(events_key, anything).and_return(1)
        allow(mock_redis).to receive(:hset).with(session_key, 'updated_at', anything).and_return(1)
        allow(mock_redis).to receive(:hset).with(session_key, 'state', anything).and_return(1)
        allow(mock_redis).to receive(:expire).with(any_args).and_return(true)
      end

      it 'retries transaction and succeeds on third attempt' do
        # Setup multi to fail twice, then succeed
        call_count = 0

        allow(mock_redis).to receive(:multi) do |&block|
          call_count += 1
          block.call(mock_redis) if block

          if call_count < 3
            nil # Return nil to simulate watch failure
          else
            [1, 1, 1, 1] # Succeed on third attempt
          end
        end

        expect(mock_redis).to receive(:watch).with(session_key).exactly(3).times

        expect(service.append_event(session_id: session_id, event: event_with_delta)).to be true
        expect(call_count).to eq(3)
      end

      it 'fails after max retries' do
        # Always return nil from multi to simulate persistent watch failures
        allow(mock_redis).to receive(:multi) do |&block|
          block.call(mock_redis) if block
          nil
        end

        allow(ADK.logger).to receive(:warn)
        expect(mock_redis).to receive(:watch).with(session_key).exactly(3).times
        expect(ADK.logger).to receive(:warn).with(/Max retries .* exceeded/)

        expect(service.append_event(session_id: session_id, event: event_with_delta)).to be false
      end
    end

    context 'with state_delta handling' do
      let(:merged_state) { initial_state.merge(state_delta) }
      let(:session_with_delta) do
        instance_double(ADK::Session,
                        id: session_id,
                        app_name: app_name,
                        user_id: user_id,
                        state_to_h: merged_state,
                        updated_at: now,
                        add_event: event_with_delta)
      end

      before do
        allow(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1, 1, 1, 1])
        allow(mock_redis).to receive(:rpush).and_return(1)
        allow(mock_redis).to receive(:hset).and_return(1)
        allow(mock_redis).to receive(:expire).and_return(true)
        allow(service).to receive(:get_session).and_return(session_with_delta)
        allow(session_with_delta).to receive(:update_state)
      end

      it 'properly merges state_delta during the WATCH block' do
        expect(session_with_delta).to receive(:update_state).with(merged_state)
        expect(mock_redis).to receive(:hset).with(session_key, 'state', anything).once

        service.append_event(session_id: session_id, event: event_with_delta)
      end

      it 'handles errors parsing current state' do
        allow(mock_redis).to receive(:hget).with(session_key, 'state').and_return('invalid json')
        allow(JSON).to receive(:parse).with('invalid json',
                                            symbolize_names: true).and_raise(JSON::ParserError.new('Invalid JSON'))
        allow(ADK.logger).to receive(:error)

        expect(ADK.logger).to receive(:error).with(/Failed to parse current state JSON/)
        expect(service.append_event(session_id: session_id, event: event_with_delta)).to be false
      end
    end
  end

  describe 'transaction error handling' do
    context 'with Redis errors' do
      it 'handles Redis::BaseError during transaction' do
        allow(mock_redis).to receive(:multi).and_raise(Redis::ConnectionError.new('Connection lost'))
        allow(ADK.logger).to receive(:error)
        allow(mock_redis).to receive(:unwatch)

        expect(ADK.logger).to receive(:error).with(/Redis error appending event/)
        expect(mock_redis).to receive(:unwatch)

        expect(service.append_event(session_id: session_id, event: event_with_delta)).to be false
      end

      it 'handles errors during WATCH' do
        allow(mock_redis).to receive(:watch).and_raise(Redis::CommandError.new('ERR WATCH inside MULTI'))
        allow(ADK.logger).to receive(:error)

        expect(ADK.logger).to receive(:error).with(/Redis error appending event/)
        expect(service.append_event(session_id: session_id, event: event_with_delta)).to be false
      end
    end

    context 'with inconsistent transaction results' do
      before do
        # Setup commands called inside multi
        allow(mock_redis).to receive(:rpush).with(events_key, anything).and_return(1)
        allow(mock_redis).to receive(:hset).with(session_key, anything, anything).and_return(1)
        allow(mock_redis).to receive(:expire).with(any_args).and_return(true)
      end

      it 'handles some commands failing in the transaction' do
        # Return a mix of success and failure
        allow(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1, 0, false, nil])
        allow(ADK.logger).to receive(:error)

        expect(ADK.logger).to receive(:error).with(/Redis MULTI command failed during event append/)
        expect(service.append_event(session_id: session_id, event: event_with_delta)).to be false
      end
    end
  end

  describe 'create_session transaction tests' do
    let(:new_session) do
      instance_double(ADK::Session,
                      id: session_id,
                      app_name: app_name,
                      user_id: user_id,
                      state_to_h: initial_state,
                      created_at: now,
                      updated_at: now)
    end

    before do
      allow(ADK::Session).to receive(:new).and_return(new_session)
      allow(mock_redis).to receive(:multi).and_yield(mock_redis)
      allow(mock_redis).to receive(:hset).and_return(1)
      allow(mock_redis).to receive(:sadd).and_return(1)
      allow(mock_redis).to receive(:expire).and_return(true)
      allow(mock_redis).to receive(:exists?).with(events_key).and_return(true)
    end

    it 'executes session creation as a transaction' do
      allow(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1, 1, 1, 1])

      expect(mock_redis).to receive(:multi).once
      expect(mock_redis).to receive(:hset).once
      expect(mock_redis).to receive(:sadd).once
      # Expect two expire calls (one for session key, one for events key)
      expect(mock_redis).to receive(:expire).with(session_key, session_ttl).once
      expect(mock_redis).to receive(:expire).with(events_key, session_ttl).once

      service.create_session(app_name: app_name, user_id: user_id, initial_state: initial_state)
    end

    it 'handles transaction failure during creation' do
      allow(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([false, nil, 1])
      allow(ADK.logger).to receive(:error)

      expect(ADK.logger).to receive(:error).with(/Redis MULTI command failed during session creation/)

      expect {
        service.create_session(app_name: app_name, user_id: user_id, initial_state: initial_state)
      }.to raise_error(ADK::Error, 'Failed to create session in Redis.')
    end
  end

  describe 'delete_session transaction tests' do
    before do
      allow(mock_redis).to receive(:multi).and_yield(mock_redis)
      allow(mock_redis).to receive(:del).and_return(1)
      allow(mock_redis).to receive(:srem).and_return(1)
    end

    it 'executes deletion as a transaction' do
      allow(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([1, 1, 1])

      expect(mock_redis).to receive(:multi).once
      expect(mock_redis).to receive(:del).with(session_key).once
      expect(mock_redis).to receive(:del).with(events_key).once
      expect(mock_redis).to receive(:srem).once

      expect(service.delete_session(session_id: session_id)).to be true
    end

    it 'handles transaction failure during deletion' do
      allow(mock_redis).to receive(:multi).and_yield(mock_redis).and_return(nil)
      allow(ADK.logger).to receive(:warn)

      expect(ADK.logger).to receive(:warn).with(/Unexpected result from Redis MULTI during session deletion/)

      expect(service.delete_session(session_id: session_id)).to be false
    end

    it 'handles Redis errors during deletion' do
      allow(mock_redis).to receive(:multi).and_raise(Redis::ConnectionError.new('Connection lost'))
      allow(ADK.logger).to receive(:error)

      expect(ADK.logger).to receive(:error).with(/Redis error deleting session/)

      expect(service.delete_session(session_id: session_id)).to be false
    end
  end
end
