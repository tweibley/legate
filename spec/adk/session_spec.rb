# File: spec/adk/session_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'concurrent'
require 'time' # Required for Time.iso8601

RSpec.describe ADK::Session do
  let(:app_name) { 'test_app' }
  let(:user_id) { 'test_user' }
  let(:session_id) { SecureRandom.uuid }
  let(:mock_session_service) { instance_double(ADK::SessionService::Base) }
  let(:initial_state) { { key1: 'value1', key2: 123 } }
  let(:event1_data) { { role: :user, content: 'Hello' } }
  let(:event2_data) { { role: :agent, content: 'Hi there' } }
  let(:event1) { ADK::Event.from_h(event1_data) }
  let(:event2) { ADK::Event.from_h(event2_data) }
  let(:initial_events) { [event1, event2] }
  let(:logger_spy) { spy('Logger') }

  # Default session instance for basic tests
  let(:session) do
    described_class.new(
      id: session_id,
      app_name: app_name,
      user_id: user_id,
      initial_state: initial_state,
      events: initial_events,
      session_service: mock_session_service
    )
  end

  before do
    allow(ADK).to receive(:logger).and_return(logger_spy)
    # Stub service methods by default to return nil or true as appropriate
    allow(mock_session_service).to receive(:load_scoped_state).and_return(nil)
    allow(mock_session_service).to receive(:save_scoped_state).and_return(true)
    allow(mock_session_service).to receive(:clear_scoped_state).and_return(true)
  end

  describe '#initialize' do
    it 'sets basic attributes correctly' do
      expect(session.id).to eq(session_id)
      expect(session.app_name).to eq(app_name)
      expect(session.user_id).to eq(user_id)
      expect(session.created_at).to be_a(Time)
      expect(session.updated_at).to eq(session.created_at)
      expect(session.session_service).to eq(mock_session_service)
    end

    it 'initializes with a default UUID if no ID is provided' do
      default_id_session = described_class.new(app_name: app_name, user_id: user_id)
      expect(default_id_session.id).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end

    it 'initializes state correctly from initial_state' do
      # state_to_h is needed because internal state is Concurrent::Map
      expect(session.state_to_h).to eq(initial_state)
    end

    it 'initializes events correctly' do
      expect(session.events).to contain_exactly(event1, event2)
    end

    it 'initializes events as empty array if not provided' do
      empty_session = described_class.new(app_name: app_name, user_id: user_id)
      expect(empty_session.events).to eq([])
    end

    it 'skips invalid event data during initialization and logs warning' do
      invalid_event_object = { invalid: 'data' } # Use a non-Event object
      session_with_invalid = described_class.new(
        app_name: app_name,
        user_id: user_id,
        events: [event1, invalid_event_object] # Pass one valid Event, one invalid object
      )
      expect(logger_spy).to have_received(:warn).with(/Invalid event data skipped:.*invalid.*data/)
      expect(session_with_invalid.events.size).to eq(1)
      expect(session_with_invalid.events.first).to eq(event1) # Check the object itself
    end
  end

  describe '#add_event' do
    let(:new_event) { ADK::Event.new(role: :user, content: 'Another message') }
    let(:event_with_delta) {
      ADK::Event.new(role: :tool_result, tool_name: :test_tool, content: {}, state_delta: { new_key: 'new_value' })
    }

    it 'adds a valid event to the events array' do
      expect { session.add_event(new_event) }.to change { session.events.count }.by(1)
      expect(session.events.last).to eq(new_event)
    end

    it 'updates the updated_at timestamp' do
      initial_time = session.updated_at
      sleep(0.01) # Ensure time changes
      session.add_event(new_event)
      expect(session.updated_at).to be > initial_time
    end

    it 'returns the added event' do
      expect(session.add_event(new_event)).to eq(new_event)
    end

    it 'returns nil and does not add an invalid object' do
      invalid_event = { not: 'an event' }
      expect { session.add_event(invalid_event) }.not_to change { session.events.count }
      expect(session.add_event(invalid_event)).to be_nil
    end

    it 'calls update_state if event has a state_delta' do
      expect(session).to receive(:update_state).with({ new_key: 'new_value' })
      session.add_event(event_with_delta)
    end

    it 'does not call update_state if event has no state_delta' do
      expect(session).not_to receive(:update_state)
      session.add_event(new_event)
    end

    it 'does not call update_state if state_delta is empty' do
      empty_delta_event = ADK::Event.new(role: :user, content: '', state_delta: {})
      expect(session).not_to receive(:update_state)
      session.add_event(empty_delta_event)
    end
  end

  describe 'State Management (get/set/update/delete/clear)' do
    context 'without prefixes (in-memory state)' do
      it '#get_state retrieves existing keys' do
        expect(session.get_state(:key1)).to eq('value1')
        expect(session.get_state('key2')).to eq(123) # Test string key
      end

      it '#get_state returns nil for non-existent keys' do
        expect(session.get_state(:non_existent)).to be_nil
      end

      it '#set_state adds a new key-value pair' do
        session.set_state(:new_key, 'new_val')
        expect(session.get_state(:new_key)).to eq('new_val')
        expect(session.state_to_h[:new_key]).to eq('new_val')
      end

      it '#set_state updates an existing key-value pair' do
        session.set_state(:key1, 'updated_value')
        expect(session.get_state(:key1)).to eq('updated_value')
      end

      it '#set_state updates updated_at' do
        initial_time = session.updated_at
        sleep(0.01)
        session.set_state(:key1, 'updated_value')
        expect(session.updated_at).to be > initial_time
      end

      it '#update_state merges a hash into the state' do
        session.update_state({ key2: 456, key3: true })
        expect(session.get_state(:key1)).to eq('value1')
        expect(session.get_state(:key2)).to eq(456)
        expect(session.get_state(:key3)).to eq(true)
      end

      it '#update_state does nothing if input is not a hash' do
        initial_state_h = session.state_to_h
        session.update_state('not a hash')
        expect(session.state_to_h).to eq(initial_state_h)
      end

      it '#update_state updates updated_at' do
        initial_time = session.updated_at
        sleep(0.01)
        session.update_state({ key3: true })
        expect(session.updated_at).to be > initial_time
      end

      it '#delete_state removes an existing key' do
        deleted_value = session.delete_state(:key1)
        expect(deleted_value).to eq('value1')
        expect(session.get_state(:key1)).to be_nil
        expect(session.state_to_h).not_to have_key(:key1)
      end

      it '#delete_state returns nil for non-existent key' do
        expect(session.delete_state(:non_existent)).to be_nil
      end

      it '#delete_state updates updated_at' do
        initial_time = session.updated_at
        sleep(0.01)
        session.delete_state(:key1)
        expect(session.updated_at).to be > initial_time
      end

      it '#clear_state! removes all in-memory keys' do
        session.clear_state!
        expect(session.state_to_h).to be_empty
        expect(session.get_state(:key1)).to be_nil
      end

      it '#clear_state! updates updated_at' do
        initial_time = session.updated_at
        sleep(0.01)
        session.clear_state!
        expect(session.updated_at).to be > initial_time
      end

      it '#state_to_h returns a plain hash copy' do
        state_hash = session.state_to_h
        expect(state_hash).to be_a(Hash)
        expect(state_hash).to eq({ key1: 'value1', key2: 123 })
        # Ensure it's a copy
        state_hash[:new_key] = 'added_to_copy'
        expect(session.get_state(:new_key)).to be_nil
      end
    end

    context 'with prefixes (session_service interaction)' do
      let(:user_prefixed_key) { 'user:pref' }
      let(:app_prefixed_key) { 'app:setting' }
      let(:temp_prefixed_key) { 'temp:data' }

      it '#get_state calls session_service.load_scoped_state for prefixed keys' do
        expect(mock_session_service).to receive(:load_scoped_state).with('user', 'pref').and_return('user_value')
        expect(mock_session_service).to receive(:load_scoped_state).with('app', 'setting').and_return(true)
        expect(session.get_state(user_prefixed_key)).to eq('user_value')
        expect(session.get_state(app_prefixed_key)).to eq(true)
      end

      it '#set_state calls session_service.save_scoped_state for prefixed keys' do
        expect(mock_session_service).to receive(:save_scoped_state).with('user', 'pref', 'new_user_val')
        expect(mock_session_service).to receive(:save_scoped_state).with('temp', 'data', { complex: true })
        session.set_state(user_prefixed_key, 'new_user_val')
        session.set_state(temp_prefixed_key, { complex: true })
      end

      it '#update_state calls session_service.save_scoped_state for prefixed keys' do
        expect(mock_session_service).to receive(:save_scoped_state).with('user', 'pref', 'val1')
        expect(mock_session_service).to receive(:save_scoped_state).with('app', 'setting', 123)
        # Also test mixing prefixed and non-prefixed
        session.update_state({ 'user:pref' => 'val1', 'app:setting' => 123, :non_prefixed => true })
        internal_state = session.instance_variable_get(:@state)
        expect(internal_state[:non_prefixed]).to eq(true)
      end

      it '#delete_state calls session_service.clear_scoped_state for prefixed keys' do
        expect(mock_session_service).to receive(:clear_scoped_state).with('user', 'pref')
        expect(mock_session_service).to receive(:clear_scoped_state).with('app', 'setting')
        session.delete_state(user_prefixed_key)
        session.delete_state(app_prefixed_key)
      end

      it '#clear_state! calls session_service.clear_scoped_state for all prefixes with wildcard' do
        ADK::Session::VALID_PREFIXES.each do |prefix|
          expect(mock_session_service).to receive(:clear_scoped_state).with(prefix, '*')
        end
        session.clear_state!
        # Also ensure in-memory state is cleared
        expect(session.state_to_h).to be_empty
      end
    end

    context 'state validation' do
      it '#set_state raises SerializationError for non-serializable value' do
        expect {
          session.set_state(:bad_key, Time.now)
        }.to raise_error(ADK::SerializationError, /must be JSON-serializable/)
        expect { session.set_state(:bad_key, Object.new) }.to raise_error(ADK::SerializationError)
        expect { session.set_state(:bad_nested, { key: Time.now }) }.to raise_error(ADK::SerializationError)
      end

      it '#set_state allows nil, basic types, and nested serializable structures' do
        expect { session.set_state(:ok_nil, nil) }.not_to raise_error
        expect { session.set_state(:ok_str, 'string') }.not_to raise_error
        expect { session.set_state(:ok_int, 123) }.not_to raise_error
        expect { session.set_state(:ok_float, 1.23) }.not_to raise_error
        expect { session.set_state(:ok_true, true) }.not_to raise_error
        expect { session.set_state(:ok_false, false) }.not_to raise_error
        expect { session.set_state(:ok_hash, { a: 1, b: [true, nil] }) }.not_to raise_error
        expect { session.set_state(:ok_array, [1, 's', { k: false }]) }.not_to raise_error
      end

      it '#set_state raises InvalidPrefixError for invalid prefixes' do
        expect {
          session.set_state('invalid:key', 1)
        }.to raise_error(ADK::InvalidPrefixError, /Invalid state key prefix: invalid/)
      end

      it '#set_state allows valid prefixes' do
        expect { session.set_state('user:key', 1) }.not_to raise_error
        expect { session.set_state('app:key', 1) }.not_to raise_error
        expect { session.set_state('temp:key', 1) }.not_to raise_error
      end

      it '#update_state raises SerializationError if any value is invalid' do
        expect { session.update_state({ good: 1, bad: Time.now }) }.to raise_error(ADK::SerializationError)
      end

      it '#update_state raises InvalidPrefixError if any key has invalid prefix' do
        expect { session.update_state({ 'user:good' => 1, 'bad:prefix' => 2 }) }.to raise_error(ADK::InvalidPrefixError)
      end

      it '#delete_state raises InvalidPrefixError for invalid prefixes' do
        expect { session.delete_state('invalid:key') }.to raise_error(ADK::InvalidPrefixError)
      end
    end
  end

  describe 'Private Methods' do
    describe '#parse_key' do
      it 'returns [prefix, key] for prefixed keys' do
        expect(session.send(:parse_key, 'user:my_key')).to eq(%w[user my_key])
        expect(session.send(:parse_key, 'app:settings:nested')).to eq(['app', 'settings:nested'])
        expect(session.send(:parse_key, :'temp:data')).to eq(%w[temp data]) # Symbol key
      end

      it 'returns [nil, key] for non-prefixed keys' do
        expect(session.send(:parse_key, 'my_key')).to eq([nil, 'my_key'])
        expect(session.send(:parse_key, :simple_key)).to eq([nil, 'simple_key']) # Symbol key
      end
    end

    describe '#validate_prefix!' do
      it 'does nothing for nil prefix' do
        expect { session.send(:validate_prefix!, nil) }.not_to raise_error
      end

      it 'does nothing for valid prefixes' do
        ADK::Session::VALID_PREFIXES.each do |prefix|
          expect { session.send(:validate_prefix!, prefix) }.not_to raise_error
        end
      end

      it 'raises InvalidPrefixError for invalid prefix' do
        expect { session.send(:validate_prefix!, 'invalid') }.to raise_error(ADK::InvalidPrefixError)
        expect { session.send(:validate_prefix!, 'users') }.to raise_error(ADK::InvalidPrefixError)
      end
    end

    describe '#validate_serializable!' do
      it 'allows nil' do
        expect { session.send(:validate_serializable!, nil) }.not_to raise_error
      end

      it 'allows basic JSON types' do
        expect { session.send(:validate_serializable!, 'string') }.not_to raise_error
        expect { session.send(:validate_serializable!, 123) }.not_to raise_error
        expect { session.send(:validate_serializable!, 45.6) }.not_to raise_error
        expect { session.send(:validate_serializable!, true) }.not_to raise_error
        expect { session.send(:validate_serializable!, false) }.not_to raise_error
      end

      it 'allows nested serializable hashes' do
        expect { session.send(:validate_serializable!, { a: 1, b: { c: [true, 'd'] } }) }.not_to raise_error
      end

      it 'allows nested serializable arrays' do
        expect { session.send(:validate_serializable!, [1, 'a', [false, { k: nil }]]) }.not_to raise_error
      end

      it 'raises SerializationError for non-serializable objects' do
        expect { session.send(:validate_serializable!, Time.now) }.to raise_error(ADK::SerializationError)
        expect { session.send(:validate_serializable!, Object.new) }.to raise_error(ADK::SerializationError)
        expect { session.send(:validate_serializable!, Set.new) }.to raise_error(ADK::SerializationError)
      end

      it 'raises SerializationError for nested non-serializable objects' do
        expect { session.send(:validate_serializable!, { a: 1, b: Time.now }) }.to raise_error(ADK::SerializationError)
        expect { session.send(:validate_serializable!, [1, 2, Object.new]) }.to raise_error(ADK::SerializationError)
      end
    end
  end

  describe 'Serialization (#to_h, .from_h)' do
    let(:now) { Time.now.utc }
    let(:session_for_serialization) do
      s = described_class.new(
        id: session_id,
        app_name: app_name,
        user_id: user_id,
        initial_state: { k: 'v' },
        events: [ADK::Event.new(role: :user, content: 'hi')] # Create event to get its ID
      )
      # Manually set timestamps for predictable serialization
      s.instance_variable_set(:@created_at, now)
      s.instance_variable_set(:@updated_at, now + 5) # Simulate update
      s
    end
    # Get the actual event hash generated by the event instance
    let(:serialized_event) { session_for_serialization.events[0].to_h }
    let(:session_hash) { session_for_serialization.to_h }

    it '#to_h serializes session to a hash correctly' do
      expect(session_hash).to eq({
                                   id: session_id,
                                   app_name: app_name,
                                   user_id: user_id,
                                   created_at: now.iso8601(3),
                                   updated_at: (now + 5).iso8601(3),
                                   state: { k: 'v' },
                                   events: [serialized_event] # Use the actual serialized event hash
                                 })
    end

    it '.from_h deserializes a valid hash correctly' do
      deserialized_session = described_class.from_h(session_hash)
      expect(deserialized_session).to be_a(ADK::Session)
      expect(deserialized_session.id).to eq(session_id)
      expect(deserialized_session.app_name).to eq(app_name)
      expect(deserialized_session.user_id).to eq(user_id)
      expect(deserialized_session.state_to_h).to eq({ k: 'v' })
      expect(deserialized_session.events.size).to eq(1)
      expect(deserialized_session.events[0].role).to eq(:user)
      expect(deserialized_session.events[0].content).to eq('hi')
      # Compare timestamps with tolerance due to potential float precision
      expect(deserialized_session.created_at).to be_within(0.001).of(now)
      expect(deserialized_session.updated_at).to be_within(0.001).of(now + 5)
    end

    it '.from_h handles missing optional fields' do
      minimal_hash = { app_name: app_name, user_id: user_id }
      deserialized = described_class.from_h(minimal_hash)
      expect(deserialized).to be_a(ADK::Session)
      expect(deserialized.id).to be_a(String)
      expect(deserialized.state_to_h).to eq({})
      expect(deserialized.events).to eq([])
      expect(deserialized.created_at).to be_a(Time)
      expect(deserialized.updated_at).to eq(deserialized.created_at)
    end

    it '.from_h skips invalid event data during deserialization' do
      hash_with_bad_event = session_hash.dup
      hash_with_bad_event[:events] = [session_hash[:events][0], { invalid: 'event' }]
      deserialized = described_class.from_h(hash_with_bad_event)
      expect(deserialized.events.size).to eq(1)
      expect(deserialized.events[0].role).to eq(:user)
    end

    it '.from_h returns nil and logs error on ArgumentError (e.g., bad timestamp)' do
      bad_timestamp_hash = session_hash.dup
      bad_timestamp_hash[:created_at] = 'invalid-time'
      # Final attempt: Make regex extremely general, just look for the core parts.
      expect(logger_spy).to receive(:error).with(/Session\.from_h: Failed to deserialize.*Error:.*Data:.*#{Regexp.escape(bad_timestamp_hash.inspect)}/m)
      expect(described_class.from_h(bad_timestamp_hash)).to be_nil
    end

    it '.from_h handles hash with string keys (optimization verification)' do
      # Simulate JSON.parse result where keys are strings
      string_key_hash = JSON.parse(JSON.generate(session_hash))
      deserialized = described_class.from_h(string_key_hash)

      expect(deserialized).to be_a(ADK::Session)
      expect(deserialized.id).to eq(session_id)
      expect(deserialized.events.size).to eq(1)
      expect(deserialized.events.first.content).to eq('hi')
    end
  end
end
