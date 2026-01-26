# frozen_string_literal: true

require 'spec_helper'
require 'adk/cli/deployment_commands'
require 'open3'

RSpec.describe ADK::CLI::DeploymentCommands do
  let(:commands) { described_class.new }
  let(:shell) { Thor::Shell::Basic.new }
  let(:output) { StringIO.new }

  before do
    allow(shell).to receive(:stdout).and_return(output)
    allow(shell).to receive(:stderr).and_return(output)
    commands.shell = shell

    # Mock system commands to check for existence
    allow(commands).to receive(:system).with('command -v gcloud > /dev/null 2>&1').and_return(true)
  end

  describe '#create_gcloud_config' do
    let(:project_id) { 'my-project-id' }
    let(:region) { 'us-central1' }
    let(:base_name) { 'test-app' }

    # Since create_gcloud_config is private, we access it via send or instance_exec for testing
    # verifying that it calls run_gcloud_command correctly is the goal.

    it 'calls run_gcloud_command with array arguments preventing injection' do
      # We intercept the Open3 calls to verify arguments
      allow(Open3).to receive(:capture2e).and_return(['', double(success?: true)])

      # Mock the check for existing config to return false (not found) so it proceeds to create
      # The logic currently uses backticks for this check, which we plan to replace.
      # We'll assume the refactored version uses Open3 for this too.
      allow(Open3).to receive(:capture2e).with('gcloud', 'config', 'configurations', 'describe', anything).and_return(['', double(success?: false)])

      # Expect creation call
      expect(Open3).to receive(:capture2e).with(
        'gcloud', 'config', 'configurations', 'create', anything, '--no-activate'
      ).and_return(['', double(success?: true)])

      # Expect project set call
      expect(Open3).to receive(:capture2e).with(
        'gcloud', 'config', 'set', 'project', project_id, '--configuration=adk-deploy-test-app'
      ).and_return(['', double(success?: true)])

      # Expect region set call
      expect(Open3).to receive(:capture2e).with(
        'gcloud', 'config', 'set', 'compute/region', region, '--configuration=adk-deploy-test-app'
      ).and_return(['', double(success?: true)])

      commands.send(:create_gcloud_config, base_name, project_id, region)
    end

    it 'safely handles malicious input in project_id' do
      malicious_project_id = 'id; rm -rf /'

      allow(Open3).to receive(:capture2e).and_return(['', double(success?: true)])
      allow(Open3).to receive(:capture2e).with('gcloud', 'config', 'configurations', 'describe', anything).and_return(['', double(success?: false)])

      # The key verification: The malicious string is passed as a single argument, NOT interpolated into a shell string
      expect(Open3).to receive(:capture2e).with(
        'gcloud', 'config', 'set', 'project', malicious_project_id, anything
      ).and_return(['', double(success?: true)])

      commands.send(:create_gcloud_config, base_name, malicious_project_id, region)
    end
  end

  describe '#run_gcloud_command' do
    it 'executes command using Open3 with array arguments' do
      args = ['config', 'list']
      status_mock = double(success?: true)

      expect(Open3).to receive(:capture2e).with('gcloud', *args).and_return(['output', status_mock])

      commands.send(:run_gcloud_command, args, 'Error message')
    end

    it 'returns false and logs error on failure' do
      args = ['config', 'list']
      status_mock = double(success?: false)
      error_output = 'Detailed error info'

      expect(Open3).to receive(:capture2e).with('gcloud', *args).and_return([error_output, status_mock])

      result = commands.send(:run_gcloud_command, args, 'Custom error message')

      expect(result).to be false
      expect(output.string).to include('Error: Custom error message')
      expect(output.string).to include(error_output)
    end
  end
end
