# frozen_string_literal: true

require 'spec_helper'
require 'legate/cli/deployment_commands'
require 'fileutils'

RSpec.describe Legate::CLI::DeploymentCommands do
  let(:commands) { described_class.new }
  let(:output) { StringIO.new }
  let(:shell) { Thor::Shell::Basic.new }
  let(:deployment_dir) { File.expand_path('deployment_test') }

  before do
    allow(shell).to receive(:stdout).and_return(output)
    allow(shell).to receive(:stderr).and_return(output)
    commands.shell = shell

    # Mock FileUtils to prevent actual directory creation
    allow(FileUtils).to receive(:mkdir_p)
    allow(FileUtils).to receive(:chmod)
    allow(FileUtils).to receive(:cp)

    # Mock File.write to prevent actual file writing
    allow(File).to receive(:write)

    # Mock File.exist?
    allow(File).to receive(:exist?).and_return(false)
  end

  # Helper to invoke Thor command
  def invoke_command(command_name, *args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    # Thor's invoke method takes (task, args, opts, config)
    # We need to pass options as the 3rd argument for them to be available
    commands.invoke(command_name, args, options)
  rescue SystemExit
    # Captured
  end

  describe '#generate' do
    let(:default_options) { { cloud: 'none', entry_point: 'bin/web' } }

    context 'Generic assets' do
      it 'creates deployment directory' do
        invoke_command(:generate, name: 'deploy_output', **default_options)
        expect(FileUtils).to have_received(:mkdir_p).with(File.expand_path('deploy_output'))
      end

      it 'generates main Dockerfile' do
        expect(File).to receive(:write).with(/Dockerfile/, include('FROM ruby:3.2-slim'))
        invoke_command(:generate, **default_options)
      end

      it 'generates .dockerignore' do
        expect(File).to receive(:write).with(/.dockerignore/, include('.git'))
        invoke_command(:generate, **default_options)
      end

      it 'generates config.ru' do
        expect(File).to receive(:write).with(/config.ru/, include('run LegateWebApp'))
        invoke_command(:generate, **default_options)
      end

      it 'generates agent Dockerfiles if specified' do
        # We only check that the file is written, as content might not include the entrypoint string directly
        # if it relies on Rackup/config.ru structure.
        expect(File).to receive(:write).with(/Dockerfile.agent.worker.0/, anything)
        invoke_command(:generate, **default_options.merge(agent_entry_points: ['bin/worker']))
      end
    end

    context 'Sample entrypoint generation' do
      it 'generates sample entrypoint if requested' do
        expect(File).to receive(:write).with(/legate_web_entrypoint.rb/, include('class LegateWebApp < Sinatra::Base'))
        invoke_command(:generate, cloud: 'none', generate_sample_entrypoint: true)
      end

      it 'fails if no entrypoint provided and sample not requested' do
        invoke_command(:generate, cloud: 'none') # Missing entry_point
        expect(output.string).to include('Error: --entry-point is required')
      end
    end

    context 'GCP assets' do
      let(:gcp_options) { default_options.merge(cloud: 'gcp', gcp_project_id: 'my-project') }

      it 'generates GCP deployment script' do
        expect(File).to receive(:write).with(/deploy-gcp.sh/, include('gcloud run deploy'))
        invoke_command(:generate, **gcp_options)
      end

      it 'generates Cloud Build config' do
        expect(File).to receive(:write).with(/cloudbuild.yaml/, include('steps:'))
        invoke_command(:generate, **gcp_options)
      end

      it 'copies GCP deployment docs' do
        # We need to mock File.expand_path to find the doc
        allow(File).to receive(:exist?).with(/go-to-gcp-production-gemini.md/).and_return(true)
        expect(FileUtils).to receive(:cp)
        invoke_command(:generate, **gcp_options)
      end

      it 'fails if GCP project ID is missing' do
        invoke_command(:generate, **default_options.merge(cloud: 'gcp'))
        expect(output.string).to include('Error: --gcp-project-id is required')
      end
    end

    context 'AWS/Azure assets' do
      it 'warns that AWS is not implemented' do
        invoke_command(:generate, **default_options.merge(cloud: 'aws'))
        expect(output.string).to include('AWS deployment asset generation is not yet implemented')
      end

      it 'warns that Azure is not implemented' do
        invoke_command(:generate, **default_options.merge(cloud: 'azure'))
        expect(output.string).to include('Azure deployment asset generation is not yet implemented')
      end
    end
  end
end
