# File: spec/legate/tools/sleepy_tool_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'legate/tools/sleepy_tool' # Adjust path as needed

RSpec.describe Legate::Tools::SleepyTool do
  let(:tool_name) { :start_sleepy_job }
  let(:tool_class) { described_class }
  let(:tool_instance) { tool_class.new }
  let(:params) { { duration: 5, message: 'Hello Sleepy' } }
  let(:context) { instance_double('Legate::Context', to_h: {}) } # Allow .to_h

  before do
    Legate::Tools::BaseAsyncJobTool.job_results.clear
  end

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

  describe '#worker_class' do
    it 'returns the SleepyWorker class' do
      expect(tool_instance.worker_class).to eq(Legate::Tools::SleepyWorker)
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
  describe '#execute (inherited behavior)' do
    before do
      # Allow BaseAsyncJobTool helpers to be called
      allow(Legate::Tools::BaseAsyncJobTool).to receive(:store_job_pending).and_call_original
      allow(Legate::Tools::BaseAsyncJobTool).to receive(:store_job_result).and_call_original
      allow(Legate::Tools::BaseAsyncJobTool).to receive(:store_job_error).and_call_original
      # Prevent actual sleep in the worker during this test
      allow_any_instance_of(Legate::Tools::SleepyWorker).to receive(:sleep)
    end

    it 'returns a pending status with a job ID' do
      result = tool_instance.execute(params, context)
      expect(result).to be_a(Hash)
      expect(result[:job_id]).to be_a(String)
      expect(result[:status]).to eq(:pending)
    end

    it 'spawns a background thread that executes the worker' do
      result = tool_instance.execute(params, context)
      jid = result[:job_id]

      # Wait for the background thread to complete
      sleep 0.3

      job_data = Legate::Tools::BaseAsyncJobTool.job_results[jid]
      expect(job_data['status']).to eq('completed')
      expect(job_data['result']).to include('Slept for 5 seconds. Your message: Hello Sleepy')
    end
  end
end

# --- Tests for SleepyWorker ---
RSpec.describe Legate::Tools::SleepyWorker do
  let(:worker) { described_class.new }
  let(:jid) { 'TEST_JID_123' }
  let(:duration) { 2 }
  let(:message) { 'Worker Test' }

  before do
    Legate::Tools::BaseAsyncJobTool.job_results.clear
    # Mock logger to prevent actual logging output during tests
    allow(Legate).to receive(:logger).and_return(instance_double('Logger', info: nil, error: nil, debug: nil))
    # Mock sleep to avoid waiting
    allow(worker).to receive(:sleep)
  end

  describe '#perform' do
    it 'stores pending status, sleeps, and stores result' do
      worker.perform(jid, duration, message)

      # Verify the final result is stored
      job_data = Legate::Tools::BaseAsyncJobTool.job_results[jid]
      expect(job_data['status']).to eq('completed')
      expect(job_data['result']).to include("Slept for #{duration} seconds. Your message: #{message}")

      expect(Legate.logger).to have_received(:info).with(/Starting job. Sleeping for #{duration}/)
      expect(worker).to have_received(:sleep).with(duration)
      expect(Legate.logger).to have_received(:info).with(/Job finished. Storing result./)
    end

    it 'stores error if sleep fails' do
      sleep_error = StandardError.new('Sleep interrupted')
      allow(worker).to receive(:sleep).with(duration).and_raise(sleep_error)

      worker.perform(jid, duration, message)

      job_data = Legate::Tools::BaseAsyncJobTool.job_results[jid]
      expect(job_data['status']).to eq('error')
      expect(job_data['error_message']).to include('Sleep interrupted')
      expect(Legate.logger).to have_received(:error).with(/Job failed! Storing error./)
    end

    it 'logs error and continues if storing initial pending status fails' do
      allow(Legate::Tools::BaseAsyncJobTool).to receive(:store_job_pending).with(jid).and_raise(StandardError.new('Store failed'))

      worker.perform(jid, duration, message)

      expect(Legate.logger).to have_received(:error).with(/Failed to store initial pending status: Store failed/)
      # Crucially, it should still proceed
      expect(worker).to have_received(:sleep).with(duration)
      # Final result should still be stored
      job_data = Legate::Tools::BaseAsyncJobTool.job_results[jid]
      expect(job_data['status']).to eq('completed')
    end
  end
end
