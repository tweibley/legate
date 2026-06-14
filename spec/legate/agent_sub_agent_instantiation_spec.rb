# frozen_string_literal: true

# Regression coverage for name-based sub-agent instantiation.
#
# Agent#instantiate_sub_agents_from_definition looks each declared sub-agent
# name up in the GlobalDefinitionRegistry. It previously called a non-existent
# `.get` method; the NoMethodError was swallowed by a broad rescue, so an agent
# declared with sub_agents_define(:child) silently came up with zero
# sub-agents. This spec drives the REAL registry (no stubbing of the lookup, the
# very thing that hid the bug) and asserts the child is actually instantiated.
require 'spec_helper'
require 'legate/agent'

RSpec.describe 'Legate::Agent name-based sub-agent instantiation' do
  before do
    Legate::GlobalDefinitionRegistry.clear!
    Legate.config.session_service = Legate::SessionService::InMemory.new
  end

  after { Legate::GlobalDefinitionRegistry.clear! }

  it 'instantiates a sub-agent declared by name from the registry' do
    child_def = Legate::AgentDefinition.new.define do |a|
      a.name :child_agent
      a.description 'A child agent.'
      a.instruction 'You are the child.'
      a.use_tool :echo
    end

    parent_def = Legate::AgentDefinition.new.define do |a|
      a.name :parent_agent
      a.description 'A parent agent.'
      a.instruction 'You are the parent.'
      a.use_tool :echo
      a.sub_agents_define :child_agent
    end

    # The child is resolved by name from the registry during instantiation,
    # so it must be registered there (AgentDefinition#define does not register).
    Legate::GlobalDefinitionRegistry.register(child_def)
    expect(Legate::GlobalDefinitionRegistry.find(:child_agent)).to eq(child_def)

    parent = Legate::Agent.new(definition: parent_def)

    expect(parent.sub_agents.map(&:name)).to contain_exactly(:child_agent)
    expect(parent.sub_agents.first.parent_agent).to eq(parent)
  end
end
