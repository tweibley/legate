# frozen_string_literal: true

# File: spec/adk/tools/check_job_status_tool_spec.rb
require 'spec_helper'
require 'sidekiq/api'
require 'redis'
require 'json'

RSpec.describe ADK::Tools::CheckJobStatusTool do
  let(:tool_class) { described_class }
  let(:metadata) { tool_class.tool_metadata }
  let(:job_id) { 'jid_test_456' }
  let(:params) { { job_id: job_id } }
  let(:dummy_registry) { ADK::ToolRegistry.new } # Dummy registry
  let(:context) { ADK::ToolContext.new(session_id: 's', user_id: 'u', app_name: 'a', tool_registry: dummy_registry) }
  let(:redis_options) { { url: 'redis://localhost:6379/1' } }
  let(:mock_redis) { instance_double(Redis) }
  let(:result_key) { "#{ADK::Tools::BaseAsyncJobTool::JOB_RESULT_REDIS_PREFIX}#{job_id}" }

  # Mocks for Sidekiq API objects
  let(:mock_job) { instance_double(Sidekiq::Job, jid: job_id) }
  let(:mock_queue) { instance_double(Sidekiq::Queue) }
  let(:mock_retry_set) { instance_double(Sidekiq::RetrySet) }
  let(:mock_scheduled_set) { instance_double(Sidekiq::ScheduledSet) }
  let(:mock_dead_set) { instance_double(Sidekiq::DeadSet) }

  before do
    # Stub Redis connection used by the tool
    allow(ADK).to receive(:redis_options).and_return(redis_options)
    allow(Redis).to receive(:new).with(redis_options).and_return(mock_redis)
    allow(mock_redis).to receive(:get).with(result_key).and_return(nil) # Default: no result stored
    allow(mock_redis).to receive(:close)

    # Stub Sidekiq API object creation
    allow(Sidekiq::Queue).to receive(:new).and_return(mock_queue)
    allow(Sidekiq::RetrySet).to receive(:new).and_return(mock_retry_set)
    allow(Sidekiq::ScheduledSet).to receive(:new).and_return(mock_scheduled_set)
    allow(Sidekiq::DeadSet).to receive(:new).and_return(mock_dead_set)

    # Default: Job not found in any set
    allow(mock_queue).to receive(:find_job).with(job_id).and_return(nil)
    allow(mock_retry_set).to receive(:find_job).with(job_id).and_return(nil)
    allow(mock_scheduled_set).to receive(:find_job).with(job_id).and_return(nil)
    allow(mock_dead_set).to receive(:find_job).with(job_id).and_return(nil)
  end

  # Test Class Metadata directly
  describe 'Class Metadata' do
    it 'has the correct explicit name' do
      expect(metadata[:name]).to eq(:check_job_status)
    end

    it 'has the correct description' do
      expect(metadata[:description]).to include('Checks the status and retrieves the result')
    end

    it 'defines the job_id parameter correctly' do
      expect(metadata[:parameters].keys).to eq([:job_id])
      expect(metadata[:parameters][:job_id][:required]).to be true
      expect(metadata[:parameters][:job_id][:type]).to eq(:string)
    end
  end

  describe '#perform_execution' do
    subject(:tool) { tool_class.new } # Create instance for execution tests

    context 'when job_id is missing' do
      it 'raises ToolArgumentError' do
        expect {
          tool.send(:perform_execution, { wrong_param: 'x' }, context)
        }.to raise_error(ADK::ToolArgumentError, /Missing required parameter: job_id/)
      end
    end

    context 'when result is found in Redis (success)' do
      let(:success_result) { { message: 'Job Complete!' } }
      let(:stored_data) { { status: :success, result: success_result }.to_json }
      before { allow(mock_redis).to receive(:get).with(result_key).and_return(stored_data) }

      it 'parses and returns the stored success result' do
        result = tool.send(:perform_execution, params, context)
        expect(result).to eq({ status: :success, result: success_result })
      end
    end

    context 'when result is found in Redis (error)' do
      let(:error_result) { { status: :error, error_message: 'WorkerError: Failed internally' }.to_json }
      before { allow(mock_redis).to receive(:get).with(result_key).and_return(error_result) }

      it 'parses and returns the stored error result' do
        result = tool.send(:perform_execution, params, context)
        expect(result).to eq({ status: :error, error_message: 'WorkerError: Failed internally' })
      end
    end

    context 'when stored result in Redis is invalid JSON' do
      before { allow(mock_redis).to receive(:get).with(result_key).and_return('{invalid json}') }
      it 'raises ToolError after logging parse error' do
        expect(ADK.logger).to receive(:error).with(/Failed to process stored result.*Error: JSON::ParserError/)
        expect {
          tool.send(:perform_execution, params, context)
        }.to raise_error(ADK::ToolError, /Failed to process stored result.*expected object key/)
      end
    end

    context 'when no result in Redis and job is in Sidekiq queue' do
      before { allow(mock_queue).to receive(:find_job).with(job_id).and_return(mock_job) }
      it 'returns a pending status hash' do
        result = tool.send(:perform_execution, params, context)
        expect(result).to eq({ status: :pending, job_id: job_id, message: 'Job is queued or currently running.' })
      end
    end

    context 'when no result in Redis and job is in Sidekiq retries' do
      before { allow(mock_retry_set).to receive(:find_job).with(job_id).and_return(mock_job) }
      it 'returns a pending status hash' do
        result = tool.send(:perform_execution, params, context)
        expect(result).to eq({ status: :pending, job_id: job_id, message: 'Job is queued or currently running.' })
      end
    end

    context 'when no result in Redis and job is in Sidekiq dead set' do
      before { allow(mock_dead_set).to receive(:find_job).with(job_id).and_return(mock_job) }
      it 'raises ToolError indicating failure' do
        expect {
          tool.send(:perform_execution, params, context)
        }.to raise_error(ADK::ToolError, /Job has failed \(found in Sidekiq Dead Set\)/)
      end
    end

    context 'when no result in Redis and job not found in Sidekiq' do
      # This is the default mock setup (job not found anywhere)
      it 'raises ToolError indicating completion/disappearance' do
        expect {
          tool.send(:perform_execution, params, context)
        }.to raise_error(ADK::ToolError, /Job result is unavailable/)
      end
    end

    context 'when Redis connection fails' do
      before {
        allow(Redis).to receive(:new).with(redis_options).and_raise(Redis::CannotConnectError, 'Connection refused')
      }
      it 'raises ToolError' do
        expect {
          tool.send(:perform_execution, params, context)
        }.to raise_error(ADK::ToolError, /Could not connect to Redis/)
      end
    end

    context 'when Sidekiq API query fails' do
      before { allow(mock_queue).to receive(:find_job).and_raise(StandardError, 'Sidekiq API error') }
      it 'raises ToolError indicating unknown status' do
        expect {
          tool.send(:perform_execution, params, context)
        }.to raise_error(ADK::ToolError, /Could not determine the status.*Sidekiq API error/)
      end
    end
  end
end
