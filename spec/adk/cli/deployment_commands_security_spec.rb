# frozen_string_literal: true

require 'spec_helper'
require 'adk/cli/deployment_commands'
require 'open3'

RSpec.describe ADK::CLI::DeploymentCommands do
  let(:commands) { described_class.new }
  let(:output) { StringIO.new }
  let(:shell) { Thor::Shell::Basic.new }

  before do
    allow(shell).to receive(:stdout).and_return(output)
    allow(shell).to receive(:stderr).and_return(output)
    commands.shell = shell
  end

  describe '#run_gcloud_command (security fix)' do
    it 'uses Open3.capture2e with array arguments to prevent injection' do
      args = ['config', 'set', 'project', 'my-project']

      # Expect Open3.capture2e to be called with 'gcloud' and the args splatted
      # This ensures we are avoiding shell interpolation
      expect(Open3).to receive(:capture2e).with('gcloud', *args).and_return(['', double(success?: true)])

      # We need to send the method call because it is private
      # Note: We are passing an array, assuming we will refactor the method to accept an array
      commands.send(:run_gcloud_command, args, "Error message")
    end
  end

  describe '#create_gcloud_config (security fix)' do
    it 'passes array arguments to run_gcloud_command' do
      # We need to allow system check for gcloud presence
      # This line in the original code is safe as it is constant string
      allow(commands).to receive(:system).with('command -v gcloud > /dev/null 2>&1').and_return(true)

      # config_name for 'test-app' will be 'adk-deploy-test-app'
      config_name = 'adk-deploy-test-app'

      # Expect the 'describe' command to now use Open3 instead of backticks
      expect(Open3).to receive(:capture2e).with('gcloud', 'config', 'configurations', 'describe', config_name).and_return(['', double(success?: false)])

      # Expect run_gcloud_command calls with arrays (checking that we updated the calls)

      # 1. create
      # We can't easily mock run_gcloud_command here if we are testing its implementation in integration,
      # but since we want to verify the arguments passed TO it by create_gcloud_config:
      expect(commands).to receive(:run_gcloud_command).with(
        ['config', 'configurations', 'create', config_name, '--no-activate'],
        anything
      ).and_return(true)

      # 2. set project
      expect(commands).to receive(:run_gcloud_command).with(
        ['config', 'set', 'project', 'my-project', "--configuration=#{config_name}"],
        anything
      ).and_return(true)

      # 3. set region
      expect(commands).to receive(:run_gcloud_command).with(
        ['config', 'set', 'compute/region', 'us-central1', "--configuration=#{config_name}"],
        anything
      ).and_return(true)

      commands.send(:create_gcloud_config, 'test-app', 'my-project', 'us-central1')
    end
  end
end
