require 'spec_helper'
require 'legate/cli/deployment_commands'
require 'shellwords'

RSpec.describe Legate::CLI::DeploymentCommands do
  let(:commands) { described_class.new }

  before do
    allow(FileUtils).to receive(:mkdir_p)
    allow(FileUtils).to receive(:chmod)
    allow(FileUtils).to receive(:cp)
    allow(File).to receive(:exist?).and_return(false)
  end

  describe 'Script Injection Vulnerability' do
    it 'escapes inputs in deploy-gcp.sh via project_id' do
      malicious_id = 'test"; echo "PWNED"; echo "'
      options = {
        cloud: 'gcp',
        name: 'test_deploy',
        entry_point: 'bin/web',
        gcp_project_id: malicious_id,
        gcp_region: 'us-central1'
      }

      captured_content = nil
      allow(File).to receive(:write) # Stub all writes

      # Capture the write to deploy-gcp.sh
      allow(File).to receive(:write).with(end_with('deploy-gcp.sh'), anything) do |path, content|
        captured_content = content
      end

      commands.invoke(:generate, [], options)

      # It should NOT contain the raw malicious string inside quotes
      expect(captured_content).not_to include("PROJECT_ID=\"#{malicious_id}\"")

      # It SHOULD contain the escaped string assigned to the variable
      # Shellwords.escape ensures it's safe for Bash
      escaped_id = Shellwords.escape(malicious_id)
      expect(captured_content).to include("PROJECT_ID=#{escaped_id}")
    end
  end
end
