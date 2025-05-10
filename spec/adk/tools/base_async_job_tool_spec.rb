# frozen_string_literal: true

# File: spec/adk/tools/base_async_job_tool_spec.rb
require 'spec_helper'
require 'sidekiq/testing' # Use Sidekiq testing helpers

# --- Dummy Worker for Testing ---
class DummySidekiqWorker
  include Sidekiq::Worker
  # Define perform to accept args based on prepare_job_arguments
  def perform(arg1, context_hash)
    # Simulate work
    puts "DummySidekiqWorker performing with #{arg1} and context #{context_hash}"
    # Example: Store result using the helper from BaseAsyncJobTool
    # result_data = "Processed: #{arg1}"
    # ADK::Tools::BaseAsyncJobTool.store_job_result(jid, result_data) if jid
  end
end

# --- Dummy Tool Implementation ---
class MyAsyncJobTool < ADK::Tools::BaseAsyncJobTool
  # Replaced define_metadata with new DSL
  self.explicit_tool_name = :my_async_job
  tool_description 'Starts a dummy job'
  parameter :input_data, type: :string, required: true

  def sidekiq_worker_class; DummySidekiqWorker; end
  # Use default job options
  def prepare_job_arguments(params, context); [params[:input_data], context.to_h]; end
end

RSpec.describe ADK::Tools::BaseAsyncJobTool do
  subject(:tool) { MyAsyncJobTool.new }
  let(:params) { { input_data: 'some_value' } }
  let(:session_id) { 'sess_abc' }
  let(:user_id) { 'user_1' }
  let(:app_name) { 'test_app' }
  let(:dummy_registry) { ADK::ToolRegistry.new } # Dummy registry for context
  let(:context) {
    ADK::ToolContext.new(session_id: session_id, user_id: user_id, app_name: app_name, tool_registry: dummy_registry)
  }
  let(:expected_job_id) { 'test_jid_123' }

  before do
    # Configure Sidekiq testing mode
    Sidekiq::Testing.fake! # Jobs are pushed to worker.jobs array, not Redis
    # Configure dummy Redis options if needed for result storage tests later
    allow(ADK).to receive(:redis_options).and_return({ url: 'redis://localhost:6379/1' })
  end

  after do
    Sidekiq::Testing.disable! # Reset Sidekiq testing mode
  end

  it 'requires subclasses to implement sidekiq_worker_class' do
    class AbstractSubclass < ADK::Tools::BaseAsyncJobTool
      # Replaced define_metadata
      self.explicit_tool_name = :abstract_job
      tool_description 'Abstract job tool'
      # No parameters defined
    end
    expect { AbstractSubclass.new.send(:sidekiq_worker_class) }.to raise_error(NotImplementedError)
  end

  it 'requires subclasses to implement prepare_job_arguments' do
    # Reline the class here as RSpec often doesn't reuse the one from the previous example
    class AbstractSubclassAgain < ADK::Tools::BaseAsyncJobTool
      # Replaced define_metadata
      self.explicit_tool_name = :abstract_job
      tool_description 'Abstract job tool'
    end
    expect { AbstractSubclassAgain.new.send(:prepare_job_arguments, {}, context) }.to raise_error(NotImplementedError)
  end

  describe '#perform_execution' do
    before do
      # Clear jobs before each test in this block
      DummySidekiqWorker.jobs.clear
      # Stub perform_async to return a predictable JID
      # Note: Sidekiq::Testing.fake! handles the JID generation usually,
      # but we can also stub it if we need a specific one.
      # --- REMOVED: Let fake! mode handle JID generation ---
      # allow(DummySidekiqWorker).to receive(:perform_async).and_return(expected_job_id)
    end

    it 'calls prepare_job_arguments with params and context' do
      expect(tool).to receive(:prepare_job_arguments).with(params, context).and_call_original
      tool.send(:perform_execution, params, context)
    end

    it 'calls worker_class.perform_async with correct args and options' do
      # Use Sidekiq::Testing to assert job enqueueing
      expect {
        tool.send(:perform_execution, params, context)
      }.to change(DummySidekiqWorker.jobs, :size).by(1)

      # Verify job details
      job = DummySidekiqWorker.jobs.last
      expect(job['args']).to eq([params[:input_data], context.to_h.transform_keys(&:to_s)]) # Args are stringified
      expect(job['queue']).to eq('default')
      expect(job['retry']).to eq(3)
    end

    it 'returns a :pending status hash with the job_id on success' do
      # Let perform_execution run and get the real JID
      result = tool.send(:perform_execution, params, context)
      expect(result[:status]).to eq(:pending)
      expect(result[:job_id]).to be_a(String) # Check JID is a string
      expect(result[:job_id]).not_to be_empty # Check JID is not empty
      # Optionally, check if it looks like a JID (e.g., matches a pattern)
      expect(result[:job_id]).to match(/^[a-f0-9]{24}$/) # Standard Sidekiq JID format
    end

    context 'when sidekiq_worker_class is invalid' do
      before { allow(tool).to receive(:sidekiq_worker_class).and_return(nil) }
      it 'raises ToolError' do
        expect {
          tool.send(:perform_execution, params, context)
        }.to raise_error(ADK::ToolError, /sidekiq_worker_class not defined or invalid/)
      end
    end

    context 'when perform_async returns nil' do
      before do
        allow(DummySidekiqWorker).to receive(:set).and_return(DummySidekiqWorker)
        allow(DummySidekiqWorker).to receive(:perform_async).and_return(nil)
      end
      it 'raises ToolError' do
        expect {
          tool.send(:perform_execution, params, context)
        }.to raise_error(ADK::ToolError, /Failed to enqueue Sidekiq job.*perform_async returned nil/)
      end
    end

    context 'when Redis connection fails' do
      before do
        allow(DummySidekiqWorker).to receive(:set).and_return(DummySidekiqWorker)
        allow(DummySidekiqWorker).to receive(:perform_async).and_raise(Redis::CannotConnectError, 'Connection refused')
      end
      it 'raises ToolError' do
        expect {
          tool.send(:perform_execution, params, context)
        }.to raise_error(ADK::ToolError, /Could not connect to Redis.*Connection refused/)
      end
    end

    context 'when perform_async raises a generic StandardError' do
      let(:generic_error) { StandardError.new('Something else broke') }
      before do
        allow(DummySidekiqWorker).to receive(:set).and_return(DummySidekiqWorker)
        allow(DummySidekiqWorker).to receive(:perform_async).and_raise(generic_error)
        allow(ADK.logger).to receive(:error) # Stub logger to check calls
      end
      it 'rescues, logs, and raises ToolError' do
        expect {
          tool.send(:perform_execution, params, context)
        }.to raise_error(ADK::ToolError, /Unexpected error enqueuing Sidekiq job.*Something else broke/)

        expect(ADK.logger).to have_received(:error).with(/Unexpected error.*StandardError - Something else broke/)
        # Check that error was called again (for backtrace), without being too specific about content
        expect(ADK.logger).to have_received(:error).twice
      end
    end
  end

  describe '.store_job_result' do
    let(:mock_redis) { instance_double(Redis) }
    let(:jid) { 'store_jid_1' }
    let(:result_data) { { message: 'Success!' } }
    let(:expected_key) { "#{ADK::Tools::BaseAsyncJobTool::JOB_RESULT_REDIS_PREFIX}#{jid}" }
    let(:expected_ttl) { ADK::Tools::BaseAsyncJobTool::JOB_RESULT_TTL }
    let(:expected_json) { { status: :success, result: result_data }.to_json }

    before do
      allow(Redis).to receive(:new).and_return(mock_redis)
      allow(mock_redis).to receive(:setex).with(expected_key, expected_ttl, expected_json)
      allow(mock_redis).to receive(:close)
    end

    it 'connects to Redis with correct options' do
      expect(Redis).to receive(:new).with(ADK.redis_options).and_return(mock_redis)
      described_class.store_job_result(jid, result_data)
    end

    it 'calls redis.setex with correct key, ttl, and JSON data' do
      expect(mock_redis).to receive(:setex).with(expected_key, expected_ttl, expected_json)
      described_class.store_job_result(jid, result_data)
    end

    it 'logs error and does not raise if Redis fails' do
      allow(mock_redis).to receive(:setex).and_raise(Redis::TimeoutError)
      expect(ADK.logger).to receive(:error).with(/Failed to store result for job #{jid}/)
      expect { described_class.store_job_result(jid, result_data) }.not_to raise_error
    end

    it 'closes the Redis connection' do
      expect(mock_redis).to receive(:close)
      described_class.store_job_result(jid, result_data)
    end
  end

  describe '.store_job_error' do
    # Similar tests as store_job_result, but checking the error format
    let(:mock_redis) { instance_double(Redis) }
    let(:jid) { 'error_jid_1' }
    let(:error_msg) { 'Something went wrong' }
    let(:error_cls) { 'MyError' }
    let(:expected_key) { "#{ADK::Tools::BaseAsyncJobTool::JOB_RESULT_REDIS_PREFIX}#{jid}" }
    let(:expected_ttl) { ADK::Tools::BaseAsyncJobTool::JOB_RESULT_TTL }
    let(:expected_json) { { status: :error, error_message: "#{error_cls}: #{error_msg}" }.to_json }

    before do
      allow(Redis).to receive(:new).and_return(mock_redis)
      allow(mock_redis).to receive(:setex).with(expected_key, expected_ttl, expected_json)
      allow(mock_redis).to receive(:close)
    end

    it 'calls redis.setex with correct key, ttl, and error JSON data' do
      expect(mock_redis).to receive(:setex).with(expected_key, expected_ttl, expected_json)
      described_class.store_job_error(jid, error_msg, error_cls)
    end

    it 'logs error and does not raise if Redis fails' do
      allow(mock_redis).to receive(:setex).and_raise(Redis::TimeoutError)
      expect(ADK.logger).to receive(:error).with(/Failed to store error for job #{jid}/)
      expect { described_class.store_job_error(jid, error_msg, error_cls) }.not_to raise_error
    end

    it 'closes the Redis connection' do
      expect(mock_redis).to receive(:close)
      described_class.store_job_error(jid, error_msg, error_cls)
    end
  end

  # --- Tests for Static Helper Methods --- #
  describe '.store_job_pending' do
    let(:mock_redis) { instance_double(Redis, close: nil) }
    let(:jid) { 'pending_jid_1' }
    let(:expected_key) { "#{ADK::Tools::BaseAsyncJobTool::JOB_RESULT_REDIS_PREFIX}#{jid}" }
    let(:expected_ttl) { ADK::Tools::BaseAsyncJobTool::JOB_RESULT_TTL }
    let(:expected_json) { { status: :pending, message: 'Job processing started.' }.to_json }

    before do
      allow(Redis).to receive(:new).and_return(mock_redis)
      allow(mock_redis).to receive(:setex).with(expected_key, expected_ttl, expected_json)
    end

    it 'connects to Redis with correct options' do
      expect(Redis).to receive(:new).with(ADK.redis_options).and_return(mock_redis)
      described_class.store_job_pending(jid)
    end

    it 'calls redis.setex with correct key, ttl, and JSON data' do
      expect(mock_redis).to receive(:setex).with(expected_key, expected_ttl, expected_json)
      described_class.store_job_pending(jid)
    end

    it 'logs error and does not raise if Redis fails' do
      allow(mock_redis).to receive(:setex).and_raise(Redis::TimeoutError)
      expect(ADK.logger).to receive(:error).with(/Failed to store pending status for job #{jid}/)
      expect { described_class.store_job_pending(jid) }.not_to raise_error
    end

    it 'closes the Redis connection' do
      expect(mock_redis).to receive(:close)
      described_class.store_job_pending(jid)
    end
  end
end
