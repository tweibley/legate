# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool_context'

RSpec.describe ADK::ToolContext do
  let(:session_id) { 'test-session-123' }
  let(:user_id) { 'test-user-456' }
  let(:app_name) { 'test-app' }
  let(:session_service) { instance_double('ADK::SessionService::Redis') }
  let(:tool_registry) { instance_double('ADK::ToolRegistry') }

  subject(:context) do
    described_class.new(
      session_id: session_id,
      user_id: user_id,
      app_name: app_name,
      session_service: session_service,
      tool_registry: tool_registry
    )
  end

  describe '#initialize' do
    it 'sets the attributes correctly' do
      expect(context.session_id).to eq(session_id)
      expect(context.user_id).to eq(user_id)
      expect(context.app_name).to eq(app_name)
      expect(context.session_service).to eq(session_service)
      expect(context.tool_registry).to eq(tool_registry)
      expect(context.pending_state_delta).to eq({})
    end
  end

  describe '#state_get' do
    it 'retrieves value from session service' do
      allow(session_service).to receive(:get_state).with(session_id: session_id, key: :some_key).and_return('value')
      expect(context.state_get(:some_key)).to eq('value')
    end

    it 'returns nil if session_service is nil' do
      no_service_context = described_class.new(
        session_id: session_id,
        user_id: user_id,
        app_name: app_name
      )
      expect(no_service_context.state_get(:some_key)).to be_nil
    end

    it 'returns nil and logs error if retrieval fails' do
      allow(session_service).to receive(:get_state).and_raise(StandardError, 'fail')
      expect(ADK.logger).to receive(:error) do |&block|
        expect(block.call).to match(/Error in state_get/)
      end
      expect(context.state_get(:some_key)).to be_nil
    end
  end

  describe '#state_set' do
    it 'updates pending_state_delta with symbol keys' do
      context.state_set('foo', 'bar')
      expect(context.pending_state_delta).to eq({ foo: 'bar' })
    end
  end

  describe '#state_update' do
    it 'merges hash into pending_state_delta' do
      context.state_set(:initial, 1)
      context.state_update({ 'new' => 2 })
      expect(context.pending_state_delta).to eq({ initial: 1, new: 2 })
    end

    it 'logs warning for non-hash input' do
      expect(ADK.logger).to receive(:warn) do |&block|
        expect(block.call).to match(/state_update called with non-hash/)
      end
      context.state_update('not a hash')
    end
  end

  describe '#clear_pending_state_delta!' do
    it 'clears the pending state' do
      context.state_set(:foo, 'bar')
      context.clear_pending_state_delta!
      expect(context.pending_state_delta).to be_empty
    end
  end

  describe '#to_h' do
    it 'returns a hash representation' do
      hash = context.to_h
      expect(hash[:session_id]).to eq(session_id)
      expect(hash[:user_id]).to eq(user_id)
      expect(hash[:app_name]).to eq(app_name)
      expect(hash[:session_service_present]).to be true
      expect(hash[:tool_registry_object_id]).to eq(tool_registry.object_id)
    end
  end
end
