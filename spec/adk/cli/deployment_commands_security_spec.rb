# frozen_string_literal: true

require 'spec_helper'
require 'adk/cli/deployment_commands'
require 'open3'

RSpec.describe ADK::CLI::DeploymentCommands do
  let(:cli) { described_class.new }

  # We need to expose private methods for testing
  before do
    described_class.send(:public, :run_gcloud_command)
    described_class.send(:public, :create_gcloud_config)
  end

  describe '#run_gcloud_command' do
    it 'uses Open3.capture2e with array arguments when passed an array (SAFE)' do
      command_args = %w[config set project my-project]

      # We expect Open3.capture2e to be called with separate arguments
      expect(Open3).to receive(:capture2e).with('gcloud', *command_args).and_return(['output', double(success?: true)])

      allow(cli).to receive(:say)

      cli.run_gcloud_command(command_args, 'Error')
    end

    it 'uses Open3.capture2e with Shellwords split when passed a string (SAFE fallback)' do
      command_str = "config set project 'my-project'"
      # Shellwords should split this into ['config', 'set', 'project', 'my-project']

      expect(Open3).to receive(:capture2e).with('gcloud', 'config', 'set', 'project', 'my-project').and_return(['output', double(success?: true)])

      allow(cli).to receive(:say)

      cli.run_gcloud_command(command_str, 'Error')
    end
  end
end
