# File: spec/adk/event_spec.rb
# frozen_string_literal: true

require 'spec_helper' # Adjust if your helper path is different
require 'adk/event'
require 'securerandom'
require 'time'

RSpec.describe ADK::Event do
  let(:valid_role) { :user }
  let(:valid_content) { 'Hello, world!' }
  let(:tool_role) { :tool_request }
  let(:tool_name) { :calculator }
  let(:tool_content) { { operation: 'add', numbers: [1, 2] } }
  let(:state_delta) { { user_mood: 'happy' } }
  let(:custom_event_id) { 'test-event-123' }

  describe '#initialize' do
    it 'initializes with required arguments' do
      event = described_class.new(role: valid_role, content: valid_content)
      expect(event.role).to eq(valid_role)
      expect(event.content).to eq(valid_content)
      expect(event.timestamp).to be_a(Time)
      expect(event.tool_name).to be_nil
      expect(event.state_delta).to be_nil
      expect(event.event_id).to be_a(String)
      expect(event.event_id).not_to be_empty
    end

    it 'initializes with all arguments' do
      timestamp = Time.now.utc - 3600
      event = described_class.new(
        role: tool_role,
        content: tool_content,
        timestamp: timestamp,
        tool_name: tool_name,
        state_delta: state_delta,
        event_id: custom_event_id
      )
      expect(event.role).to eq(tool_role)
      expect(event.content).to eq(tool_content)
      expect(event.timestamp).to eq(timestamp)
      expect(event.tool_name).to eq(tool_name)
      expect(event.state_delta).to eq(state_delta) # Keys already symbols
      expect(event.event_id).to eq(custom_event_id)
    end

    it 'defaults timestamp to Time.now.utc' do
      time_before = Time.now.utc
      event = described_class.new(role: valid_role, content: valid_content)
      time_after = Time.now.utc
      expect(event.timestamp).to be_between(time_before, time_after)
    end

    it 'defaults event_id to a SecureRandom.uuid' do
      allow(SecureRandom).to receive(:uuid).and_return('mocked-uuid')
      event = described_class.new(role: valid_role, content: valid_content)
      expect(event.event_id).to eq('mocked-uuid')
    end

    it 'raises ArgumentError for invalid role' do
      expect { described_class.new(role: :invalid_role, content: valid_content) }
        .to raise_error(ArgumentError, /Invalid role: invalid_role/)
    end

    context 'when role is :tool_request or :tool_result' do
      it 'warns if tool_name is nil' do
        expect(ADK.logger).to receive(:warn).with(/event created without a valid :tool_name symbol/)
        described_class.new(role: :tool_request, content: tool_content, tool_name: nil)
      end

      it 'warns if tool_name is not a Symbol' do
        expect(ADK.logger).to receive(:warn).with(/event created without a valid :tool_name symbol/)
        described_class.new(role: :tool_result, content: { result: 'ok' }, tool_name: 'not_a_symbol')
      end

      it 'does not warn if tool_name is a valid Symbol' do
        expect(ADK.logger).not_to receive(:warn).with(/tool_name/)
        described_class.new(role: :tool_request, content: tool_content, tool_name: :calculator)
      end
    end

    it 'warns and sets state_delta to nil if it is not a Hash' do
      expect(ADK.logger).to receive(:warn).with(/state_delta must be a Hash or nil, received Array/)
      event = described_class.new(role: valid_role, content: valid_content, state_delta: [1, 2, 3])
      expect(event.state_delta).to be_nil
    end

    it 'symbolizes keys in state_delta' do
      event = described_class.new(role: valid_role, content: valid_content, state_delta: { 'string_key' => 'value' })
      expect(event.state_delta).to eq({ string_key: 'value' })
    end

    it 'warns if content is of an unusual type' do
      unusual_content = Object.new
      expect(ADK.logger).to receive(:warn).with(/Content is of unusual type \(Object\): #{unusual_content.inspect}/)
      described_class.new(role: valid_role, content: unusual_content)
    end

    it 'does not warn for common content types (String, Hash, Array, Nil, Numeric, Boolean)' do
      expect(ADK.logger).not_to receive(:warn).with(/Content is of unusual type/)
      described_class.new(role: valid_role, content: 'string')
      described_class.new(role: valid_role, content: { key: 'value' })
      described_class.new(role: valid_role, content: [1, 2])
      described_class.new(role: valid_role, content: nil)
      described_class.new(role: valid_role, content: 123)
      described_class.new(role: valid_role, content: 1.23)
      described_class.new(role: valid_role, content: true)
      described_class.new(role: valid_role, content: false)
    end

    it 'is frozen after initialization' do
      event = described_class.new(role: valid_role, content: valid_content)
      expect(event).to be_frozen
      expect { event.instance_variable_set(:@role, :agent) }.to raise_error(FrozenError)
    end
  end

  describe '#final_agent_response?' do
    it 'returns true if role is :agent' do
      event = described_class.new(role: :agent, content: 'Final answer')
      expect(event.final_agent_response?).to be true
    end

    it 'returns false if role is not :agent' do
      event_user = described_class.new(role: :user, content: 'Hi')
      event_tool_req = described_class.new(role: :tool_request, content: {}, tool_name: :calc)
      event_tool_res = described_class.new(role: :tool_result, content: {}, tool_name: :calc)
      expect(event_user.final_agent_response?).to be false
      expect(event_tool_req.final_agent_response?).to be false
      expect(event_tool_res.final_agent_response?).to be false
    end
  end

  describe '#to_h' do
    it 'serializes the event to a hash' do
      timestamp = Time.iso8601('2023-01-01T12:00:00.123Z')
      event = described_class.new(
        role: tool_role,
        content: tool_content,
        timestamp: timestamp,
        tool_name: tool_name,
        state_delta: state_delta,
        event_id: custom_event_id
      )
      expected_hash = {
        role: tool_role,
        content: tool_content,
        timestamp: '2023-01-01T12:00:00.123Z', # ISO8601 with milliseconds
        tool_name: tool_name,
        state_delta: state_delta,
        event_id: custom_event_id
      }
      expect(event.to_h).to eq(expected_hash)
    end

    it 'handles nil values correctly' do
      timestamp = Time.iso8601('2023-01-01T12:00:00.123Z')
      event = described_class.new(role: :user, content: nil, timestamp: timestamp)
      allow(SecureRandom).to receive(:uuid).and_return('default-uuid') # Control default ID
      event_default_id = described_class.new(role: :user, content: nil, timestamp: timestamp)

      expected_hash = {
        role: :user,
        content: nil,
        timestamp: '2023-01-01T12:00:00.123Z',
        tool_name: nil,
        state_delta: nil,
        event_id: 'default-uuid'
      }
      expect(event_default_id.to_h).to eq(expected_hash)
    end
  end

  describe '.from_h' do
    let(:timestamp_str) { '2023-01-01T12:00:00.123Z' }
    let(:timestamp) { Time.iso8601(timestamp_str) }
    let(:event_hash) do
      {
        'role' => 'tool_result',
        'content' => { 'result' => 'Success' },
        'timestamp' => timestamp_str,
        'tool_name' => 'calculator',
        'state_delta' => { 'calculation_count' => 1 },
        'event_id' => 'event-456'
      }
    end

    it 'deserializes a valid hash with string keys' do
      event = described_class.from_h(event_hash)
      expect(event).to be_a(ADK::Event)
      expect(event.role).to eq(:tool_result)
      expect(event.content).to eq({ 'result' => 'Success' })
      expect(event.timestamp).to eq(timestamp)
      expect(event.tool_name).to eq(:calculator)
      expect(event.state_delta).to eq({ calculation_count: 1 }) # Symbolized keys
      expect(event.event_id).to eq('event-456')
    end

    it 'deserializes a valid hash with symbol keys' do
      symbol_key_hash = event_hash.transform_keys(&:to_sym)
      event = described_class.from_h(symbol_key_hash)
      expect(event).to be_a(ADK::Event)
      expect(event.role).to eq(:tool_result)
      expect(event.timestamp).to eq(timestamp)
      expect(event.tool_name).to eq(:calculator)
      expect(event.state_delta).to eq({ calculation_count: 1 })
      expect(event.event_id).to eq('event-456')
    end

    it 'handles missing optional fields (tool_name, state_delta, event_id)' do
      minimal_hash = {
        role: 'user',
        content: 'hello',
        timestamp: timestamp_str
      }
      event = described_class.from_h(minimal_hash)
      expect(event).to be_a(ADK::Event)
      expect(event.role).to eq(:user)
      expect(event.content).to eq('hello')
      expect(event.timestamp).to eq(timestamp)
      expect(event.tool_name).to be_nil
      expect(event.state_delta).to be_nil
      expect(event.event_id).to be_a(String) # Should default
    end

    it 'defaults timestamp if missing' do
      hash_no_ts = event_hash.except('timestamp')
      time_before = Time.now.utc
      event = described_class.from_h(hash_no_ts)
      time_after = Time.now.utc
      expect(event.timestamp).to be_between(time_before, time_after)
    end

    it 'symbolizes keys in state_delta during deserialization' do
      hash_with_string_delta_keys = event_hash.merge('state_delta' => { 'string_key' => 'value' })
      event = described_class.from_h(hash_with_string_delta_keys)
      expect(event.state_delta).to eq({ string_key: 'value' })
    end

    it 'returns nil and logs error for invalid role' do
      invalid_hash = event_hash.merge('role' => 'invalid')
      expect(ADK.logger).to receive(:error).with(/Failed to parse timestamp or invalid role: Invalid role: invalid/)
      expect(described_class.from_h(invalid_hash)).to be_nil
    end

    it 'returns nil and logs error for invalid timestamp format' do
      invalid_hash = event_hash.merge('timestamp' => 'not-a-time')
      # Adjust regex to match Time.iso8601's specific error message
      expect(ADK.logger).to receive(:error).with(/Failed to parse timestamp or invalid role: invalid xmlschema format: "not-a-time"/)
      expect(described_class.from_h(invalid_hash)).to be_nil
    end

    it 'returns nil and logs error for type errors (e.g., non-hash state_delta)' do
      invalid_hash = event_hash.merge('state_delta' => 'not_a_hash')
      # Expect the message from the TypeError rescue block
      expect(ADK.logger).to receive(:error).with(/Type error during deserialization.*Hash: #{invalid_hash.inspect}/)
      expect(described_class.from_h(invalid_hash)).to be_nil
    end

    it 'returns nil and logs error if role is missing' do
      invalid_hash = event_hash.except('role')
      # Expecting to_sym on nil to raise NoMethodError, caught as ArgumentError by rescue
      # Update: Actually, it should fail in the `initialize` method's role validation.
      expect(ADK.logger).to receive(:error).with(/Failed to parse timestamp or invalid role: Invalid role:/)
      expect(described_class.from_h(invalid_hash)).to be_nil
    end
  end
end
