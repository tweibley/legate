# File: spec/adk/session_service/in_memory_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/session_service/in_memory'
require 'adk/session'
require 'adk/event'

RSpec.describe ADK::SessionService::InMemory do
  # Allow logger info globally for setup
  before do
    # Allow info level logs generally for setup unless specifically overridden
    allow(ADK.logger).to receive(:info)
    # Allow other levels too if needed, or set a default allow
    allow(ADK.logger).to receive(:debug)
    allow(ADK.logger).to receive(:warn)
    allow(ADK.logger).to receive(:error)
  end

  subject(:service) { described_class.new }
  let(:app_name) { 'test_app' }
  let(:user_id) { 'test_user' }
  let(:initial_state) { { 'foo' => 'bar' } }

  describe '#initialize' do
    let!(:service_instance) { described_class.new }

    it 'initializes sessions and scoped_states as Concurrent::Map' do
      expect(service_instance.sessions).to be_a(Concurrent::Map)
      # Private member access for testing internal state, use with caution
      expect(service_instance.instance_variable_get(:@scoped_states)).to be_a(Concurrent::Map)
    end

    it 'logs initialization' do
      expect(ADK.logger).to have_received(:info).with('InMemorySessionService initialized.')
    end
  end

  describe '#persistent?' do
    it 'returns false' do
      expect(service.persistent?).to be false
    end
  end

  describe '#create_session' do
    # Re-enable test
    it 'creates a new session with the correct attributes' do
      local_initial_state = { 'foo' => 'bar' } # Define locally
      session = service.create_session(app_name: app_name, user_id: user_id, initial_state: local_initial_state)
      expect(session).to be_a(ADK::Session)
      expect(session.app_name).to eq(app_name)
      expect(session.user_id).to eq(user_id)

      # Revert to checking public state accessor
      expect(session.state[:foo]).to eq('bar')

      expect(session.session_service).to eq(service)
      expect(service.sessions.key?(session.id)).to be true
      expect(service.sessions[session.id]).to eq(session)
    end

    it 'logs session creation' do
      expect(ADK.logger).to receive(:info).with(/Created session: .+ for app:#{app_name}, user:#{user_id}/).ordered
      service.create_session(app_name: app_name, user_id: user_id)
    end
  end

  describe '#get_session' do
    let!(:session) { service.create_session(app_name: app_name, user_id: user_id) }

    it 'retrieves an existing session by ID' do
      retrieved_session = service.get_session(session_id: session.id)
      expect(retrieved_session).to eq(session)
    end

    it 'returns nil if the session ID does not exist' do
      retrieved_session = service.get_session(session_id: 'nonexistent_id')
      expect(retrieved_session).to be_nil
    end

    it 'logs session retrieval success' do
      expect(ADK.logger).to receive(:debug).with("Retrieved session: #{session.id}")
      service.get_session(session_id: session.id)
    end

    it 'logs session not found' do
      expect(ADK.logger).to receive(:warn).with('Session not found: nonexistent_id')
      service.get_session(session_id: 'nonexistent_id')
    end
  end

  # Testing deprecated method for completeness, but noting its status
  describe '#save_session (deprecated)' do
    let!(:session) { service.create_session(app_name: app_name, user_id: user_id) }
    let(:non_existent_session) do
      ADK::Session.new(app_name: 'other', user_id: 'other', session_service: service)
    end

    it 'returns true for an existing session and updates timestamp' do
      original_updated_at = session.updated_at
      sleep(0.01) # Ensure time progresses
      expect(ADK.logger).to receive(:warn).with('InMemorySessionService#save_session called (likely unnecessary). Use append_event.')
      expect(service.save_session(session: session)).to be true
      expect(session.updated_at).to be > original_updated_at
    end

    it 'returns false for a non-existent session' do
      expect(ADK.logger).to receive(:error).with("Attempted to save non-existent session: #{non_existent_session.id}")
      expect(service.save_session(session: non_existent_session)).to be false
    end
  end

  describe '#append_event' do
    subject(:service) { described_class.new }
    let!(:session) { service.create_session(app_name: app_name, user_id: user_id, initial_state: { 'count' => 0 }) }
    let(:event) { ADK::Event.new(role: :user, content: 'test event content', state_delta: { 'count' => 1 }) }

    it 'appends an event to the session' do
      allow(service).to receive(:get_session).with(session_id: session.id).and_return(session)
      expect(session).to receive(:add_event).with(event)
      expect(service.append_event(session_id: session.id, event: event)).to be true
    end

    it 'returns false if the session ID does not exist' do
      allow(service).to receive(:get_session).with(session_id: 'nonexistent_id').and_return(nil)
      expect(service.append_event(session_id: 'nonexistent_id', event: event)).to be false
    end
  end

  describe '#delete_session' do
    subject(:service) { described_class.new }
    let!(:session) { service.create_session(app_name: app_name, user_id: user_id) }

    it 'deletes an existing session' do
      expect(service.sessions.key?(session.id)).to be true
      expect(ADK.logger).to receive(:info).with("Deleted session: #{session.id}")
      expect(service.delete_session(session_id: session.id)).to be true
      expect(service.sessions.key?(session.id)).to be false
    end

    it 'returns false if the session ID does not exist' do
      expect(ADK.logger).to receive(:warn).with('Attempted to delete non-existent session: nonexistent_id')
      expect(service.delete_session(session_id: 'nonexistent_id')).to be false
    end
  end

  describe '#list_sessions' do
    let!(:session1) { service.create_session(app_name: 'app1', user_id: 'user1') }
    let!(:session2) { service.create_session(app_name: 'app1', user_id: 'user2') }
    let!(:session3) { service.create_session(app_name: 'app2', user_id: 'user1') }

    it 'returns all sessions when no filters are provided' do
      expect(service.list_sessions).to contain_exactly(session1, session2, session3)
    end

    it 'filters sessions by app_name' do
      expect(service.list_sessions(app_name: 'app1')).to contain_exactly(session1, session2)
      expect(service.list_sessions(app_name: 'app2')).to contain_exactly(session3)
      expect(service.list_sessions(app_name: 'app3')).to be_empty
    end

    it 'filters sessions by user_id' do
      expect(service.list_sessions(user_id: 'user1')).to contain_exactly(session1, session3)
      expect(service.list_sessions(user_id: 'user2')).to contain_exactly(session2)
      expect(service.list_sessions(user_id: 'user3')).to be_empty
    end

    it 'filters sessions by both app_name and user_id' do
      expect(service.list_sessions(app_name: 'app1', user_id: 'user1')).to contain_exactly(session1)
      expect(service.list_sessions(app_name: 'app1', user_id: 'user2')).to contain_exactly(session2)
      expect(service.list_sessions(app_name: 'app2', user_id: 'user1')).to contain_exactly(session3)
      expect(service.list_sessions(app_name: 'app1', user_id: 'user3')).to be_empty
    end

    it 'logs the count of listed sessions' do
      expect(ADK.logger).to receive(:debug).with('Listing 3 sessions.')
      service.list_sessions # No filters
      expect(ADK.logger).to receive(:debug).with('Listing 1 sessions.')
      service.list_sessions(app_name: 'app1', user_id: 'user1')
    end
  end

  describe '#save_scoped_state, #load_scoped_state, #clear_scoped_state' do
    let(:scope) { 'user' }
    let(:key) { 'settings' }
    let(:value) { { 'theme' => 'dark' } }
    let(:state_key) { "#{scope}:#{key}" }

    it 'saves and loads scoped state correctly' do
      service.save_scoped_state(scope, key, value)
      loaded_value = service.load_scoped_state(scope, key)
      expect(loaded_value).to eq(value)
    end

    it 'load_scoped_state returns nil for non-existent keys' do
      expect(service.load_scoped_state(scope, 'non_existent_key')).to be_nil
    end

    it 'clear_scoped_state removes a specific key' do
      service.save_scoped_state(scope, key, value)
      service.clear_scoped_state(scope, key)
      expect(service.load_scoped_state(scope, key)).to be_nil
    end

    it 'clear_scoped_state with wildcard removes all keys in that scope' do
      service.save_scoped_state(scope, 'key1', 'value1')
      service.save_scoped_state(scope, 'key2', 'value2')
      service.save_scoped_state('app', 'key3', 'value3') # Different scope

      service.clear_scoped_state(scope, '*')

      expect(service.load_scoped_state(scope, 'key1')).to be_nil
      expect(service.load_scoped_state(scope, 'key2')).to be_nil
      expect(service.load_scoped_state('app', 'key3')).to eq('value3') # Should still exist
    end

    it 'clear_scoped_state with wildcard does nothing if no keys match the scope' do
      service.save_scoped_state('app', 'key3', 'value3')
      expect { service.clear_scoped_state('user', '*') }.not_to(change {
        service.instance_variable_get(:@scoped_states).size
      })
    end

    it 'clear_scoped_state does nothing if the specific key does not exist' do
      expect { service.clear_scoped_state(scope, 'non_existent_key') }.not_to(change {
        service.instance_variable_get(:@scoped_states).size
      })
    end
  end
end
