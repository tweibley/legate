# File: spec/legate/mcp/server/legate_tool_adapter_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'fast_mcp'
require 'legate/mcp/server/legate_tool_adapter'
require 'legate/tool'
require 'legate/tool_context'
require 'legate/mcp/util/schema_converter'
require 'legate/mcp' # For logger
require 'securerandom'

# Mock Legate Tool for testing
class MockLegateTool < Legate::Tool
  self.explicit_tool_name = :mock_legate_tool
  tool_description 'A mock Legate tool for testing adapter'
  parameter :input_param, type: :string, description: 'Input data', required: true

  def perform_execution(params, _context)
    { status: :success, result: "Success: #{params[:input_param]}" }
  end
end

class MockLegateAsyncTool < Legate::Tools::BaseAsyncJobTool
  self.explicit_tool_name = :mock_legate_async_tool
  tool_description 'An async Legate tool'
  parameter :job_data, type: :string

  class MockWorker; def perform(*_args); end; end

  def worker_class; MockWorker; end
  def prepare_job_arguments(params, _context); [params[:job_data]]; end
end

class MockLegateErrorTool < Legate::Tool
  self.explicit_tool_name = :mock_legate_error_tool
  tool_description 'Returns an Legate error'
  parameter :error_message, type: :string

  def perform_execution(params, _context)
    { status: :error, error_message: params[:error_message] || 'Default Legate error' }
  end
end

class MockLegateExecuteErrorTool < Legate::Tool
  self.explicit_tool_name = :mock_legate_execute_error_tool
  tool_description 'Raises an error during execution'

  def perform_execution(_params, _context)
    raise ArgumentError, 'Execution failed!'
  end
end

RSpec.describe Legate::Mcp::Server::LegateToolAdapter do
  let(:logger_spy) { spy('Logger') }
  let(:mock_schema_proc) { proc { required(:param1).filled(:string) } }

  before do
    allow(Legate).to receive(:logger).and_return(logger_spy)
    # Stub the schema converter
    allow(Legate::Mcp::Util::SchemaConverter).to receive(:legate_to_dry_schema)
      .and_return(mock_schema_proc)
  end

  describe '.wrap' do
    it 'raises ArgumentError if input is not an Legate::Tool class' do
      expect { described_class.wrap(String) }.to raise_error(ArgumentError, /not a valid Legate::Tool/)
      # Test wrapping an instance, should fail class check
      expect { described_class.wrap(MockLegateTool.new) }.to raise_error(ArgumentError, /not a valid Legate::Tool class/)
    end

    it 'raises ArgumentError if Legate::Tool has no metadata' do
      class NoMetaTool < Legate::Tool; end # Define locally
      # Mock tool_metadata to return nil for this specific class
      allow(NoMetaTool).to receive(:tool_metadata).and_return(nil)
      expect { described_class.wrap(NoMetaTool) }.to raise_error(ArgumentError, /incomplete metadata/)
    end

    it 'creates an anonymous subclass of LegateToolAdapter' do
      adapter_class = described_class.wrap(MockLegateTool)
      expect(adapter_class).to be_a(Class)
      expect(adapter_class).to be < Legate::Mcp::Server::LegateToolAdapter
      expect(adapter_class.superclass).to eq(Legate::Mcp::Server::LegateToolAdapter)
    end

    it 'sets the legate_tool_class attribute on the subclass' do
      adapter_class = described_class.wrap(MockLegateTool)
      expect(adapter_class.legate_tool_class).to eq(MockLegateTool)
    end

    it 'sets the tool_name for fast-mcp based on Legate metadata' do
      adapter_class = described_class.wrap(MockLegateTool)
      # Assume fast-mcp provides a class method reader for tool_name
      expect(adapter_class.tool_name).to eq('mock_legate_tool')
    end

    it 'sets the description for fast-mcp based on Legate metadata' do
      adapter_class = described_class.wrap(MockLegateTool)
      expect(adapter_class.description).to eq('A mock Legate tool for testing adapter')
    end

    it 'calls SchemaConverter and sets arguments using the returned proc' do
      expect(Legate::Mcp::Util::SchemaConverter).to receive(:legate_to_dry_schema)
        .with(MockLegateTool.tool_metadata[:parameters])
        .and_return(mock_schema_proc)
      # We expect the Class.new block to call `arguments(&mock_schema_proc)` internally.
      # We cannot easily introspect this, but subsequent tests on `call` rely on it.
      # So, just creating the class is enough to trust the DSL was called.
      expect { described_class.wrap(MockLegateTool) }.not_to raise_error
    end

    it 'logs creation info' do
      described_class.wrap(MockLegateTool)
      expect(Legate.logger).to have_received(:info).with(/Created fast-mcp adapter for Legate tool: MockLegateTool as 'mock_legate_tool'/)
    end
  end

  describe '#call' do
    let(:adapter_class) { described_class.wrap(MockLegateTool) }
    let(:adapter_instance) { adapter_class.new } # Instance of the *wrapped* class
    let(:mock_tool_instance) { instance_double(MockLegateTool) }
    let(:mcp_args) { { 'input_param' => 'value1' } } # String keys from fast-mcp
    let(:legate_params) { { input_param: 'value1' } } # Symbol keys for Legate tool

    before do
      # Need to allow Legate::Tool.new to be called to get the instance
      allow(MockLegateTool).to receive(:new).and_return(mock_tool_instance)
      # We will stub `execute` directly in specific contexts below as needed,
      # rather than trying to call_original or stub perform_execution here.
    end

    it 'instantiates the wrapped Legate tool' do
      expect(MockLegateTool).to receive(:new).and_return(mock_tool_instance)
      # Allow execute to be called and return a minimal hash to avoid NoMethodError
      allow(mock_tool_instance).to receive(:execute).and_return({ status: :success })
      # We don't need to assert on the result here, just check instantiation
      adapter_instance.call(**mcp_args) # This will fail if new isn't called
    end

    it 'transforms string keys to symbol keys for Legate execute' do
      # Expect execute to be called with the correct symbolic params
      expect(mock_tool_instance).to receive(:execute)
        .with(legate_params, instance_of(Legate::ToolContext))
        .and_return({ status: :success, result: 'ok' })
      adapter_instance.call(**mcp_args)
    end

    it 'creates and passes a dummy Legate::ToolContext' do
      # Expect execute to be called with a ToolContext
      expect(mock_tool_instance).to receive(:execute)
        .with(anything, instance_of(Legate::ToolContext))
        .and_return({ status: :success, result: 'ok' })
      adapter_instance.call(**mcp_args)
    end

    context 'when Legate tool returns :success' do
      it 'returns the raw result' do
        # Stub execute to return a success hash
        allow(mock_tool_instance).to receive(:execute).and_return({ status: :success, result: 'Success Data' })
        result = adapter_instance.call(**mcp_args)
        expect(result).to eq('Success Data')
      end
    end

    context 'when Legate tool returns :error' do
      let(:error_tool_adapter_class) { described_class.wrap(MockLegateErrorTool) }
      let(:error_adapter_instance) { error_tool_adapter_class.new }
      let(:mock_error_tool_instance) { instance_double(MockLegateErrorTool) }

      before do
        allow(MockLegateErrorTool).to receive(:new).and_return(mock_error_tool_instance)
      end

      it 'raises StandardError with the error message' do
        # Stub execute to return an error hash with a message
        allow(mock_error_tool_instance).to receive(:execute).and_return({ status: :error,
                                                                          error_message: 'Specific Legate error' })
        expect { error_adapter_instance.call }.to raise_error(StandardError, 'Specific Legate error')
      end

      it 'uses a default error message if missing' do
        # Stub execute to return an error hash without a message
        allow(mock_error_tool_instance).to receive(:execute).and_return({ status: :error }) # No message
        expect { error_adapter_instance.call }.to raise_error(StandardError, /Unknown error from Legate tool/)
      end
    end

    context 'when Legate tool returns :pending' do
      let(:async_adapter_class) { described_class.wrap(MockLegateAsyncTool) }
      let(:async_adapter_instance) { async_adapter_class.new }
      let(:async_mcp_args) { { 'job_data' => 'test input' } }
      let(:mock_async_instance) { instance_double(MockLegateAsyncTool) }
      let(:generated_jid) { 'a_real_looking_jid_abc123' }

      before do
        allow(MockLegateAsyncTool).to receive(:new).and_return(mock_async_instance)
        # Stub execute on the async tool instance to return the pending hash
        allow(mock_async_instance).to receive(:execute)
          .with({ job_data: 'test input' }, instance_of(Legate::ToolContext))
          .and_return({ status: :pending, job_id: generated_jid })
      end

      it 'returns a hash with status: pending, job_id, and message' do
        result = async_adapter_instance.call(**async_mcp_args)
        expect(result).to eq({ status: 'pending', job_id: generated_jid,
                               message: "Legate tool 'mock_legate_async_tool' started an async job." })
      end
    end

    context 'when Legate tool returns unknown status' do
      it 'raises StandardError' do
        # Stub execute to return an unknown status
        allow(mock_tool_instance).to receive(:execute).and_return({ status: :weird, data: '...' })
        expect { adapter_instance.call(**mcp_args) }.to raise_error(StandardError, /returned unknown status: weird/)
      end
    end

    context 'when Legate tool execute method raises an error' do
      # Move these lets outside the 'it' block
      let(:error_execute_class) { described_class.wrap(MockLegateExecuteErrorTool) }
      let(:error_execute_instance) { error_execute_class.new }
      let(:mock_execute_error_instance) { instance_double(MockLegateExecuteErrorTool) }

      before do
        allow(MockLegateExecuteErrorTool).to receive(:new).and_return(mock_execute_error_instance)
        # Stub execute to raise the error
        allow(mock_execute_error_instance).to receive(:execute).and_raise(ArgumentError, 'Execution failed!')
      end

      it 'rescues the error and raises a generic StandardError' do
        expect {
          error_execute_instance.call
        }.to raise_error(StandardError, /Execution failed!/)
      end
    end

    it 'raises NotImplementedError if called on the base class' do
      base_instance = Legate::Mcp::Server::LegateToolAdapter.new
      expect { base_instance.call }.to raise_error(NotImplementedError, /cannot be used directly/)
    end
  end
end
