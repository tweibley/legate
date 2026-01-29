# frozen_string_literal: true

require 'spec_helper'
require 'adk/cli/agent_commands'
require 'adk/agent_definition_store'
require 'thor/shell/basic'

RSpec.describe ADK::CLI::AgentCommands do
  let(:commands) { described_class.new }
  let(:output) { StringIO.new }
  let(:shell) { Thor::Shell::Basic.new }

  before do
    allow(shell).to receive(:stdout).and_return(output)
    allow(shell).to receive(:stderr).and_return(output)
    commands.shell = shell

    # Stub Redis to avoid actual connection
    redis_mock = instance_double(Redis)
    allow(Redis).to receive(:new).and_return(redis_mock)
    allow(redis_mock).to receive(:close)
    allow(redis_mock).to receive(:smembers).with(ADK::AgentDefinitionStore::REDIS_AGENTS_SET_KEY).and_return(['my_agent', 'test_agent'])

    # Stub finding the specific agent to return nil (not found)
    allow(ADK::AgentDefinitionStore).to receive(:load_from_redis).with(:my_agnte).and_return(nil)
    allow(ADK::AgentDefinitionStore).to receive(:find).with(:my_agnte).and_return(nil)

    # Prevent exit(1) from stopping the test suite, but allow checking for it
    allow(commands).to receive(:exit).with(1).and_raise(SystemExit)
  end

  describe '#status' do
    it 'suggests the correct agent name when a typo is made' do
      expect {
        commands.status('my_agnte')
      }.to raise_error(SystemExit)

      expect(output.string).to include("Agent definition 'my_agnte' not found.")
      # This is the UX improvement we want to see
      expect(output.string).to include("Did you mean 'my_agent'?")
    end
  end
end
