# File: spec/adk/agent_define_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/agent'
require 'adk/global_tool_manager' # Required for reset!

# Minimal mock tool for testing
class MockDefineTool < ADK::Tool
  tool_description "A mock tool for define specs."
  self.explicit_tool_name = :mock_define_tool # Use explicit name
end

# Second mock tool for multi-class test
class AnotherMockTool < ADK::Tool
  tool_description "Another mock tool."
  self.explicit_tool_name = :another_mock_tool
end

RSpec.describe ADK::Agent, ".define" do
  let(:agent_name) { "defined_agent" }
  let(:agent_description) { "Agent created via define block." }
  let(:model_name) { "gemini-test-define" }
  let(:tool_path) { 'spec/adk/fixtures/tools/dir_a' } # Path with FixtureToolA
  let(:another_path) { 'spec/adk/fixtures/tools/dir_b' } # Path with FixtureToolB
  let(:tool_class) { MockDefineTool }
  let(:another_tool_class) { AnotherMockTool }

  it "creates an agent instance with the configured attributes" do
    agent = ADK::Agent.define do |a|
      a.name = agent_name
      a.description = agent_description
      a.model_name = model_name
      a.discover_tools_in tool_path
      a.add_tool_classes tool_class
      a.fallback_mode = :echo
    end

    expect(agent).to be_an_instance_of(ADK::Agent)
    expect(agent.name).to eq(agent_name)
    expect(agent.description).to eq(agent_description)
    expect(agent.model_name).to eq(model_name)
    expect(agent.fallback_mode).to eq(:echo)

    expect(agent.find_tool_class(:mock_define_tool)).to eq(tool_class) # From tool_class
  end

  it "uses defaults if optional attributes are not set" do
    agent = ADK::Agent.define do |a|
      a.name = agent_name
      a.description = agent_description
      # model_name, fallback_mode, tools etc. not set
    end

    expect(agent.model_name).to eq(ADK::Agent::DEFAULT_MODEL)
    expect(agent.fallback_mode).to eq(:error) # Default fallback
  end

  it "raises ArgumentError if block is not provided" do
    expect { ADK::Agent.define }.to raise_error(ArgumentError, /requires a block/)
  end

  it "raises ArgumentError if name is not set in the block" do
    expect do
      ADK::Agent.define do |a|
        a.description = agent_description
      end
    end.to raise_error(ArgumentError, /Agent name must be set/)
  end

  it "raises ArgumentError if description is not set in the block" do
    expect do
      ADK::Agent.define do |a|
        a.name = agent_name
      end
    end.to raise_error(ArgumentError, /Agent description must be set/)
  end

  xit "handles multiple calls to discover_tools_in and add_tool_classes" do
    agent = ADK::Agent.define do |a|
      a.name = agent_name
      a.description = agent_description
      a.discover_tools_in tool_path
      a.add_tool_classes tool_class
      a.discover_tools_in another_path
      a.add_tool_classes another_tool_class # Use let variable
    end

    expect(agent.find_tool_class(:fixture_tool_a)).not_to be_nil
    expect(agent.find_tool_class(:fixture_tool_b)).not_to be_nil # Assuming dir_b/tool_b.rb defines :fixture_tool_b
    expect(agent.find_tool_class(:mock_define_tool)).to eq(tool_class)
    expect(agent.find_tool_class(:another_mock_tool)).to eq(another_tool_class)
  end
end
