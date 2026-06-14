# File: spec/legate/global_definition_registry_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'legate/global_definition_registry'
require 'legate/agent' # AgentDefinition is in the agent.rb file

RSpec.describe Legate::GlobalDefinitionRegistry do
  # Create a real AgentDefinition for testing
  class TestAgentDefinition < Legate::AgentDefinition
    attr_reader :name

    def initialize(name)
      @name = name
    end

    # Stub other required methods if needed
  end

  before do
    # Clear the registry before each test
    described_class.clear!

    # Allow any logger methods to be called
    allow(Legate.logger).to receive(:error)
    allow(Legate.logger).to receive(:warn)
    allow(Legate.logger).to receive(:debug)
  end

  describe '.register' do
    let(:valid_definition) { TestAgentDefinition.new(:test_agent) }

    it 'registers a valid agent definition' do
      expect(described_class.register(valid_definition)).to be true
      expect(described_class.find(:test_agent)).to eq(valid_definition)
    end

    it 'returns false for non-AgentDefinition objects' do
      invalid_obj = Object.new
      allow(invalid_obj).to receive(:name).and_return(:test_agent)

      expect(Legate.logger).to receive(:error).with(/Invalid object passed to register/)
      expect(described_class.register(invalid_obj)).to be false
    end

    it 'returns false for definitions without a symbol name' do
      invalid_definition = TestAgentDefinition.new('string_name')
      expect(Legate.logger).to receive(:error).with(/Invalid object passed to register/)
      expect(described_class.register(invalid_definition)).to be false
    end

    it 'overwrites existing definitions with the same name' do
      first_definition = TestAgentDefinition.new(:duplicate_name)
      second_definition = TestAgentDefinition.new(:duplicate_name)

      described_class.register(first_definition)
      expect(Legate.logger).to receive(:warn).with(/Overwriting existing definition for agent/)
      described_class.register(second_definition)

      # Should return the second definition
      expect(described_class.find(:duplicate_name)).to eq(second_definition)
    end
  end

  describe '.find' do
    let(:test_definition) { TestAgentDefinition.new(:findable_agent) }

    before do
      described_class.register(test_definition)
    end

    it 'returns the definition for a registered agent' do
      expect(described_class.find(:findable_agent)).to eq(test_definition)
    end

    it 'returns nil for an unregistered agent' do
      expect(described_class.find(:unknown_agent)).to be_nil
    end

    it 'returns nil and logs a warning for non-symbol keys' do
      expect(Legate.logger).to receive(:warn).with(/Find called with non-symbol key/)
      expect(described_class.find('string_key')).to be_nil
    end
  end

  describe '.clear!' do
    it 'removes all registered definitions' do
      # Register some definitions
      definition1 = TestAgentDefinition.new(:agent1)
      definition2 = TestAgentDefinition.new(:agent2)

      described_class.register(definition1)
      described_class.register(definition2)

      # Verify they exist
      expect(described_class.find(:agent1)).to eq(definition1)
      expect(described_class.find(:agent2)).to eq(definition2)

      # Clear the registry
      expect(Legate.logger).to receive(:debug).with('GlobalDefinitionRegistry: Cleared.')
      described_class.clear!

      # Verify they're gone
      expect(described_class.find(:agent1)).to be_nil
      expect(described_class.find(:agent2)).to be_nil
    end
  end

  describe '.all' do
    it 'returns all registered definitions' do
      # Register some definitions
      definition1 = TestAgentDefinition.new(:agent1)
      definition2 = TestAgentDefinition.new(:agent2)

      described_class.register(definition1)
      described_class.register(definition2)

      # Get all definitions
      all_definitions = described_class.all

      # Verify contents
      expect(all_definitions).to be_a(Hash)
      expect(all_definitions.keys).to contain_exactly(:agent1, :agent2)
      expect(all_definitions[:agent1]).to eq(definition1)
      expect(all_definitions[:agent2]).to eq(definition2)
    end

    it 'returns a copy of the registry, not the original' do
      definition = TestAgentDefinition.new(:single_agent)
      described_class.register(definition)

      # Get the registry and modify it
      registry_copy = described_class.all
      registry_copy[:new_key] = 'new value'

      # The original registry should not be modified
      expect(described_class.all.keys).to contain_exactly(:single_agent)
      expect(described_class.all).not_to have_key(:new_key)
    end
  end

  describe '.update_definition atomic validation' do
    let(:definition) do
      Legate::AgentDefinition.new.define do |a|
        a.name :editable_agent
        a.instruction 'Original instruction.'
        a.use_tool :echo
      end
    end

    before { described_class.register(definition) }

    it 'applies a valid field update' do
      expect(described_class.update_definition(:editable_agent, { description: 'A new description' })).to be true
      expect(described_class.find(:editable_agent).description).to eq('A new description')
    end

    it 'rejects and rolls back an update that would leave the definition invalid' do
      # Force validate! to reject the post-update state (e.g. a future invariant);
      # the batch update must be rolled back atomically.
      allow(definition).to receive(:validate!).and_raise(ArgumentError, 'invalid')
      expect(described_class.update_definition(:editable_agent, { instruction: 'changed', description: 'changed' })).to be false
      # The prior valid state is restored (not the rejected values).
      expect(described_class.find(:editable_agent).instruction).to eq('Original instruction.')
    end
  end
end
