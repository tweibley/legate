# frozen_string_literal: true

require 'spec_helper'
require 'adk/cli/deployment_commands'
require 'open3'

RSpec.describe ADK::CLI::DeploymentCommands do
  let(:cli) { described_class.new }

  describe 'Command Injection Vulnerability' do
    it 'executes gcloud commands safely using Open3.capture2e with array arguments' do
      project_id = 'foo; echo injected'
      config_name = 'adk-deploy-base' # Expected sanitized name from "base"
      region = 'region'

      # We assume the user input for project_id is malicious.
      # The refactored code should pass this as a single argument to Open3.capture2e,
      # preventing shell injection.

      # Mock system to bypass "command -v gcloud" check
      allow(cli).to receive(:system).with('command -v gcloud > /dev/null 2>&1').and_return(true)

      # Mock Open3.capture2e
      # We expect 3 calls:
      # 1. describe config (check existence)
      # 2. set project
      # 3. set region

      # Let's say config exists to verify the update path which uses run_gcloud_command
      # Call 1: Describe
      expect(Open3).to receive(:capture2e).with('gcloud', 'config', 'configurations', 'describe', config_name)
                                          .and_return(['', double(success?: true)])

      # Call 2: Set Project (This is where injection would happen if unsafe)
      # It should receive the malicious string as a SINGLE argument in the array
      expect(Open3).to receive(:capture2e).with(
        'gcloud', 'config', 'set', 'project', project_id, "--configuration=#{config_name}"
      ).and_return(['', double(success?: true)])

      # Call 3: Set Region
      expect(Open3).to receive(:capture2e).with(
        'gcloud', 'config', 'set', 'compute/region', region, "--configuration=#{config_name}"
      ).and_return(['', double(success?: true)])

      # Silence stdout
      allow(cli).to receive(:say)

      cli.send(:create_gcloud_config, 'base', project_id, region)
    end
  end
end
