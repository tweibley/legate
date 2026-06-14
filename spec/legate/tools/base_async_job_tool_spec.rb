# frozen_string_literal: true

# File: spec/legate/tools/base_async_job_tool_spec.rb
require 'spec_helper'

# --- Dummy Worker for Testing ---
class DummyWorker
  # Define perform to accept args based on prepare_job_arguments
  def perform(jid, arg1, _context_hash)
    # Simulate work
    sleep 0.1
    result_message = "Processed: #{arg1}"
    Legate::Tools::BaseAsyncJobTool.store_job_result(jid, result_message)
  end
end

# --- Dummy Tool Implementation ---
class MyAsyncJobTool < Legate::Tools::BaseAsyncJobTool
  # Replaced define_metadata with new DSL
  self.explicit_tool_name = :my_async_job
  tool_description 'Starts a dummy job'
  parameter :input_data, type: :string, required: true

  def worker_class; DummyWorker; end
  def prepare_job_arguments(params, context); [params[:input_data], context.to_h]; end
end

RSpec.describe Legate::Tools::BaseAsyncJobTool do
  subject(:tool) { MyAsyncJobTool.new }
  let(:params) { { input_data: 'some_value' } }
  let(:session_id) { 'sess_abc' }
  let(:user_id) { 'user_1' }
  let(:app_name) { 'test_app' }
  let(:dummy_registry) { Legate::ToolRegistry.new } # Dummy registry for context
  let(:context) {
    Legate::ToolContext.new(session_id: session_id, user_id: user_id, app_name: app_name, tool_registry: dummy_registry)
  }

  before do
    # Clear job results between tests
    Legate::Tools::BaseAsyncJobTool.job_results.clear
  end

  it 'requires subclasses to implement worker_class' do
    class AbstractSubclass < Legate::Tools::BaseAsyncJobTool
      self.explicit_tool_name = :abstract_job
      tool_description 'Abstract job tool'
    end
    expect { AbstractSubclass.new.send(:worker_class) }.to raise_error(NotImplementedError)
  end

  it 'requires subclasses to implement prepare_job_arguments' do
    class AbstractSubclassAgain < Legate::Tools::BaseAsyncJobTool
      self.explicit_tool_name = :abstract_job
      tool_description 'Abstract job tool'
    end
    expect { AbstractSubclassAgain.new.send(:prepare_job_arguments, {}, context) }.to raise_error(NotImplementedError)
  end

  describe '#perform_execution' do
    it 'calls prepare_job_arguments with params and context' do
      expect(tool).to receive(:prepare_job_arguments).with(params, context).and_call_original
      tool.send(:perform_execution, params, context)
    end

    it 'returns a :pending status hash with the job_id on success' do
      result = tool.send(:perform_execution, params, context)
      expect(result[:status]).to eq(:pending)
      expect(result[:job_id]).to be_a(String)
      expect(result[:job_id]).not_to be_empty
    end

    it 'stores pending status in job_results' do
      result = tool.send(:perform_execution, params, context)
      jid = result[:job_id]
      job_data = Legate::Tools::BaseAsyncJobTool.job_results[jid]
      expect(job_data).not_to be_nil
      expect(job_data['status']).to eq('pending')
    end

    it 'spawns a background thread that executes the worker' do
      result = tool.send(:perform_execution, params, context)
      jid = result[:job_id]

      # Wait for the background thread to complete
      sleep 0.3

      job_data = Legate::Tools::BaseAsyncJobTool.job_results[jid]
      expect(job_data['status']).to eq('completed')
      expect(job_data['result']).to include('Processed: some_value')
    end
  end

  describe '.store_job_result' do
    let(:jid) { 'store_jid_1' }
    let(:result_data) { 'Success!' }

    it 'stores the result in job_results' do
      described_class.store_job_result(jid, result_data)
      job_data = described_class.job_results[jid]
      expect(job_data['status']).to eq('completed')
      expect(job_data['result']).to include('Success!')
    end
  end

  describe '.store_job_error' do
    let(:jid) { 'error_jid_1' }
    let(:error_msg) { 'Something went wrong' }

    it 'stores the error in job_results' do
      described_class.store_job_error(jid, error_msg, 'MyError')
      job_data = described_class.job_results[jid]
      expect(job_data['status']).to eq('error')
      expect(job_data['error_message']).to eq(error_msg)
    end
  end

  describe '.store_job_pending' do
    let(:jid) { 'pending_jid_1' }

    it 'stores pending status in job_results' do
      described_class.store_job_pending(jid)
      job_data = described_class.job_results[jid]
      expect(job_data['status']).to eq('pending')
    end
  end
end
