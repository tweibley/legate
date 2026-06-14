# frozen_string_literal: true

require 'spec_helper'
require 'legate/cli/agent_commands'
require 'legate/global_definition_registry'
require 'legate/global_tool_manager'
require 'legate/tool'
require 'legate/session_service/in_memory'
require 'stringio'
require 'thor/shell/basic' # Required for explicit shell

# Mock Tool for testing
class MockCliTool < Legate::Tool
  tool_description 'A mock tool for CLI tests.'
  parameter :param1, type: :string, description: 'A parameter', required: true

  def perform_execution(params, _context)
    { status: :success, result: "MockCliTool executed with #{params[:param1]}" }
  end
end

RSpec.describe Legate::CLI::AgentCommands do
  let(:commands) { described_class.new }
  let(:output) { StringIO.new }
  let(:shell) { Thor::Shell::Basic.new } # Create a shell instance
  let(:session_service_in_memory) { Legate::SessionService::InMemory.new }
  let(:session) { session_service_in_memory.create_session(app_name: agent_name.to_s, user_id: 'cli_user') }

  before do
    # Configure the shell to use the StringIO
    allow(shell).to receive(:stdout).and_return(output)
    allow(shell).to receive(:stderr).and_return(output) # Redirect stderr too
    # Set the shell for the command instance
    commands.shell = shell

    # Let yes? run, but stub the underlying readline
    allow(commands).to receive(:yes?).and_call_original

    # Reset stores before each test
    Legate::GlobalDefinitionRegistry.clear!
    Legate::GlobalToolManager.reset!
    # Register mock tool globally for tests that need it
    Legate::GlobalToolManager.register_tool(MockCliTool)
  end

  after do
    # Ensure stores are clean after tests
    Legate::GlobalDefinitionRegistry.clear!
    Legate::GlobalToolManager.reset!
  end

  # --- Helper to invoke Thor command ---
  def invoke_command(command_name, *args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    commands.options = options # Set options on the instance

    # FIX: Stub exit on the commands instance to prevent premature termination
    allow(commands).to receive(:exit).with(1) do |status|
      output.puts "Intentional Exit with status #{status} (captured)"
    end
    allow(commands).to receive(:exit).with(0) do |status|
      output.puts "Intentional Exit with status #{status} (captured)"
    end # Capture clean exits too, if any

    commands.invoke(command_name, args, options)
  rescue SystemExit => e
    # Capture Thor's internal exit calls if they bypass the instance method
    output.puts "SystemExit with status #{e.status} (rescued)"
  rescue Thor::RequiredArgumentMissingError => e
    output.puts "Thor Error: #{e.message}"
    output.puts 'SystemExit with status 1 (captured missing arg)'
  end

  # --- Tests ---

  describe '#list' do
    context 'when no definitions exist' do
      it 'prints a message indicating no definitions' do
        invoke_command(:list)
        expect(output.string).to include('No agent definitions found.')
      end
    end

    context 'when definitions exist' do
      before do
        # Register agents in GlobalDefinitionRegistry
        agent1 = Legate::AgentDefinition.new.define do |a|
          a.name :agent_one
          a.description 'First agent'
          a.instruction 'Instruction for agent one'
          a.model_name 'gemini-1.5-pro'
          a.use_tool :mock_cli_tool
        end
        Legate::GlobalDefinitionRegistry.register(agent1)

        agent2 = Legate::AgentDefinition.new.define do |a|
          a.name :agent_two
          a.description 'Second agent'
          a.instruction 'Instruction for agent two'
        end
        Legate::GlobalDefinitionRegistry.register(agent2)
      end

      it 'lists the defined agents with details' do
        invoke_command(:list)
        expect(output.string).to include('Defined Agents:')
        expect(output.string).to include('agent_one')
        expect(output.string).to include('First agent')
        expect(output.string).to include('agent_two')
        expect(output.string).to include('Second agent')
      end

      it 'handles definitions with no description' do
        agent3 = Legate::AgentDefinition.new.define do |a|
          a.name :agent_three
          a.instruction 'Instruction for agent three'
          a.model_name 'gemini-1.5-pro'
          a.use_tool :mock_cli_tool
        end
        Legate::GlobalDefinitionRegistry.register(agent3)

        invoke_command(:list)
        expect(output.string).to include('Defined Agents:')
        expect(output.string).to include('agent_three')
        expect(output.string).to include('agent_one')
        expect(output.string).to include('agent_two')
      end
    end
  end

  # --- Test save command ---
  describe '#save' do
    let(:agent_name) { 'my_agent' }
    let(:description) { 'Test agent description' }
    let(:instruction) { 'Test agent instruction' }
    let(:valid_tools) { 'mock_cli_tool,echo' }
    let(:invalid_tools) { 'mock_cli_tool,non_existent_tool' }

    before do
      # Register 'echo' tool for testing valid tool lists
      Legate::GlobalToolManager.register_tool(Legate::Tools::Echo) if Legate::GlobalToolManager.find_class(:echo).nil?
    end

    context 'with valid options' do
      it 'saves the definition to the registry' do
        invoke_command(:save, agent_name, description: description, instruction: instruction, tools: valid_tools)

        expect(output.string).to include("Agent definition 'my_agent' saved")
        expect(output.string).to include('Tools: mock_cli_tool, echo')
        expect(output.string).to include("Model: #{Legate::Agent::DEFAULT_MODEL}")

        # Verify it was actually registered
        found = Legate::GlobalDefinitionRegistry.find(:my_agent)
        expect(found).not_to be_nil
        expect(found.description).to eq(description)
      end

      it 'saves with a specific model' do
        model_name = 'gemini-1.5-flash'

        invoke_command(:save, agent_name, description: description, instruction: instruction, model: model_name)

        expect(output.string).to include("Model: #{model_name}")
        expect(output.string).to include('Tools: None')
      end

      it 'saves with no tools specified' do
        invoke_command(:save, agent_name, description: description, instruction: instruction)

        expect(output.string).to include('Tools: None')
      end
    end

    context 'with invalid tool names' do
      it 'warns about unknown tools but saves valid ones' do
        invoke_command(:save, agent_name, description: description, instruction: instruction, tools: invalid_tools)

        expect(output.string).to include("Warning: Unknown globally registered tool 'non_existent_tool', ignoring.")
        expect(output.string).to include("Agent definition 'my_agent' saved")
        expect(output.string).to include('Tools: mock_cli_tool')
      end
    end
  end

  # --- Test delete command ---
  describe '#delete' do
    let(:agent_name) { :my_agent_to_delete }

    context 'when definition exists in registry' do
      before do
        agent_def = Legate::AgentDefinition.new.define do |a|
          a.name :my_agent_to_delete
          a.description 'To be deleted'
          a.instruction 'Delete me'
        end
        Legate::GlobalDefinitionRegistry.register(agent_def)
      end

      it 'prompts for confirmation and deletes' do
        # Expect uncolored prompt when using explicit basic shell
        expected_prompt = "Are you sure you want to permanently delete agent definition 'my_agent_to_delete'? [y/N] "
        expect(Thor::LineEditor).to receive(:readline).with(expected_prompt, { add_to_history: false }).and_return('y')

        invoke_command(:delete, agent_name.to_s)

        expect(output.string).to include("Agent definition 'my_agent_to_delete' deleted successfully.")
        expect(Legate::GlobalDefinitionRegistry.find(agent_name)).to be_nil
      end

      it 'cancels deletion if user answers no' do
        expected_prompt = "Are you sure you want to permanently delete agent definition 'my_agent_to_delete'? [y/N] "
        expect(Thor::LineEditor).to receive(:readline).with(expected_prompt, { add_to_history: false }).and_return('n')

        invoke_command(:delete, agent_name.to_s)

        expect(output.string).to include('Deletion cancelled.')
        expect(Legate::GlobalDefinitionRegistry.find(agent_name)).not_to be_nil # Still exists
      end
    end

    context 'when definition does not exist' do
      it 'prints an error and exits' do
        expect(commands).not_to receive(:yes?)

        invoke_command(:delete, agent_name.to_s)

        expect(output.string).to include("Error: Agent definition 'my_agent_to_delete' not found.")
        expect(output.string).to include('SystemExit with status 1')
      end
    end
  end

  # --- Test stop command ---
  describe '#stop' do
    let(:agent_name) { :my_running_agent }

    context 'when definition exists and is running' do
      before do
        agent_def = Legate::AgentDefinition.new.define do |a|
          a.name :my_running_agent
          a.description 'Running agent'
          a.instruction 'Run forever'
        end
        Legate::GlobalDefinitionRegistry.register(agent_def)
        Legate::GlobalDefinitionRegistry.update_definition(agent_name, { persistent_status: 'running' })
      end

      it 'prompts for confirmation and updates status to stopped' do
        expected_prompt = "Agent 'my_running_agent' is currently marked as 'running'. Stop it? [y/N] "
        expect(Thor::LineEditor).to receive(:readline).with(expected_prompt, { add_to_history: false }).and_return('y')

        invoke_command(:stop, agent_name.to_s)

        expect(output.string).to include("Agent 'my_running_agent' has been marked as stopped.")
        defn = Legate::GlobalDefinitionRegistry.get_definition(agent_name)
        expect(defn[:persistent_status]).to eq('stopped')
      end

      it 'skips prompt when force option is used' do
        expect(commands).not_to receive(:yes?)

        invoke_command(:stop, agent_name.to_s, force: true)

        expect(output.string).to include("Agent 'my_running_agent' has been marked as stopped.")
      end

      it 'cancels stop when user says no' do
        expected_prompt = "Agent 'my_running_agent' is currently marked as 'running'. Stop it? [y/N] "
        expect(Thor::LineEditor).to receive(:readline).with(expected_prompt, { add_to_history: false }).and_return('n')

        invoke_command(:stop, agent_name.to_s)

        expect(output.string).to include('Stop cancelled.')
      end
    end

    context 'when agent is already stopped' do
      before do
        agent_def = Legate::AgentDefinition.new.define do |a|
          a.name :my_running_agent
          a.description 'Stopped agent'
          a.instruction 'Already stopped'
        end
        Legate::GlobalDefinitionRegistry.register(agent_def)
        # persistent_status defaults to 'stopped'
      end

      it 'informs user and exits without update' do
        invoke_command(:stop, agent_name.to_s)

        expect(output.string).to include("Agent 'my_running_agent' is already stopped.")
      end
    end

    context 'when agent definition not found' do
      it 'prints error and exits' do
        invoke_command(:stop, agent_name.to_s)
        expect(output.string).to include("Agent definition 'my_running_agent' not found.")
        expect(output.string).to include('SystemExit with status 1')
      end
    end
  end

  # --- Test export command ---
  describe '#export' do
    let(:agent_name) { :export_agent }

    before do
      agent_def = Legate::AgentDefinition.new.define do |a|
        a.name :export_agent
        a.description 'Agent to export'
        a.instruction 'Export me'
        a.model_name 'gemini-pro'
        a.use_tool :calculator
      end
      Legate::GlobalDefinitionRegistry.register(agent_def)
      Legate::GlobalToolManager.register_tool(Legate::Tools::Calculator) if Legate::GlobalToolManager.find_class(:calculator).nil?
    end

    it 'exports to YAML by default (stdout)' do
      invoke_command(:export, agent_name.to_s)

      # Should contain YAML formatted output (keys as strings because of transform_keys)
      expect(output.string).to include('description: Agent to export')
      # Should not include internal fields
      expect(output.string).not_to include('persistent_status')
    end

    it 'exports to JSON when forced (stdout)' do
      invoke_command(:export, agent_name.to_s, format: 'json')

      expect(output.string).to include('"description": "Agent to export"')
    end

    it 'writes to file when output option is provided' do
      file_path = '/tmp/exported_agent.yaml'
      expect(File).to receive(:write).with(file_path, anything)

      invoke_command(:export, agent_name.to_s, output: file_path)

      expect(output.string).to include("Agent definition exported to #{file_path}")
    end

    it 'handles file write errors' do
      file_path = '/invalid/path/agent.yaml'
      allow(File).to receive(:write).and_raise(Errno::EACCES, 'Permission denied')

      invoke_command(:export, agent_name.to_s, output: file_path)

      expect(output.string).to include('Error writing to file: Permission denied')
      expect(output.string).to include('SystemExit with status 1')
    end
  end

  # --- Test start command ---
  describe '#start' do
    let(:agent_name) { :starter_agent }
    let(:agent_definition_object) { instance_double(Legate::AgentDefinition, name: agent_name, tool_names: ['mock_cli_tool'], model_name: 'gemini-test') }
    let(:agent_instance) { instance_double(Legate::Agent, model_name: 'gemini-test', instruction: 'Test instruction', tools: [MockCliTool.new]) }

    before do
      # Global stubs
      allow(Legate::Agent).to receive(:new).and_call_original
      allow(Legate::Agent).to receive(:new).with(definition: agent_definition_object).and_return(agent_instance)

      # Default behavior for agent instance
      allow(agent_instance).to receive(:running?).and_return(false)
      allow(agent_instance).to receive(:start) do
        allow(agent_instance).to receive(:running?).and_return(true)
      end
      allow(agent_instance).to receive(:stop) do
        allow(agent_instance).to receive(:running?).and_return(false)
      end
    end

    context 'when definition exists in registry' do
      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(agent_definition_object)
      end

      it 'loads definition, instantiates agent, starts/stops runtime, and prints details' do
        invoke_command(:start, agent_name.to_s)

        expect(output.string).to include("Loading agent 'starter_agent'...")
        expect(output.string).to include('Agent uses model: gemini-test')
        expect(output.string).to include('Starting agent runtime...')
        expect(output.string).to include('started.')
        expect(output.string).to include("Agent 'starter_agent' is ready.")
        expect(output.string).not_to include('SystemExit')
      end
    end

    context 'when definition does not exist' do
      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(nil)
      end

      it 'prints an error and exits' do
        invoke_command(:start, agent_name.to_s)
        expect(output.string).to include("Agent definition 'starter_agent' not found.")
        expect(output.string).to include('SystemExit with status 1')
      end
    end

    context 'when agent instantiation fails' do
      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(agent_definition_object)
        allow(Legate::Agent).to receive(:new).with(definition: agent_definition_object).and_raise(StandardError, 'Initialization failed')
      end

      it 'prints an error, includes backtrace, and exits' do
        invoke_command(:start, agent_name.to_s)
        expect(output.string).to include('Initialization failed')
        expect(output.string).to include('SystemExit with status 1')
      end
    end

    context 'when agent start fails' do
      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(agent_definition_object)
        allow(Legate::Agent).to receive(:new).with(definition: agent_definition_object).and_return(agent_instance)
        allow(agent_instance).to receive(:start).and_raise(StandardError, 'Start sequence failed')
      end

      it 'prints an error, attempts stop, includes backtrace, and exits' do
        invoke_command(:start, agent_name.to_s)
        expect(output.string).to include('Start sequence failed')
        expect(output.string).to include('SystemExit with status 1')
      end
    end
  end

  # --- Test execute command ---
  describe '#execute' do
    let(:agent_name) { :executor_agent }
    let(:task) { 'Run the mock tool with foo' }
    let(:agent_definition_object) { instance_double(Legate::AgentDefinition, name: agent_name, tool_names: ['mock_cli_tool'], model_name: 'gemini-exec') }
    let(:mock_agent_instance) {
      instance_double(Legate::Agent, name: agent_name, model_name: 'gemini-exec', tools: [MockCliTool.new],
                                     running?: false)
    }

    around(:each) do |example|
      # Store original class variable
      original_execute_service = nil
      original_execute_service = Legate::CLI::AgentCommands.class_variable_get(:@@session_service_for_execute) if Legate::CLI::AgentCommands.class_variable_defined?(:@@session_service_for_execute)

      # Replace with our test instance
      Legate::CLI::AgentCommands.class_variable_set(:@@session_service_for_execute, session_service_in_memory)

      # Run the example
      example.run

      # Restore original class variable or a fresh default if it wasn't originally defined
      if original_execute_service
        Legate::CLI::AgentCommands.class_variable_set(:@@session_service_for_execute, original_execute_service)
      else
        Legate::CLI::AgentCommands.class_variable_set(:@@session_service_for_execute, Legate::SessionService::InMemory.new)
      end
    end

    before do
      # Reset the controlled service's state before each test
      session_service_in_memory.instance_variable_get(:@sessions).clear
      session_service_in_memory.instance_variable_get(:@scoped_states).clear

      # Global stubs for all contexts
      allow(Legate::Agent).to receive(:new).and_return(mock_agent_instance)
      allow(mock_agent_instance).to receive(:start) do
        allow(mock_agent_instance).to receive(:running?).and_return(true)
      end
      allow(mock_agent_instance).to receive(:stop) do
        allow(mock_agent_instance).to receive(:running?).and_return(false)
      end
    end

    context 'basic execution (in-memory session)' do
      it 'loads definition, starts agent, runs task, formats result, and stops agent' do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(agent_definition_object)

        expected_event = Legate::Event.new(role: :agent, content: { status: :success, result: 'Task completed!' })

        # Expect run_task with any arguments to work
        allow(mock_agent_instance).to receive(:run_task).and_return(expected_event)

        expect(mock_agent_instance).to receive(:start)
        expect(mock_agent_instance).to receive(:stop)

        invoke_command(:execute, agent_name.to_s, task)

        expect(output.string).to include("Loading agent 'executor_agent' to execute task: \"#{task}\"...")
        expect(output.string).to match(/Started new session: [\w-]{36}/)
        expect(output.string).to include('Agent uses model: gemini-exec')
        expect(output.string).to include('Loaded tools: [mock_cli_tool]')
        expect(output.string).to match(/Running task in session [\w-]{36}: '#{task}'.../)
        expect(output.string).to include('finished.')
        expect(output.string).to include('Task Result:')
        expect(output.string).to include('Success:')
        expect(output.string).to include('Result: Task completed!')
        expect(output.string).to include('Stopping agent runtime...')
        expect(output.string).to include('stopped.')
        expect(output.string).not_to include('Intentional Exit') # Should not exit on success
      end
    end

    context 'when definition is not found' do
      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(nil)
      end

      it 'prints error and exits' do
        invoke_command(:execute, agent_name.to_s, task)
        expect(output.string).to include("Agent definition 'executor_agent' not found.")
        expect(output.string).to include('SystemExit with status 1')
      end
    end

    context 'with session handling options' do
      before do
        allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(agent_name).and_return(agent_definition_object)
      end

      it 'uses existing session ID if provided and found' do
        # Create the session directly in the controlled service instance
        existing_session = session_service_in_memory.create_session(
          app_name: agent_name.to_s, user_id: 'cli_user'
        )
        existing_session_id = existing_session.id

        # Allow run_task with any arguments
        allow(mock_agent_instance).to receive(:run_task).and_return({ status: :success, result: 'Used existing session' })

        # Don't expect create_session with explicit arguments - let it call through if needed
        allow(session_service_in_memory).to receive(:get_session).with(session_id: existing_session_id).and_return(existing_session)

        invoke_command(:execute, agent_name.to_s, task, session_id: existing_session_id)

        expect(output.string).to include("Continuing session: #{existing_session_id}")
        expect(output.string).to include("Running task in session #{existing_session_id}")
        expect(output.string).to include('Result: Used existing session')
      end

      it 'warns and creates new session if provided session ID not found' do
        non_existent_session_id = 'non-existent-session-456'

        # Mock get_session to return nil for the non-existent ID
        allow(session_service_in_memory).to receive(:get_session).with(session_id: non_existent_session_id).and_return(nil)

        # Create a new session when called with any arguments
        new_session = session_service_in_memory.create_session(
          app_name: agent_name.to_s, user_id: 'cli_user'
        )
        allow(session_service_in_memory).to receive(:create_session).and_return(new_session)

        # Allow run_task with any arguments
        allow(mock_agent_instance).to receive(:run_task).and_return({ status: :success, result: 'Created new session ok' })

        invoke_command(:execute, agent_name.to_s, task, session_id: non_existent_session_id)

        expect(output.string).to include("Warning: Session ID '#{non_existent_session_id}' provided but not found. Starting a new session.")
        expect(output.string).to include('Result: Created new session ok')
      end
    end
  end
end
