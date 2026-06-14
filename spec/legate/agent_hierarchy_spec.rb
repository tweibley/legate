# frozen_string_literal: true

# File: spec/legate/agent_hierarchy_spec.rb
require 'spec_helper'
require 'legate/agent'
require 'legate/planner'
require 'legate/tool_registry'
require 'legate/session'
require 'legate/session_service/in_memory'
require 'legate/event'

RSpec.describe 'Legate::Agent Hierarchy Methods' do
  let(:logger_double) { spy('Logger') }
  let(:session_service_double) { instance_double(Legate::SessionService::InMemory, get_session: nil, append_event: true) }

  before do
    # Global mock setup
    allow(Legate).to receive(:logger).and_return(logger_double)
    allow(Legate).to receive_message_chain(:config, :session_service).and_return(session_service_double)
  end

  # Helper method to create an agent with a specific name
  def create_agent_with_name(name, parent = nil)
    # Create a real definition object instead of a mock
    definition = Legate::AgentDefinition.new
    definition.define do |p|
      p.name name
      p.description "Agent #{name}"
      p.instruction "You are agent #{name}"
      p.model_name 'test-model'
      p.fallback_mode :error
    end

    # Create the agent with the real definition
    agent = Legate::Agent.new(definition: definition, session_service: session_service_double)

    # Set parent if provided
    if parent
      agent.instance_variable_set(:@parent_agent, parent)
      parent.instance_variable_get(:@sub_agents) << agent
    end

    agent
  end

  describe '#root_agent' do
    context 'when agent has no parent' do
      it 'returns self' do
        agent = create_agent_with_name(:root_agent)
        expect(agent.root_agent).to eq(agent)
      end
    end

    context 'when agent has a parent' do
      it 'returns the parent' do
        root = create_agent_with_name(:root_agent)
        child = create_agent_with_name(:child_agent, root)

        expect(child.root_agent).to eq(root)
      end
    end

    context 'with deep hierarchy' do
      it 'returns the topmost ancestor' do
        root = create_agent_with_name(:root_agent)
        level1 = create_agent_with_name(:level1_agent, root)
        level2 = create_agent_with_name(:level2_agent, level1)
        level3 = create_agent_with_name(:level3_agent, level2)

        expect(level3.root_agent).to eq(root)
      end
    end
  end

  describe '#find_agent' do
    context 'when searching for self' do
      it 'returns self when name matches' do
        agent = create_agent_with_name(:test_agent)
        expect(agent.find_agent(:test_agent)).to eq(agent)
      end

      it 'converts string name to symbol' do
        agent = create_agent_with_name(:test_agent)
        expect(agent.find_agent('test_agent')).to eq(agent)
      end
    end

    context 'with simple hierarchy' do
      let(:root) { create_agent_with_name(:root_agent) }
      let(:child1) { create_agent_with_name(:child1, root) }
      let(:child2) { create_agent_with_name(:child2, root) }

      before do
        # Force initialization of all agents to set up hierarchy
        root
        child1
        child2
      end

      it 'finds direct sub-agents' do
        expect(root.find_agent(:child1)).to eq(child1)
        expect(root.find_agent(:child2)).to eq(child2)
      end

      it 'returns nil when agent not found' do
        expect(root.find_agent(:nonexistent)).to be_nil
      end
    end

    context 'with complex hierarchy' do
      let(:root) { create_agent_with_name(:root_agent) }
      let(:branch1) { create_agent_with_name(:branch1, root) }
      let(:branch2) { create_agent_with_name(:branch2, root) }
      let(:leaf1) { create_agent_with_name(:leaf1, branch1) }
      let(:leaf2) { create_agent_with_name(:leaf2, branch1) }
      let(:leaf3) { create_agent_with_name(:leaf3, branch2) }

      before do
        # Force initialization of all agents to set up hierarchy
        root
        branch1
        branch2
        leaf1
        leaf2
        leaf3
      end

      it 'finds deeply nested agents' do
        expect(root.find_agent(:leaf1)).to eq(leaf1)
        expect(root.find_agent(:leaf3)).to eq(leaf3)
      end

      it 'returns the first matching agent in DFS order' do
        # Create another agent with the same name in a different branch
        duplicate_leaf = create_agent_with_name(:leaf1, branch2)

        # Root should find the first one (in branch1)
        expect(root.find_agent(:leaf1)).to eq(leaf1)
        expect(root.find_agent(:leaf1)).not_to eq(duplicate_leaf)
      end

      it 'can find agents via middle nodes' do
        expect(branch1.find_agent(:leaf2)).to eq(leaf2)
        expect(branch2.find_agent(:leaf3)).to eq(leaf3)
      end

      it 'cannot find agents in other branches' do
        expect(branch1.find_agent(:leaf3)).to be_nil
        expect(branch2.find_agent(:leaf1)).to be_nil
      end
    end
  end

  describe '#find_sub_agent' do
    let(:root) { create_agent_with_name(:root_agent) }
    let(:child1) { create_agent_with_name(:child1, root) }
    let(:child2) { create_agent_with_name(:child2, root) }
    let(:grandchild) { create_agent_with_name(:grandchild, child1) }

    before do
      # Force initialization of all agents to set up hierarchy
      root
      child1
      child2
      grandchild
    end

    it 'finds direct sub-agents' do
      expect(root.find_sub_agent(:child1)).to eq(child1)
      expect(root.find_sub_agent(:child2)).to eq(child2)
    end

    it 'converts string names to symbols' do
      expect(root.find_sub_agent('child1')).to eq(child1)
    end

    it 'does not find deeply nested agents' do
      expect(root.find_sub_agent(:grandchild)).to be_nil
    end

    it 'returns nil when agent not found' do
      expect(root.find_sub_agent(:nonexistent)).to be_nil
    end
  end
end
