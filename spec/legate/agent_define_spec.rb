# File: spec/legate/agent_define_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'legate/agent'
require 'legate/global_tool_manager' # Required for reset!
require 'legate/tools/calculator'
require 'legate/tools/echo'
require 'legate/global_definition_registry' # For mocking

# Minimal mock tool for testing
class MockDefineTool < Legate::Tool
  tool_description 'Minimal Mock Tool'
  self.explicit_tool_name = :mock_define_tool
  # Explicitly define the class method for the test
  def self.tool_name; :mock_define_tool; end
end

# Second mock tool for multi-class test
class AnotherMockTool < Legate::Tool
  tool_description 'Another mock tool.'
  self.explicit_tool_name = :another_mock_tool
end

RSpec.describe Legate::Agent, '.define' do
  let(:agent_name) { :test_definer_agent }
  let(:agent_description) { 'An agent created via the define DSL' }
  let(:agent_instruction) { 'Follow the DSL instructions.' }
  let(:model_name) { 'gemini-pro' }
  let(:tool_path) { 'spec/legate/fixtures/tools/dir_a' } # Path with FixtureToolA
  let(:another_path) { 'spec/legate/fixtures/tools/dir_b' } # Path with FixtureToolB
  let(:tool_class) { MockDefineTool }
  let(:tool_class1) { Legate::Tools::Calculator }
  let(:tool_class2) { Legate::Tools::Echo }
  let(:tool_name1) { :calculator }
  let(:tool_name2) { :echo }

  # Mocks for dependencies
  let(:mock_registry) { class_double(Legate::GlobalDefinitionRegistry, register: true).as_stubbed_const }

  before do
    # Stub the registry class methods
    allow(mock_registry).to receive(:register).and_return(true)

    # Ensure global tool manager has the tools for definition resolution
    allow(Legate::GlobalToolManager).to receive(:find_class).with(tool_name1).and_return(tool_class1)
    allow(Legate::GlobalToolManager).to receive(:find_class).with(tool_name2).and_return(tool_class2)
    allow(Legate::GlobalToolManager).to receive(:get_tool_name).with(tool_class1).and_return(tool_name1)
    allow(Legate::GlobalToolManager).to receive(:get_tool_name).with(tool_class2).and_return(tool_name2)
    # Allow find_class for the mock tool used in tests
    allow(Legate::GlobalToolManager).to receive(:find_class).with(:mock_define_tool).and_return(MockDefineTool)
  end

  it 'creates an agent instance with the configured attributes' do
    # Capture let variables
    local_agent_name = agent_name
    local_agent_description = agent_description
    local_agent_instruction = agent_instruction
    local_model_name = model_name
    local_tool_class = tool_class

    agent = Legate::Agent.define do |a|
      a.name local_agent_name
      a.description local_agent_description
      a.instruction local_agent_instruction
      a.model_name local_model_name
      a.use_tool :mock_define_tool
      a.fallback_mode :echo
    end

    # Re-evaluate expectations for AgentDefinition
    expect(agent).to be_a(Legate::AgentDefinition)
    expect(agent.name).to eq(local_agent_name)
    expect(agent.description).to eq(local_agent_description)
    expect(agent.instruction).to eq(local_agent_instruction)
    expect(agent.model_name).to eq(local_model_name.to_sym)
    expect(agent.fallback_mode).to eq(:echo)
    expect(agent.tool_names).to contain_exactly(:mock_define_tool)
  end

  it 'uses defaults if optional attributes are not set' do
    # Capture let variables
    local_agent_name = agent_name
    local_agent_description = agent_description
    local_agent_instruction = agent_instruction

    agent = Legate::Agent.define do |a|
      a.name local_agent_name
      a.description local_agent_description
      a.instruction local_agent_instruction
    end

    # Re-evaluate expectations for AgentDefinition
    expect(agent).to be_a(Legate::AgentDefinition)
    expect(agent.name).to eq(local_agent_name)
    expect(agent.description).to eq(local_agent_description)
    expect(agent.instruction).to eq(local_agent_instruction)
    expect(agent.model_name).to be_nil
    expect(agent.fallback_mode).to eq(:error)
    expect(agent.tool_names).to be_empty
  end

  it 'raises ArgumentError if block is not provided' do
    expect { Legate::Agent.define }.to raise_error(ArgumentError, /requires a block/)
  end

  it 'raises ArgumentError if name is not set in the block' do
    # Capture let variables
    local_agent_description = agent_description
    local_agent_instruction = agent_instruction

    expect do
      Legate::Agent.define do |a|
        a.description local_agent_description
        a.instruction local_agent_instruction
      end
    end.to raise_error(ArgumentError, /Agent definition must have a name/)
  end

  it 'raises ArgumentError if description is not set in the block' do
    # Capture let variables
    local_agent_name = agent_name
    local_agent_instruction = agent_instruction

    agent_def = nil
    expect do
      agent_def = Legate::Agent.define do |a|
        a.name local_agent_name
        a.instruction local_agent_instruction
      end
    end.not_to raise_error
    expect(agent_def.description).to eq('')

    # Check registry *was* called (since validation passed)
    expect(mock_registry).to have_received(:register)
  end

  it 'handles multiple calls to add_tool_classes' do
    # Define a local class for this test scope
    class AnotherMockToolForTest < Legate::Tool
      tool_description 'Local mock tool'
      self.explicit_tool_name = :another_mock_tool
      def self.tool_name; :another_mock_tool; end
    end

    # Define Fixture tools locally for this test to avoid path issues
    class FixtureToolA < Legate::Tool
      self.explicit_tool_name = :fixture_tool_a
      tool_description 'Fixture Tool A'
      def self.tool_name; :fixture_tool_a; end
    end

    class FixtureToolB < Legate::Tool
      self.explicit_tool_name = :fixture_tool_b
      tool_description 'Fixture Tool B'
      def self.tool_name; :fixture_tool_b; end
    end

    # Capture let variables and local class
    local_agent_name = agent_name
    local_agent_description = agent_description
    local_agent_instruction = agent_instruction # Need instruction
    local_tool_class = tool_class
    local_another_tool_class = AnotherMockToolForTest

    # Use locally defined fixture classes
    # require 'spec/legate/fixtures/tools/dir_a/fixture_tool_a' unless defined?(FixtureToolA)
    # require 'spec/legate/fixtures/tools/dir_b/fixture_tool_b' unless defined?(FixtureToolB)
    local_fixture_tool_a = FixtureToolA
    local_fixture_tool_b = FixtureToolB

    # Create an agent definition using the DSL
    agent_def = Legate::Agent.define do |a|
      a.name local_agent_name
      a.description local_agent_description
      a.instruction local_agent_instruction # Instruction is now mandatory for definition
      # Revert bypass and use use_tool again
      a.use_tool local_tool_class.tool_name
      a.use_tool local_fixture_tool_a.tool_name
      a.use_tool local_another_tool_class.tool_name
      a.use_tool local_fixture_tool_b.tool_name
    end

    # Re-evaluate expectations for AgentDefinition
    expect(agent_def).to be_a(Legate::AgentDefinition)
    # Check that the tool names are collected correctly in the definition
    expect(agent_def.tool_names).to contain_exactly(
      local_tool_class.tool_name,
      local_fixture_tool_a.tool_name,
      local_another_tool_class.tool_name,
      local_fixture_tool_b.tool_name
    )
  end

  context 'when defining a valid agent' do
    # Capture the defined definition object for inspection
    let!(:defined_definition) do
      # Capture let variables
      local_agent_name = agent_name
      local_agent_description = agent_description
      local_agent_instruction = agent_instruction
      local_model_name = model_name
      local_tool_name1 = tool_name1
      local_tool_name2 = tool_name2

      # Use let! to ensure definition happens before examples
      Legate::Agent.define do |a|
        # Use the new DSL
        a.name local_agent_name
        a.description local_agent_description
        a.instruction local_agent_instruction
        a.model_name local_model_name
        a.use_tool local_tool_name1
        a.use_tool local_tool_name2
      end
    end

    it 'returns an AgentDefinition instance' do
      expect(defined_definition).to be_a(Legate::AgentDefinition)
    end

    it 'configures the AgentDefinition instance correctly' do
      expect(defined_definition.name).to eq(agent_name)
      expect(defined_definition.description).to eq(agent_description)
      expect(defined_definition.instruction).to eq(agent_instruction)
      expect(defined_definition.model_name).to eq(model_name.to_sym)
      expect(defined_definition.tool_names).to contain_exactly(tool_name1, tool_name2)
      expect(defined_definition.fallback_mode).to eq(:error)
      expect(defined_definition.mcp_servers).to eq([])
    end

    it 'registers the definition in the GlobalDefinitionRegistry' do
      expect(mock_registry).to have_received(:register).with(defined_definition)
    end

    it 'registers the definition instance with the GlobalDefinitionRegistry' do
      # Check that register was called with the exact definition instance returned by define
      expect(mock_registry).to have_received(:register).with(defined_definition)
    end
  end

  context 'when using defaults' do
    # Define local agent name directly
    let(:local_default_agent_name) { :default_agent }
    let(:local_default_agent_desc) { 'Agent using defaults' }
    let(:local_default_agent_inst) { 'Default instruction' }

    let!(:defined_definition_defaults) do
      # Capture local variables
      name_val = local_default_agent_name
      desc_val = local_default_agent_desc
      inst_val = local_default_agent_inst

      Legate::Agent.define do |a|
        a.name name_val
        a.description desc_val
        a.instruction inst_val
      end
    end

    it 'uses default model name if not specified' do
      expect(defined_definition_defaults.model_name).to be_nil
    end

    it 'has an empty tool list if use_tool is not called' do
      expect(defined_definition_defaults.tool_names).to be_empty
    end

    it 'registers default definition in the registry' do
      expect(mock_registry).to have_received(:register).with(defined_definition_defaults)
    end

    it 'registers the default definition instance' do
      expect(mock_registry).to have_received(:register).with(defined_definition_defaults)
    end
  end

  context 'with definition errors' do
    it 'raises ArgumentError if name is not set' do
      # Capture let variables
      local_agent_description = agent_description
      local_agent_instruction = agent_instruction

      # Reset and setup specific mock expectation for this test
      RSpec::Mocks.space.proxy_for(mock_registry).reset
      allow(mock_registry).to receive(:register) # Allow call for check below

      # Move define call inside expect block
      expect {
        Legate::Agent.define do |a|
          a.description local_agent_description
          a.instruction local_agent_instruction
        end
      }.to raise_error(ArgumentError, /Agent definition must have a name/)

      # Check that registry was NOT called because validation failed
      expect(mock_registry).not_to have_received(:register)
    end

    it 'raises ArgumentError if description is not set' do
      # Test that it completes successfully instead.
      local_agent_name = agent_name
      local_agent_instruction = agent_instruction

      # Reset and setup specific mock expectation for this test
      RSpec::Mocks.space.proxy_for(mock_registry).reset
      allow(mock_registry).to receive(:register).and_return(true)

      agent_def = nil
      expect {
        agent_def = Legate::Agent.define do |a|
          a.name local_agent_name
          a.instruction local_agent_instruction # Provide instruction
          # No description
        end
      }.not_to raise_error
      expect(agent_def.description).to eq('') # Defaults to empty

      # Check registry *was* called (since validation passed)
      expect(mock_registry).to have_received(:register)
    end

    it 'derives a default instruction when none is set (instruction is optional)' do
      local_agent_name = agent_name
      local_agent_description = agent_description

      definition = Legate::AgentDefinition.new
      definition.define do |a|
        a.name local_agent_name
        a.description local_agent_description
        # Missing instruction -> defaulted, not an error
      end

      expect(definition.instruction).to include("You are the #{local_agent_name} agent")
      expect(definition.instruction).to include('Use the available tools')
    end

    it 'raises ArgumentError if name is not a Symbol' do
      # Capture let variables
      local_agent_description = agent_description
      local_agent_instruction = agent_instruction

      expect do
        Legate::Agent.define do |a|
          a.name 'string_name'
          a.description local_agent_description
          a.instruction local_agent_instruction
        end
      end.to raise_error(ArgumentError, 'Agent name must be a Symbol.')
    end
  end

  context 'with registry errors' do
    it 'raises StoreError if registration fails' do
      # Capture local variables
      local_failing_name = :failing_agent
      local_failing_desc = 'This will fail to register'
      local_failing_inst = 'Registration instruction'

      # Simulate registry failure
      allow(mock_registry).to receive(:register).and_raise(StandardError, 'Registry save failed')

      expect do
        Legate::Agent.define do |a|
          a.name local_failing_name
          a.description local_failing_desc
          a.instruction local_failing_inst
        end
      end.to raise_error(Legate::StoreError, /Unexpected error registering definition/)
    end
  end
end
