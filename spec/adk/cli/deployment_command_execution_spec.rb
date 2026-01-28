# frozen_string_literal: true

require 'spec_helper'
require 'adk/cli/deployment_commands'

RSpec.describe ADK::CLI::DeploymentCommands do
  let(:commands) { described_class.new }
  let(:output) { StringIO.new }
  let(:shell) { Thor::Shell::Basic.new }

  before do
    allow(shell).to receive(:stdout).and_return(output)
    allow(shell).to receive(:stderr).and_return(output)
    commands.shell = shell
  end

  describe '#run_gcloud_command (private)' do
    it 'safely executes commands with array arguments avoiding shell injection' do
      malicious_arg = 'foo; rm -rf /'
      args = ['config', 'set', 'project', malicious_arg]

      # We expect Open3.capture2e to receive the command and args as separate parameters
      # NOT as a single string joined by spaces. This ensures the malicious arg is treated
      # as a single argument to the command, not interpreted by the shell.
      expect(Open3).to receive(:capture2e)
        .with('gcloud', 'config', 'set', 'project', malicious_arg)
        .and_return(['', double(success?: true)])

      # Call the private method
      commands.send(:run_gcloud_command, args, 'Error message')
    end

    it 'handles string arguments by splitting them (legacy support)' do
      # If a string is passed, it should still split it.
      args = 'config list'
      expect(Open3).to receive(:capture2e)
        .with('gcloud', 'config', 'list')
        .and_return(['', double(success?: true)])

      commands.send(:run_gcloud_command, args, 'Error message')
    end
  end
end
