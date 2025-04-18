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
  define_metadata(
    name: :mock_tool,
    description: 'A simple mock tool',
    parameters: {
      param1: { type: :string, required: true, description: 'First param' },
      param2: { type: :integer, required: false, description: 'Second param' }
    }
  )

  # Allow mocking execute
  def execute(params, context)
    # Default implementation, tests will mock this
    { status: :success, result: "Executed with #{params.inspect}" }
  end
end

class MockAdkAsyncTool < ADK::Tool
  define_metadata(
    name: :mock_async_tool,
    description: 'A mock async tool',
    parameters: { input: { type: :string, required: true, description: 'Input string' } }
  )

  def execute(params, context)
    { status: :pending, job_id: 'job-123', message: 'Job started' }
  end
end

class MockAdkErrorTool < ADK::Tool
  define_metadata(
    name: :mock_error_tool,
    description: 'A mock tool that returns an error',
    parameters: {}
  )

  def execute(params, context)
    { status: :error, error_message: 'Something went wrong' }
  end
end

class MockAdkExecuteErrorTool < ADK::Tool
  define_metadata(
    name: :mock_execute_error_tool,
    description: 'A mock tool that raises an error during execute',
    parameters: {}
  )

  def execute(params, context)
    raise ArgumentError, "Bad argument within execute"
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
      expect(adapter_class.tool_name).to eq('mock_tool')
    end

    it 'sets the description for fast-mcp based on ADK metadata' do
      adapter_class = described_class.wrap(MockAdkTool)
      expect(adapter_class.description).to eq('A simple mock tool')
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
      expect(ADK.logger).to have_received(:info).with(/Created fast-mcp adapter for ADK tool: MockAdkTool as 'mock_tool'/)
    end
  end

  describe '#call' do
    let(:adapter_class) { described_class.wrap(MockAdkTool) }
    let(:adapter_instance) { adapter_class.new } # Instance of the *wrapped* class
    let(:mock_tool_instance) { instance_double(MockAdkTool) }
    let(:mcp_args) { { 'param1' => 'value1', 'param2' => 42 } } # String keys from fast-mcp
    let(:adk_params) { { param1: 'value1', param2: 42 } } # Symbol keys for ADK tool

    before do
      # Stub the instantiation of the underlying ADK tool
      allow(MockAdkTool).to receive(:new).and_return(mock_tool_instance)
      # Stub SecureRandom.uuid for predictable context
      allow(SecureRandom).to receive(:uuid).and_return('dummy-session-id')
    end

    it 'instantiates the wrapped ADK tool' do
      expect(MockAdkTool).to receive(:new).and_return(mock_tool_instance)
      allow(mock_tool_instance).to receive(:execute).and_return({ status: :success, result: 'ok' })
      adapter_instance.call(**mcp_args)
    end

    it 'transforms string keys to symbol keys for ADK execute' do
      expect(mock_tool_instance).to receive(:execute)
        .with(adk_params, instance_of(ADK::ToolContext))
        .and_return({ status: :success, result: 'ok' })
      adapter_instance.call(**mcp_args)
    end

    it 'creates and passes a dummy ADK::ToolContext' do
      expect(mock_tool_instance).to receive(:execute)
        .with(anything, instance_of(ADK::ToolContext))
        .and_return({ status: :success, result: 'ok' })

      # Verify context content
      expect(ADK::ToolContext).to receive(:new)
        .with(session_id: 'dummy-session-id',
              user_id: 'mcp_user',
              app_name: 'mcp_server',
              tool_registry: instance_of(ADK::ToolRegistry))
        .and_call_original
      adapter_instance.call(**mcp_args)
    end

    context 'when ADK tool returns :success' do
      it 'returns the raw result' do
        expect(mock_tool_instance).to receive(:execute).and_return({ status: :success, result: 'Success Data' })
        result = adapter_instance.call(**mcp_args)
        expect(result).to eq('Success Data')
      end
    end

    context 'when ADK tool returns :error' do
      it 'raises StandardError with the error message' do
        error_tool_adapter_class = described_class.wrap(MockAdkErrorTool)
        error_adapter_instance = error_tool_adapter_class.new
        expect { error_adapter_instance.call }.to raise_error(StandardError, 'Something went wrong')
      end

      it 'uses a default error message if missing' do
        allow(mock_tool_instance).to receive(:execute).and_return({ status: :error })
        expect { adapter_instance.call }.to raise_error(StandardError, /Unknown error from ADK tool/)
      end
    end

    context 'when ADK tool returns :pending' do
      let(:async_adapter_class) { described_class.wrap(MockAdkAsyncTool) }
      let(:async_adapter_instance) { async_adapter_class.new }
      let(:async_mcp_args) { { 'input' => 'test input' } }

      it 'returns a hash with status: pending, job_id, and message' do
        result = async_adapter_instance.call(**async_mcp_args)
        expect(result).to eq({ status: 'pending', job_id: 'job-123', message: 'Job started' })
      end
    end

    context 'when ADK tool returns unknown status' do
      it 'raises StandardError' do
        allow(mock_tool_instance).to receive(:execute).and_return({ status: :weird, data: '...' })
        expect { adapter_instance.call(**mcp_args) }.to raise_error(StandardError, /returned unknown status: weird/)
      end
    end

    context 'when ADK tool execute method raises an error' do
      it 'rescues the error and raises a generic StandardError' do
        error_execute_adapter_class = described_class.wrap(MockAdkExecuteErrorTool)
        error_execute_instance = error_execute_adapter_class.new
        expect {
          error_execute_instance.call
        }.to raise_error(StandardError, /Execution Error in ADK tool.*Bad argument within execute/)
      end
    end

    it 'raises NotImplementedError if called on the base class' do
      base_instance = ADK::Mcp::Server::AdkToolAdapter.new
      expect { base_instance.call }.to raise_error(NotImplementedError, /cannot be used directly/)
    end
  end
end
