# frozen_string_literal: true

require 'spec_helper'
require 'adk/cli/tool_commands'
require 'adk/global_tool_manager'
require 'adk/tool_context'
require 'stringio'
require 'thor/shell/basic'

# Define a Mock Tool class for testing
class MockCliTestTool < ADK::Tool
  tool_description 'A mock tool for CLI tool command tests.'

  parameter :param1, type: :string, description: 'First parameter', required: true
  parameter :param2, type: :string, description: 'Second parameter', required: false

  def perform_execution(params, _context)
    if params[:param1] == 'error'
      raise ADK::ToolError, 'Simulated tool error'
    elsif params[:param1] == 'pending'
      { status: :pending, job_id: 'job-123', message: 'Job started' }
    else
      { status: :success, result: "Executed with #{params[:param1]} and #{params[:param2]}" }
    end
  end
end

RSpec.describe ADK::CLI::ToolCommands do
  let(:commands) { described_class.new }
  let(:output) { StringIO.new }
  let(:shell) { Thor::Shell::Basic.new }

  before do
    # Configure shell to capture output
    allow(shell).to receive(:stdout).and_return(output)
    allow(shell).to receive(:stderr).and_return(output)
    commands.shell = shell

    # Mock ADK::GlobalToolManager methods (the actual class used by ToolCommands)
    allow(ADK::GlobalToolManager).to receive(:list_all_tools).and_return([])
    allow(ADK::GlobalToolManager).to receive(:create_instance).and_return(nil)

    # Mock exit to prevent aborting the test suite
    allow(commands).to receive(:exit)
  end

  # Helper to invoke Thor command
  def invoke_command(command_name, *args)
    commands.invoke(command_name, args)
  rescue SystemExit
    # Captured
  end

  describe '#list' do
    context 'when no tools are registered' do
      it 'prints "No tools registered"' do
        invoke_command(:list)
        expect(output.string).to include('No tools registered.')
      end
    end

    context 'when tools are registered' do
      let(:tool_list) do
        [
          { name: :mock_tool, description: 'A mock tool' },
          { name: :another_tool, description: 'Another tool' }
        ]
      end

      before do
        allow(ADK::GlobalToolManager).to receive(:list_all_tools).and_return(tool_list)
      end

      it 'lists the available tools' do
        invoke_command(:list)
        expect(output.string).to include('Available tools:')
        expect(output.string).to include('- mock_tool: A mock tool')
        expect(output.string).to include('- another_tool: Another tool')
      end
    end
  end

  describe '#info' do
    context 'when tool does not exist' do
      it 'prints not found error' do
        invoke_command(:info, 'non_existent')
        expect(output.string).to include("Tool 'non_existent' not found in registry.")
      end
    end

    context 'when tool exists' do
      let(:tool_instance) { MockCliTestTool.new }

      before do
        allow(ADK::GlobalToolManager).to receive(:create_instance).with(:mock_tool).and_return(tool_instance)
        # Ensure name is consistent for test
        allow(tool_instance).to receive(:name).and_return(:mock_tool)
      end

      it 'prints tool information' do
        invoke_command(:info, 'mock_tool')
        expect(output.string).to include('Tool: mock_tool')
        expect(output.string).to include('Description: A mock tool for CLI tool command tests.')
        expect(output.string).to include('Parameters:')
        expect(output.string).to include('- param1 (string, required)')
        expect(output.string).to include('- param2 (string, optional)')
      end
    end
  end

  describe '#execute' do
    let(:tool_instance) { MockCliTestTool.new }

    before do
      allow(ADK::GlobalToolManager).to receive(:create_instance).with(:mock_tool).and_return(tool_instance)
    end

    context 'when tool does not exist' do
      before do
        allow(ADK::GlobalToolManager).to receive(:create_instance).with(:unknown).and_return(nil)
      end

      it 'prints error and exits' do
        invoke_command(:execute, 'unknown')
        expect(output.string).to include("Tool 'unknown' not found in registry.")
      end
    end

    context 'when tool exists' do
      it 'executes successfully with key=value parameters' do
        invoke_command(:execute, 'mock_tool', 'param1=value1', 'param2=value2')

        expect(output.string).to include("Executing tool 'mock_tool'")
        expect(output.string).to include('Success:')
        expect(output.string).to include('Output: Executed with value1 and value2')
      end

      it 'ignores invalid parameters and warns' do
        invoke_command(:execute, 'mock_tool', 'param1=value1', 'invalid=foo')

        expect(output.string).to include("Warning: Provided parameter 'invalid' is not defined")
        expect(output.string).to include("Parsed: param1 = 'value1'")
      end

      it 'suggests corrections for invalid parameters' do
        invoke_command(:execute, 'mock_tool', 'param1=value1', 'pram2=value2')

        expect(output.string).to include("Warning: Provided parameter 'pram2' is not defined")
        expect(output.string).to include("Did you mean 'param2'?")
      end

      it 'handles single argument as required parameter if applicable' do
        # MockCliTestTool has param1 as required, but it also has param2
        # The logic in ToolCommands:
        # if args.length == 1 && tool.parameters.length == 1 && tool.parameters.values.first[:required]
        # So it won't trigger for MockCliTestTool because it has 2 params

        # Let's mock a tool with single required param
        single_param_tool = double('SingleParamTool',
                                   name: :single,
                                   parameters: { input: { type: :string, required: true } },
                                   execute: { status: :success, result: 'ok' })
        allow(ADK::GlobalToolManager).to receive(:create_instance).with(:single).and_return(single_param_tool)

        invoke_command(:execute, 'single', 'test_input')
        expect(output.string).to include("Assuming single argument 'test_input' maps to required parameter 'input'")
      end

      it 'reports error when tool execution fails' do
        invoke_command(:execute, 'mock_tool', 'param1=error')

        # New format uses output_error which doesn't have "Error executing tool:" prefix
        expect(output.string).to include('Simulated tool error')
      end

      it 'reports pending status correctly' do
        invoke_command(:execute, 'mock_tool', 'param1=pending')

        expect(output.string).to include('Pending:')
        expect(output.string).to include('Job ID: job-123')
      end

      it 'handles unexpected errors gracefully' do
        allow(tool_instance).to receive(:execute).and_raise(StandardError, 'Unexpected crash')
        invoke_command(:execute, 'mock_tool', 'param1=test')

        # New format uses output_error
        expect(output.string).to include('Unexpected crash')
      end
    end
  end
end
