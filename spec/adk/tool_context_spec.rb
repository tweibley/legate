# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool_context'

RSpec.describe ADK::ToolContext do
  let(:session_service) { instance_double("ADK::SessionService::Base") }
  let(:logger) { instance_double("Logger") }
  let(:session_id) { "sess-123" }
  let(:user_id) { "user-456" }
  let(:app_name) { "app-789" }
  let(:invocation_id) { "inv-abc" }

  # We instantiate the context with our mocks
  let(:context) do
    described_class.new(
      session_id: session_id,
      user_id: user_id,
      app_name: app_name,
      session_service: session_service,
      logger: logger,
      invocation_id: invocation_id
    )
  end

  before do
    # ADK::ToolContext uses ADK.logger internally, so we must mock ADK.logger
    # to capture and verify log messages.
    allow(ADK).to receive(:logger).and_return(logger)

    # Allow standard log calls by default
    allow(logger).to receive(:debug)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  describe "#state_get" do
    it "returns value from session service" do
      expect(session_service).to receive(:get_state)
        .with(session_id: session_id, key: :my_key)
        .and_return("my_value")

      expect(context.state_get(:my_key)).to eq("my_value")
    end

    it "logs debug message" do
      allow(session_service).to receive(:get_state).and_return("value")
      expect(logger).to receive(:debug) do |&block|
        expect(block.call).to include("state_get for key: my_key")
      end
      context.state_get(:my_key)
    end

    context "without session service" do
      let(:session_service) { nil }

      it "returns nil and logs warning" do
        expect(logger).to receive(:warn) do |&block|
          expect(block.call).to include("no session_service available")
        end
        expect(context.state_get(:my_key)).to be_nil
      end
    end

    context "when session service raises error" do
      before do
        allow(session_service).to receive(:get_state).and_raise(StandardError.new("connection failed"))
      end

      it "returns nil and logs error" do
        expect(logger).to receive(:error) do |&block|
          expect(block.call).to include("Error in state_get", "connection failed")
        end
        expect(context.state_get(:my_key)).to be_nil
      end
    end
  end

  describe "#state_set" do
    it "updates pending_state_delta" do
      context.state_set(:new_key, "new_value")
      expect(context.pending_state_delta).to eq(new_key: "new_value")
    end

    it "logs debug message" do
      expect(logger).to receive(:debug) do |&block|
        expect(block.call).to include("state_set for key: new_key", "new_value")
      end
      context.state_set(:new_key, "new_value")
    end
  end

  describe "#state_update" do
    it "merges hash into pending_state_delta with symbol keys" do
      context.state_update("key1" => "val1", :key2 => "val2")
      expect(context.pending_state_delta).to eq(key1: "val1", key2: "val2")
    end

    it "logs debug message" do
      expect(logger).to receive(:debug) do |&block|
        expect(block.call).to include("state_update with hash")
      end
      context.state_update(key: "value")
    end

    context "with non-hash input" do
      it "ignores input and logs warning" do
        expect(logger).to receive(:warn) do |&block|
          expect(block.call).to include("state_update called with non-hash")
        end

        context.state_update("not a hash")
        expect(context.pending_state_delta).to be_empty
      end
    end
  end

  describe "#clear_pending_state_delta!" do
    it "clears the delta" do
      context.state_set(:key, "val")
      expect(context.pending_state_delta).not_to be_empty

      context.clear_pending_state_delta!
      expect(context.pending_state_delta).to be_empty
    end
  end

  describe "#to_h" do
    it "returns expected hash structure" do
      result = context.to_h
      expect(result).to include(
        session_id: session_id,
        user_id: user_id,
        app_name: app_name,
        invocation_id: invocation_id,
        session_service_present: true
      )
    end

    context "without session service" do
      let(:session_service) { nil }

      it "indicates session service is missing" do
        expect(context.to_h[:session_service_present]).to be false
      end
    end
  end
end
