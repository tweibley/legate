# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legate::Agent do
  describe 'basic functionality' do
    let(:agent_definition) do
      Legate::AgentDefinition.new.define do |a|
        a.name :test_agent
        a.description 'Test agent'
        a.instruction 'You are a test agent'
        a.fallback_mode :error
      end
    end

    it 'can be instantiated' do
      agent = described_class.new(definition: agent_definition)
      expect(agent).to be_a(described_class)
      expect(agent.name).to eq(:test_agent)
    end
  end
end
