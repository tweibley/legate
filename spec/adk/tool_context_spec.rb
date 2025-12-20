# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool_context'

RSpec.describe ADK::ToolContext do
  let(:session_id) { 'test-session-123' }
  let(:user_id) { 'test-user-456' }
  let(:app_name) { 'test-app' }
  let(:tool_registry) { instance_double('ADK::ToolRegistry') }
  let(:session_service) { instance_double('ADK::SessionService::Base') }

  subject(:context) do
    described_class.new(
      session_id: session_id,
      user_id: user_id,
      app_name: app_name,
      tool_registry: tool_registry,
      session_service: session_service
    )
  end

  describe '#state_get' do
    let(:key) { :some_key }
    let(:value) { 'some_value' }

    it 'retrieves value from session service' do
      expect(session_service).to receive(:get_state)
        .with(session_id: session_id, key: key)
        .and_return(value)

      expect(context.state_get(key)).to eq(value)
    end

    context 'when session_service is nil' do
      subject(:context_no_service) do
        described_class.new(
          session_id: session_id,
          user_id: user_id,
          app_name: app_name
        )
      end

      it 'logs warning and returns nil' do
        expect(ADK.logger).to receive(:warn) do |&block|
          expect(block.call).to match(/no session_service available/)
        end
        expect(context_no_service.state_get(key)).to be_nil
      end
    end

    context 'when session_service raises an error' do
      before do
        allow(session_service).to receive(:get_state).and_raise(StandardError, 'Redis failure')
      end

      it 'logs error and returns nil' do
        expect(ADK.logger).to receive(:error) do |&block|
          expect(block.call).to match(/Error in state_get.*Redis failure/)
        end
        expect(context.state_get(key)).to be_nil
      end
    end
  end

  describe '#state_set' do
    it 'sets value in pending_state_delta with symbol key' do
      context.state_set('some_key', 'value')
      expect(context.pending_state_delta).to eq({ some_key: 'value' })
    end

    it 'logs debug message' do
      expect(ADK.logger).to receive(:debug) do |&block|
        expect(block.call).to match(/state_set for key/)
      end
      context.state_set(:key, 'val')
    end
  end

  describe '#state_update' do
    it 'merges hash into pending_state_delta with symbol keys' do
      context.state_set(:existing, 1)
      context.state_update({ 'new_key' => 2, :another => 3 })

      expect(context.pending_state_delta).to eq({ existing: 1, new_key: 2, another: 3 })
    end

    context 'with non-hash argument' do
      it 'logs warning and does not update state' do
        expect(ADK.logger).to receive(:warn) do |&block|
          expect(block.call).to match(/called with non-hash/)
        end
        context.state_update('not a hash')
        expect(context.pending_state_delta).to be_empty
      end
    end
  end

  describe '#clear_pending_state_delta!' do
    it 'clears the pending state' do
      context.state_set(:key, 'val')
      context.clear_pending_state_delta!
      expect(context.pending_state_delta).to be_empty
    end
  end

  describe '#to_h' do
    it 'returns a hash representation of the context' do
      hash = context.to_h

      expect(hash).to include(
        session_id: session_id,
        user_id: user_id,
        app_name: app_name,
        session_service_present: true,
        tool_registry_object_id: tool_registry.object_id
      )
    end

    context 'when session_service is missing' do
      subject(:context_no_service) do
        described_class.new(
          session_id: session_id,
          user_id: user_id,
          app_name: app_name
        )
      end

      it 'sets session_service_present to false' do
        expect(context_no_service.to_h[:session_service_present]).to be false
      end
    end
  end
end
