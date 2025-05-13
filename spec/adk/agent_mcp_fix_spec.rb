# frozen_string_literal: true

require 'spec_helper'
require 'adk/agent'
require 'adk/tool_registry'
require 'adk/session_service/redis'

RSpec.describe 'Agent MCP Fix' do
  describe 'MCP servers handling' do
    # Create a mock tool class for testing
    class TestTool < ADK::Tool
      def self.tool_metadata
        { name: :test_tool }
      end
    end

    before do
      # Suppress logs for cleaner test output
      allow(ADK).to receive(:logger).and_return(
        instance_double(Logger, debug: nil, info: nil, warn: nil, error: nil)
      )
    end

    it 'handles nil mcp_servers gracefully' do
      # Use minimal concrete objects to avoid mock expectations issues
      session_service = instance_double(ADK::SessionService::Redis)
      allow(session_service).to receive(:get_session)
      allow(session_service).to receive(:append_event)

      agent_def = ADK::AgentDefinition.new.define do |d|
        d.name :test_agent
        d.description 'Test agent'
        d.instruction 'Test instruction'
        d.model_name 'gemini-pro'
        # mcp_servers defaults to [] in AgentDefinition,
        # but this test specifically checks behavior when it's nil.
        # We will stub it to return nil after creation.
        d.webhook_enabled true # Assuming this is a valid attribute to set
      end
      # Stub mcp_servers to return nil for this specific test case.
      allow(agent_def).to receive(:mcp_servers).and_return(nil)

      # Allow configuration
      allow(ADK).to receive(:config).and_return(
        instance_double(ADK::Configuration,
                        session_service: session_service,
                        definition_store: instance_double(ADK::DefinitionStore::RedisStore, get_definition: {}))
      )

      # Mock planner to respond to plan
      planner = instance_double(ADK::Planner)
      allow(ADK::Planner).to receive(:new).and_return(planner)
      allow(planner).to receive(:plan)
      allow(planner).to receive(:respond_to?).with(:plan).and_return(true)

      # Should not raise an error
      agent = nil
      expect {
        agent = ADK::Agent.new(definition: agent_def, session_service: session_service)
        # Don't actually call start/stop since that requires more mocking
      }.not_to raise_error

      # Test specific connect_mcp_servers method without the agent.start wrapper
      expect {
        agent.send(:connect_mcp_servers)
      }.not_to raise_error
    end

    it 'handles empty mcp_servers array gracefully' do
      # Use minimal concrete objects to avoid mock expectations issues
      session_service = instance_double(ADK::SessionService::Redis)
      allow(session_service).to receive(:get_session)
      allow(session_service).to receive(:append_event)

      agent_def = ADK::AgentDefinition.new.define do |d|
        d.name :test_agent
        d.description 'Test agent'
        d.instruction 'Test instruction'
        d.model_name 'gemini-pro'
        d.mcp_servers [] # Explicitly set to empty array
        d.webhook_enabled true # Assuming this is a valid attribute to set
      end

      # Allow configuration
      allow(ADK).to receive(:config).and_return(
        instance_double(ADK::Configuration,
                        session_service: session_service,
                        definition_store: instance_double(ADK::DefinitionStore::RedisStore, get_definition: {}))
      )

      # Mock planner to respond to plan
      planner = instance_double(ADK::Planner)
      allow(ADK::Planner).to receive(:new).and_return(planner)
      allow(planner).to receive(:plan)
      allow(planner).to receive(:respond_to?).with(:plan).and_return(true)

      # Should not raise an error
      agent = nil
      expect {
        agent = ADK::Agent.new(definition: agent_def, session_service: session_service)
        # Don't actually call start/stop since that requires more mocking
      }.not_to raise_error

      # Test specific connect_mcp_servers method without the agent.start wrapper
      expect {
        agent.send(:connect_mcp_servers)
      }.not_to raise_error
    end
  end
end
