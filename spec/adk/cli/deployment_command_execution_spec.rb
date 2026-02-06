require 'spec_helper'
require 'adk/cli/deployment_commands'

RSpec.describe ADK::CLI::DeploymentCommands do
  let(:commands) { described_class.new }

  describe '#run_gcloud_command' do
    it 'executes gcloud command securely' do
      # We want to verify that Open3.capture2e is used instead of backticks
      # mocking Open3 to verify arguments
      allow(Open3).to receive(:capture2e).and_return(['', double(success?: true)])

      # We need to call the private method
      commands.send(:run_gcloud_command, 'info', error_message: 'Error message')

      expect(Open3).to have_received(:capture2e).with('gcloud', 'info')
    end

    it 'executes gcloud command with multiple arguments securely' do
      allow(Open3).to receive(:capture2e).and_return(['', double(success?: true)])

      commands.send(:run_gcloud_command, 'config', 'set', 'project', 'my-project', error_message: 'Error message')

      expect(Open3).to have_received(:capture2e).with('gcloud', 'config', 'set', 'project', 'my-project')
    end
  end
end
