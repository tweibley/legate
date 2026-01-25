# frozen_string_literal: true

require 'spec_helper'
require 'English'
require 'adk/cli/deployment_commands'

RSpec.describe ADK::CLI::DeploymentCommands do
  let(:cli) { described_class.new }

  # Suppress CLI output during tests
  before do
    allow(cli).to receive(:say)
  end

  describe '#create_gcloud_config' do
    let(:project_id) { 'my-project; echo INJECTION' }
    let(:region) { 'us-central1; echo INJECTION' }
    let(:base_name) { 'test-app' }
    let(:config_name) { 'adk-deploy-test-app' }

    before do
      # Mock system checks to pretend gcloud is installed
      allow(cli).to receive(:system).with(include('command -v gcloud')).and_return(true)

      # Mock checking if config exists (return false/failure to trigger creation path)
      allow(cli).to receive(:`).with(include('config configurations describe')).and_return('')

      # We need to control $CHILD_STATUS.success? for multiple calls.
      # 1. describe -> fails (false)
      # 2. create -> succeeds (true)
      # 3. set project -> succeeds (true)
      # 4. set region -> succeeds (true)
      allow($CHILD_STATUS).to receive(:success?).and_return(false, true, true, true)
    end

    it 'escapes project_id and region to prevent command injection' do
      # Expect creation command (sanitized base_name)
      expect(cli).to receive(:`).with(include("config configurations create #{config_name}")).and_return('')

      # Expect set project command - verify it is escaped
      # The vulnerability would execute: gcloud config set project my-project; echo INJECTION ...
      # The fix should execute: gcloud config set project my-project\;\ echo\ INJECTION ...

      escaped_project_id = Shellwords.escape(project_id)
      escaped_region = Shellwords.escape(region)

      # We check that the shell command passed to backticks contains the escaped version
      # Using include matchers because the command includes other flags
      expect(cli).to receive(:`).with(include(escaped_project_id)).and_return('')
      expect(cli).to receive(:`).with(include(escaped_region)).and_return('')

      # Bypass private method
      cli.send(:create_gcloud_config, base_name, project_id, region)
    end
  end
end
