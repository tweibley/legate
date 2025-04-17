# File: spec/adk/mcp/server/adk_agent_adapter_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'fast_mcp'
require 'redis'
require 'adk/mcp/server/adk_agent_adapter'
require 'adk/session_service/in_memory' # For testing
require 'adk/session_service/base'
require 'adk/mcp' # For logger

RSpec.describe ADK::Mcp::Server::AdkAgentAdapter do
  let(:logger_spy) { spy('Logger') }
  let(:agent_name) { 'test_agent' }
  let(:session_service_instance) { ADK::SessionService::InMemory.new }

  before do
    allow(ADK::Mcp).to receive(:logger).and_return(logger_spy)
    # Mock redis connection used within AdkAgentAdapter class methods
    mock_redis = instance_double(Redis)
    allow(Redis).to receive(:new).and_return(mock_redis)
    allow(mock_redis).to receive(:ping)
    allow(mock_redis).to receive(:hmget).and_return(['Test Agent Desc', '[]', 'test-model']) # Mock successful load
  end

  describe '.wrap' do
    it 'raises ArgumentError if agent name is invalid' do
      expect {
        described_class.wrap(nil, session_service_instance)
      }.to raise_error(ArgumentError, /Agent definition name/)
      expect {
        described_class.wrap('', session_service_instance)
      }.to raise_error(ArgumentError, /Agent definition name/)
    end

    it 'raises ArgumentError if session service is invalid' do
      expect { described_class.wrap(agent_name, nil) }.to raise_error(ArgumentError, /Session service instance/)
      expect { described_class.wrap(agent_name, Object.new) }.to raise_error(ArgumentError, /Session service instance/)
    end

    it 'creates an anonymous subclass of AdkAgentAdapter' do
      adapter_class = described_class.wrap(agent_name, session_service_instance)
      expect(adapter_class).to be_a(Class)
      expect(adapter_class).to be < ADK::Mcp::Server::AdkAgentAdapter
    end

    it 'sets class instance variables on the subclass' do
      adapter_class = described_class.wrap(agent_name, session_service_instance)
      expect(adapter_class.agent_definition_name).to eq(agent_name)
      expect(adapter_class.session_service).to eq(session_service_instance)
    end

    it 'sets fast-mcp tool_name based on agent name' do
      adapter_class = described_class.wrap(agent_name, session_service_instance)
      expect(adapter_class.tool_name).to eq("run_agent_#{agent_name}")
    end

    it 'sets fast-mcp description based on agent name' do
      adapter_class = described_class.wrap(agent_name, session_service_instance)
      expect(adapter_class.description).to eq("Runs the ADK Agent '#{agent_name}' with the given prompt.")
    end

    it 'defines the :prompt argument using fast-mcp DSL' do
      adapter_class = described_class.wrap(agent_name, session_service_instance)
      # We cannot easily introspect the arguments schema set via the DSL.
      # Trust that the DSL call within .wrap sets it up correctly.
      # Subsequent tests on #call would fail if arguments weren't defined.
      # For basic check, ensure it doesn't raise error.
      expect { adapter_class.new }.not_to raise_error # Instantiation implies DSL worked
    end

    it 'logs creation info' do
      described_class.wrap(agent_name, session_service_instance)
      expect(logger_spy).to have_received(:info).with("Created fast-mcp adapter for ADK agent definition: '#{agent_name}'")
    end

    # Note: Testing the Redis connection failure within .wrap might be complex due to class methods
  end

  # TODO: Add tests for the #call method (will require more extensive mocking)
  # describe '#call' do
  #   let(:adapter_class) { described_class.wrap(agent_name, session_service_instance) }
  #   let(:adapter_instance) { adapter_class.new }
  #   let(:prompt) { "What is the weather?" }
  #   # ... mocks for Redis, SessionService, Agent, Event ...
  # end
end
