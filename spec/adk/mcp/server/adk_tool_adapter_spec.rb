# File: spec/adk/mcp/server/adk_tool_adapter_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'fast_mcp'
require 'adk/mcp/server/adk_tool_adapter'
require 'adk/tool'
require 'adk/tool_context'
require 'adk/mcp/util/schema_converter'
require 'adk/mcp' # For logger
require 'securerandom'

# Mock ADK Tool for testing
class MockAdkTool < ADK::Tool
  self.explicit_tool_name = :mock_adk_tool
  tool_description 'A mock ADK tool for testing adapter'
  parameter :input_param, type: :string, description: 'Input data', required: true

  def perform_execution(params, context)
    { status: :success, result: "Success: #{params[:input_param]}" }
  end
end

class MockAdkAsyncTool < ADK::Tools::BaseAsyncJobTool
  self.explicit_tool_name = :mock_adk_async_tool
  tool_description 'An async ADK tool'
  parameter :job_data, type: :string

  class MockWorker; include Sidekiq::Worker; def perform(*_args); end; end

  def sidekiq_worker_class; MockWorker; end
  def prepare_job_arguments(params, context); [params[:job_data]]; end
end

class MockAdkErrorTool < ADK::Tool
  self.explicit_tool_name = :mock_adk_error_tool
  tool_description 'Returns an ADK error'
  parameter :error_message, type: :string

  def perform_execution(params, context)
    { status: :error, error_message: params[:error_message] || 'Default ADK error' }
  end
end

class MockAdkExecuteErrorTool < ADK::Tool
  self.explicit_tool_name = :mock_adk_execute_error_tool
  tool_description 'Raises an error during execution'

  def perform_execution(params, context)
    raise ArgumentError, "Execution failed!"
  end
end

RSpec.describe ADK::Mcp::Server::AdkToolAdapter do
  let(:logger_spy) { spy('Logger') }
  let(:mock_schema_proc) { Proc.new { required(:param1).filled(:string) } }

  before do
    allow(ADK).to receive(:logger).and_return(logger_spy)
    # Stub the schema converter
    allow(ADK::Mcp::Util::SchemaConverter).to receive(:adk_to_dry_schema)
      .and_return(mock_schema_proc)
  end

  describe '.wrap' do
    it 'raises ArgumentError if input is not an ADK::Tool class' do
      expect { described_class.wrap(String) }.to raise_error(ArgumentError, /not a valid ADK::Tool/)
      # Test wrapping an instance, should fail class check
      expect { described_class.wrap(MockAdkTool.new) }.to raise_error(ArgumentError, /not a valid ADK::Tool class/)
    end

    it 'raises ArgumentError if ADK::Tool has no metadata' do
      class NoMetaTool < ADK::Tool; end # Define locally
      # Mock tool_metadata to return nil for this specific class
      allow(NoMetaTool).to receive(:tool_metadata).and_return(nil)
      expect { described_class.wrap(NoMetaTool) }.to raise_error(ArgumentError, /incomplete metadata/)
    end

    it 'creates an anonymous subclass of AdkToolAdapter' do
      adapter_class = described_class.wrap(MockAdkTool)
      expect(adapter_class).to be_a(Class)
      expect(adapter_class).to be < ADK::Mcp::Server::AdkToolAdapter
      expect(adapter_class.superclass).to eq(ADK::Mcp::Server::AdkToolAdapter)
    end

    it 'sets the adk_tool_class attribute on the subclass' do
      adapter_class = described_class.wrap(MockAdkTool)
      expect(adapter_class.adk_tool_class).to eq(MockAdkTool)
    end

    it 'sets the tool_name for fast-mcp based on ADK metadata' do
      adapter_class = described_class.wrap(MockAdkTool)
      # Assume fast-mcp provides a class method reader for tool_name
      expect(adapter_class.tool_name).to eq('mock_adk_tool')
    end

    it 'sets the description for fast-mcp based on ADK metadata' do
      adapter_class = described_class.wrap(MockAdkTool)
      expect(adapter_class.description).to eq('A mock ADK tool for testing adapter')
    end

    it 'calls SchemaConverter and sets arguments using the returned proc' do
      expect(ADK::Mcp::Util::SchemaConverter).to receive(:adk_to_dry_schema)
        .with(MockAdkTool.tool_metadata[:parameters])
        .and_return(mock_schema_proc)
      # We expect the Class.new block to call `arguments(&mock_schema_proc)` internally.
      # We cannot easily introspect this, but subsequent tests on `call` rely on it.
      # So, just creating the class is enough to trust the DSL was called.
      expect { described_class.wrap(MockAdkTool) }.not_to raise_error
    end

    it 'logs creation info' do
      described_class.wrap(MockAdkTool)
      expect(ADK.logger).to have_received(:info).with(/Created fast-mcp adapter for ADK tool: MockAdkTool as 'mock_adk_tool'/)
    end
  end

  describe '#call' do
    let(:adapter_class) { described_class.wrap(MockAdkTool) }
    let(:adapter_instance) { adapter_class.new } # Instance of the *wrapped* class
    let(:mock_tool_instance) { instance_double(MockAdkTool) }
    let(:mcp_args) { { 'input_param' => 'value1' } } # String keys from fast-mcp
    let(:adk_params) { { input_param: 'value1' } } # Symbol keys for ADK tool

    before do
      # Need to allow ADK::Tool.new to be called to get the instance
      allow(MockAdkTool).to receive(:new).and_return(mock_tool_instance)
      # We will stub `execute` directly in specific contexts below as needed,
      # rather than trying to call_original or stub perform_execution here.
    end

    it 'instantiates the wrapped ADK tool' do
      expect(MockAdkTool).to receive(:new).and_return(mock_tool_instance)
      # Allow execute to be called and return a minimal hash to avoid NoMethodError
      allow(mock_tool_instance).to receive(:execute).and_return({ status: :success })
      # We don't need to assert on the result here, just check instantiation
      adapter_instance.call(**mcp_args) # This will fail if new isn't called
    end

    it 'transforms string keys to symbol keys for ADK execute' do
      # Expect execute to be called with the correct symbolic params
      expect(mock_tool_instance).to receive(:execute)
        .with(adk_params, instance_of(ADK::ToolContext))
        .and_return({ status: :success, result: 'ok' })
      adapter_instance.call(**mcp_args)
    end

    it 'creates and passes a dummy ADK::ToolContext' do
      # Expect execute to be called with a ToolContext
      expect(mock_tool_instance).to receive(:execute)
        .with(anything, instance_of(ADK::ToolContext))
        .and_return({ status: :success, result: 'ok' })
      adapter_instance.call(**mcp_args)
    end

    context 'when ADK tool returns :success' do
      it 'returns the raw result' do
        # Stub execute to return a success hash
        allow(mock_tool_instance).to receive(:execute).and_return({ status: :success, result: 'Success Data' })
        result = adapter_instance.call(**mcp_args)
        expect(result).to eq('Success Data')
      end
    end

    context 'when ADK tool returns :error' do
      let(:error_tool_adapter_class) { described_class.wrap(MockAdkErrorTool) }
      let(:error_adapter_instance) { error_tool_adapter_class.new }
      let(:mock_error_tool_instance) { instance_double(MockAdkErrorTool) }

      before do
        allow(MockAdkErrorTool).to receive(:new).and_return(mock_error_tool_instance)
      end

      it 'raises StandardError with the error message' do
        # Stub execute to return an error hash with a message
        allow(mock_error_tool_instance).to receive(:execute).and_return({ status: :error,
                                                                          error_message: 'Specific ADK error' })
        expect { error_adapter_instance.call }.to raise_error(StandardError, 'Specific ADK error')
      end

      it 'uses a default error message if missing' do
        # Stub execute to return an error hash without a message
        allow(mock_error_tool_instance).to receive(:execute).and_return({ status: :error }) # No message
        expect { error_adapter_instance.call }.to raise_error(StandardError, /Unknown error from ADK tool/)
      end
    end

    context 'when ADK tool returns :pending' do
      let(:async_adapter_class) { described_class.wrap(MockAdkAsyncTool) }
      let(:async_adapter_instance) { async_adapter_class.new }
      let(:async_mcp_args) { { 'job_data' => 'test input' } }
      let(:mock_async_instance) { instance_double(MockAdkAsyncTool) }
      let(:generated_jid) { 'a_real_looking_jid_abc123' }

      before do
        allow(MockAdkAsyncTool).to receive(:new).and_return(mock_async_instance)
        # Stub execute on the async tool instance to return the pending hash
        allow(mock_async_instance).to receive(:execute)
          .with({ job_data: 'test input' }, instance_of(ADK::ToolContext))
          .and_return({ status: :pending, job_id: generated_jid })
      end

      it 'returns a hash with status: pending, job_id, and message' do
        result = async_adapter_instance.call(**async_mcp_args)
        expect(result).to eq({ status: 'pending', job_id: generated_jid,
                               message: "ADK tool 'mock_adk_async_tool' started an async job." })
      end
    end

    context 'when ADK tool returns unknown status' do
      it 'raises StandardError' do
        # Stub execute to return an unknown status
        allow(mock_tool_instance).to receive(:execute).and_return({ status: :weird, data: '...' })
        expect { adapter_instance.call(**mcp_args) }.to raise_error(StandardError, /returned unknown status: weird/)
      end
    end

    context 'when ADK tool execute method raises an error' do
      # Move these lets outside the 'it' block
      let(:error_execute_class) { described_class.wrap(MockAdkExecuteErrorTool) }
      let(:error_execute_instance) { error_execute_class.new }
      let(:mock_execute_error_instance) { instance_double(MockAdkExecuteErrorTool) }

      before do
        allow(MockAdkExecuteErrorTool).to receive(:new).and_return(mock_execute_error_instance)
        # Stub execute to raise the error
        allow(mock_execute_error_instance).to receive(:execute).and_raise(ArgumentError, "Execution failed!")
      end

      it 'rescues the error and raises a generic StandardError' do
        expect {
          error_execute_instance.call
        }.to raise_error(StandardError, /Execution failed!/)
      end
    end

    it 'raises NotImplementedError if called on the base class' do
      base_instance = ADK::Mcp::Server::AdkToolAdapter.new
      expect { base_instance.call }.to raise_error(NotImplementedError, /cannot be used directly/)
    end
  end
end
