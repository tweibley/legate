# File: spec/adk/tools/check_job_status_tool_spec.rb
require 'spec_helper'
require 'sidekiq/api'
require 'redis'
require 'json'

RSpec.describe ADK::Tools::CheckJobStatusTool do
  subject(:tool) { described_class.new }
  let(:job_id) { 'jid_test_456' }
  let(:params) { { job_id: job_id } }
  let(:context) { ADK::ToolContext.new(session_id: 's', user_id: 'u', app_name: 'a') }
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

  it 'has correct metadata' do
    expect(tool.name).to eq(:check_job_status)
    expect(tool.parameters).to have_key(:job_id)
    expect(tool.parameters[:job_id][:required]).to be true
  end

  describe '#perform_execution' do
    context 'when job_id is missing' do
      it 'returns an error hash' do
        result = tool.send(:perform_execution, { wrong_param: 'x' }, context)
        expect(result).to eq({ status: :error, error_message: 'Missing required parameter: job_id' })
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
      it 'logs a parse error and returns status based on Sidekiq API check' do
        expect(ADK.logger).to receive(:error).with(/Failed to parse stored JSON result/)
        result = tool.send(:perform_execution, params, context)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include('result is unavailable')
      end
    end

    context 'when no result in Redis and job is in Sidekiq queue' do
      before { allow(mock_queue).to receive(:find_job).with(job_id).and_return(mock_job) }
      it 'returns a pending status hash' do
        result = tool.send(:perform_execution, params, context)
        expect(result).to eq({ status: :pending, job_id: job_id, message: "Job is queued or currently running." })
      end
    end

    context 'when no result in Redis and job is in Sidekiq retries' do
      before { allow(mock_retry_set).to receive(:find_job).with(job_id).and_return(mock_job) }
      it 'returns a pending status hash' do
        result = tool.send(:perform_execution, params, context)
        expect(result).to eq({ status: :pending, job_id: job_id, message: "Job is queued or currently running." })
      end
    end

    context 'when no result in Redis and job is in Sidekiq dead set' do
      before { allow(mock_dead_set).to receive(:find_job).with(job_id).and_return(mock_job) }
      it 'returns an error hash indicating failure' do
        result = tool.send(:perform_execution, params, context)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include('failed (found in Dead Set)')
      end
    end

    context 'when no result in Redis and job not found in Sidekiq' do
      # This is the default mock setup (job not found anywhere)
      it 'returns an error hash indicating completion/disappearance' do
        result = tool.send(:perform_execution, params, context)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include('result is unavailable')
      end
    end

    context 'when Redis connection fails' do
      before {
        allow(Redis).to receive(:new).with(redis_options).and_raise(Redis::CannotConnectError, "Connection refused")
      }
      it 'returns an error hash' do
        result = tool.send(:perform_execution, params, context)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include('Could not connect to Redis')
      end
    end

    context 'when Sidekiq API query fails' do
      before { allow(mock_queue).to receive(:find_job).and_raise(StandardError, "Sidekiq API error") }
      it 'returns an error hash indicating unknown status' do
        result = tool.send(:perform_execution, params, context)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include("Could not determine the status")
      end
    end
  end
end
