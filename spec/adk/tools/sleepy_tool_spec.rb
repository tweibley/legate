# File: spec/adk/tools/sleepy_tool_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/tools/sleepy_tool' # Adjust path as needed
require 'sidekiq/testing' # Required for testing Sidekiq workers

RSpec.describe ADK::Tools::SleepyTool do
  let(:tool_name) { :start_sleepy_job }
  let(:tool_class) { described_class }
  let(:tool_instance) { tool_class.new }
  let(:params) { { duration: 5, message: 'Hello Sleepy' } }
  let(:context) { instance_double('ADK::Context', to_h: {}) } # Allow .to_h

  # --- Shared Tool Behavior (Consider extracting to a shared example) ---
  it 'has the correct tool name' do
    expect(tool_class.tool_metadata[:name]).to eq(tool_name)
  end

  it 'has a description' do
    expect(tool_class.tool_metadata[:description]).not_to be_empty
  end

  it 'defines parameters' do
    parameters = tool_class.tool_metadata[:parameters]
    expect(parameters).to include(:duration, :message)
    expect(parameters[:duration][:type]).to eq(:integer)
    expect(parameters[:duration][:required]).to eq(true)
    expect(parameters[:message][:type]).to eq(:string)
    expect(parameters[:message][:required]).to eq(true)
  end
  # --- End Shared Tool Behavior ---

  describe '#sidekiq_worker_class' do
    it 'returns the SleepyWorker class' do
      expect(tool_instance.sidekiq_worker_class).to eq(ADK::Tools::SleepyWorker)
    end
  end

  describe '#prepare_job_arguments' do
    it 'prepares arguments correctly for the worker' do
      prepared_args = tool_instance.prepare_job_arguments(params, context)
      expect(prepared_args).to eq([5, 'Hello Sleepy'])
    end

    it 'handles string duration input' do
      params[:duration] = '10'
      prepared_args = tool_instance.prepare_job_arguments(params, context)
      expect(prepared_args).to eq([10, 'Hello Sleepy'])
    end
  end

  # --- BaseAsyncJobTool Integration (Basic Check) ---
  # Requires Sidekiq::Testing.inline! or similar setup in spec_helper
  # or a block: Sidekiq::Testing.inline! do ... end
  describe '#execute (inherited behavior)' do
    before do
      Sidekiq::Worker.clear_all # Clear jobs before each test
      # Allow BaseAsyncJobTool helpers to be called
      allow(ADK::Tools::BaseAsyncJobTool).to receive(:store_job_pending).and_return(true)
      allow(ADK::Tools::BaseAsyncJobTool).to receive(:store_job_result).and_return(true)
      allow(ADK::Tools::BaseAsyncJobTool).to receive(:store_job_error).and_return(true)
      # Prevent actual sleep in the worker during this test
      allow_any_instance_of(ADK::Tools::SleepyWorker).to receive(:sleep)
    end

    # Use Sidekiq inline testing mode to execute the job immediately
    it 'enqueues and executes the worker job, returning a job ID' do
      Sidekiq::Testing.inline! do
        result = tool_instance.execute(params, context)
        expect(result).to be_a(Hash)
        expect(result[:job_id]).to be_a(String)
        expect(result[:status]).to eq(:pending) # Changed from 'queued'

        # Verify worker was called (inline mode executes it)
        expect(ADK::Tools::BaseAsyncJobTool).to have_received(:store_job_pending).with(anything) # JID is generated
        # Cannot easily test sleep was "called" with allow(...).to receive(:sleep)
        expect(ADK::Tools::BaseAsyncJobTool).to have_received(:store_job_result).with(anything,
                                                                                      "Slept for 5 seconds. Your message: Hello Sleepy")
      end
    end

    it 'enqueues the job with correct arguments using fake! mode' do
      Sidekiq::Testing.fake! do # Ensure jobs are enqueued but not run
        job_id = tool_instance.execute(params, context)[:job_id] # Get the expected JID if Base returns it
        expect(ADK::Tools::SleepyWorker.jobs.size).to eq(1)
        job = ADK::Tools::SleepyWorker.jobs.first
        expect(job['jid']).to eq(job_id) if job_id # Check JID if available
        expect(job['args']).to eq([5, 'Hello Sleepy'])
        expect(job['queue']).to eq('default')
        expect(job['retry']).to eq(3) # Changed from 1 based on BaseAsyncJobTool default
      end
    end
  end
end

# --- Tests for SleepyWorker ---
RSpec.describe ADK::Tools::SleepyWorker do
  let(:worker) { described_class.new }
  let(:jid) { 'TEST_JID_123' }
  let(:duration) { 2 }
  let(:message) { 'Worker Test' }

  before do
    # Mock the jid for the worker instance
    allow(worker).to receive(:jid).and_return(jid)
    # Mock the BaseAsyncJobTool helpers
    allow(ADK::Tools::BaseAsyncJobTool).to receive(:store_job_pending)
    allow(ADK::Tools::BaseAsyncJobTool).to receive(:store_job_result)
    allow(ADK::Tools::BaseAsyncJobTool).to receive(:store_job_error)
    # Mock logger to prevent actual logging output during tests
    allow(ADK).to receive(:logger).and_return(instance_double('Logger', info: nil, error: nil))
    # Mock sleep to avoid waiting
    allow(worker).to receive(:sleep)
  end

  describe '#perform' do
    it 'stores pending status, sleeps, and stores result' do
      worker.perform(duration, message)

      expect(ADK::Tools::BaseAsyncJobTool).to have_received(:store_job_pending).with(jid).ordered
      expect(ADK.logger).to have_received(:info).with(/Starting job. Sleeping for #{duration}/).ordered
      expect(worker).to have_received(:sleep).with(duration).ordered
      expect(ADK.logger).to have_received(:info).with(/Job finished. Storing result./).ordered
      expected_result = "Slept for #{duration} seconds. Your message: #{message}"
      expect(ADK::Tools::BaseAsyncJobTool).to have_received(:store_job_result).with(jid, expected_result).ordered
      expect(ADK::Tools::BaseAsyncJobTool).not_to have_received(:store_job_error)
    end

    it 'stores error if sleep fails' do
      sleep_error = StandardError.new('Sleep interrupted')
      allow(worker).to receive(:sleep).with(duration).and_raise(sleep_error)

      worker.perform(duration, message)

      expect(ADK::Tools::BaseAsyncJobTool).to have_received(:store_job_pending).with(jid).ordered
      expect(worker).to have_received(:sleep).with(duration).ordered
      expect(ADK.logger).to have_received(:error).with(/Job failed! Storing error./).ordered
      expect(ADK::Tools::BaseAsyncJobTool)
        .to have_received(:store_job_error)
        .with(jid, "Job failed after starting sleep: #{sleep_error.message}", 'StandardError')
        .ordered
      expect(ADK::Tools::BaseAsyncJobTool).not_to have_received(:store_job_result)
    end

    it 'stores error if storing result fails' do
      store_error = StandardError.new('Redis unavailable')
      expected_result = "Slept for #{duration} seconds. Your message: #{message}"
      allow(ADK::Tools::BaseAsyncJobTool).to receive(:store_job_result).with(jid,
                                                                             expected_result).and_raise(store_error)

      worker.perform(duration, message)

      expect(ADK::Tools::BaseAsyncJobTool).to have_received(:store_job_pending).with(jid).ordered
      expect(worker).to have_received(:sleep).with(duration).ordered
      expect(ADK::Tools::BaseAsyncJobTool).to have_received(:store_job_result).with(jid, expected_result).ordered # It was called
      expect(ADK.logger).to have_received(:error).with(/Job failed! Storing error./).ordered
      expect(ADK::Tools::BaseAsyncJobTool)
        .to have_received(:store_job_error)
        .with(jid, "Job failed after starting sleep: #{store_error.message}", 'StandardError') # Error bubbles up
        .ordered
    end

    it 'logs error and continues if storing initial pending status fails' do
      pending_error = StandardError.new('Cannot connect to Redis')
      allow(ADK::Tools::BaseAsyncJobTool).to receive(:store_job_pending).with(jid).and_raise(pending_error)

      worker.perform(duration, message)

      expect(ADK::Tools::BaseAsyncJobTool).to have_received(:store_job_pending).with(jid).ordered
      expect(ADK.logger).to have_received(:error).with(/Failed to store initial pending status: #{pending_error.message}/).ordered
      # Crucially, it should still proceed
      expect(worker).to have_received(:sleep).with(duration).ordered
      expected_result = "Slept for #{duration} seconds. Your message: #{message}"
      expect(ADK::Tools::BaseAsyncJobTool).to have_received(:store_job_result).with(jid, expected_result).ordered
      expect(ADK::Tools::BaseAsyncJobTool).not_to have_received(:store_job_error) # Error during pending doesn't trigger job error storage
    end
  end
end
