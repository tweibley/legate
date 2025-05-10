# frozen_string_literal: true

# File: spec/adk/agent_spec.rb
require 'spec_helper'
require 'adk/agent'
require 'adk/planner'
require 'adk/tool_registry'
require 'adk/session'
require 'adk/session_service/in_memory'
require 'adk/event'
require 'adk/tools/calculator' # Example tool
require 'adk/tools/echo'       # Example tool
require 'adk/tools/base_async_job_tool' # For job_id tests
require 'adk/tools/check_job_status_tool' # For job_id tests
require 'adk/errors'
require 'adk/mcp/client' # For MCP tests
require 'adk/mcp/tool_wrapper' # For MCP tests
require 'adk/global_tool_manager' # Required for mocking
require 'adk/global_definition_registry' # Required for mocking
require 'adk/definition_store/redis_store' # For mocking RedisStore directly

# --- Mock Tools ---
class MockTool < ADK::Tool
  tool_description 'A simple mock tool.'
  self.explicit_tool_name = :mock_tool
  parameter :input, type: :string, required: true

  def perform_execution(params, _context)
    { status: :success, result: "Mock tool processed: #{params[:input]}" }
  end
end

class MockAnotherTool < ADK::Tool
  tool_description 'Another mock tool.'
  self.explicit_tool_name = :another_tool
  parameter :value, type: :integer

  def perform_execution(params, _context)
    { status: :success, result: params[:value] * 2 }
  end
end

class MockToolNeedsContext < ADK::Tool
  tool_description 'A tool that uses context.'
  self.explicit_tool_name = :context_tool
  parameter :data, type: :string

  def perform_execution(params, context)
    { status: :success, result: "Context: #{context.session_id}, Data: #{params[:data]}" }
  end
end

class MockToolNoName < ADK::Tool
  # No tool_name defined
  tool_description 'A tool without an explicit name.'
  # No self.explicit_tool_name = ...
end

class MockToolWithPending < ADK::Tool
  tool_description 'A tool that can return pending status.'
  self.explicit_tool_name = :pending_tool
  parameter :job_request, type: :string

  def perform_execution(params, context)
    { status: :pending, job_id: "job-#{rand(1000)}", message: "Job submitted for #{params[:job_request]}" }
  end
end

class MockToolWithError < ADK::Tool
  tool_description 'A tool that always errors.'
  self.explicit_tool_name = :error_tool
  parameter :fail_message, type: :string

  def perform_execution(params, context)
    raise ADK::ToolError.new("Tool failed as requested: #{params[:fail_message]}", tool_name: :error_tool)
  end
end

class MockToolWithArgError < ADK::Tool
  tool_description 'A tool that raises argument errors.'
  self.explicit_tool_name = :arg_error_tool
  parameter :number, type: :integer, required: true

  def perform_execution(params, context)
    # Assume validation happens before this, but raise here for test
    raise ADK::ToolArgumentError, 'Invalid number provided' unless params[:number] > 0

    { status: :success, result: params[:number] }
  end
end

class MockToolInvalidResult < ADK::Tool
  tool_description 'A tool that returns invalid hash.'
  self.explicit_tool_name = :invalid_result_tool

  def perform_execution(params, context)
    'not a hash' # Invalid return
  end
end

class MockToolPreparationError < ADK::Tool
  tool_description 'A tool that errors during prepare_context.'
  self.explicit_tool_name = :prep_error_tool

  def prepare_context(context)
    raise StandardError, 'Preparation Boom!'
  end

  def perform_execution(params, context)
    { status: :success, result: 'Should not reach here' }
  end
end
# --- End Mock Tools ---

RSpec.describe ADK::Agent do
  let(:agent_name) { :test_agent }
  let(:agent_description) { 'A test agent.' }
  let(:model_name) { 'test_model' }
  let(:instruction) { 'You are a helpful test agent.' }
  let(:tool_classes) { [MockTool, MockAnotherTool] }
  let(:tool_paths) { [] } # Assume no path discovery by default
  let(:planner_double) { instance_double(ADK::Planner, plan: []) } # Use ADK::Planner
  let(:session_service_double) {
    instance_double(ADK::SessionService::InMemory, get_session: session_double, append_event: true)
  } # Back to InMemory
  let(:fake_history) { [] }
  let(:session_double) do
    instance_double(ADK::Session, id: session_id, user_id: 'user1', app_name: 'app1').tap do |double|
      allow(double).to receive(:events).and_return(fake_history)
      allow(double).to receive(:add_event) { |event| fake_history << event }
    end
  end
  let(:session_id) { "test_session_#{rand(1000)}" }
  let(:user_input) { 'Test user input' }
  let(:logger_double) { spy('Logger') } # Use spy for easier verification

  # Mocks for definition/global components
  let(:mock_definition) do
    instance_double(ADK::AgentDefinition,
                    name: agent_name,
                    description: agent_description,
                    instruction: instruction,
                    model_name: model_name,
                    tool_names: tool_classes.map { |tc|
                      tc.tool_metadata[:name].to_sym rescue nil
                    }.compact.to_set, # Get names from classes
                    fallback_mode: :error,
                    mcp_servers: [],
                    webhook_enabled: false,
                    webhook_validator: nil,
                    webhook_secret: nil,
                    webhook_transformer: nil,
                    webhook_session_extractor: nil)
  end
  let(:mock_store) { instance_double(ADK::DefinitionStore::RedisStore, save_definition: true, get_definition: nil) }
  let(:mock_registry) { class_double(ADK::GlobalDefinitionRegistry, register: nil, find: nil).as_stubbed_const }
  let(:mock_config) {
    instance_double(ADK::Configuration, definition_store: mock_store, session_service: session_service_double)
  }
  let(:mock_tool_manager) {
    class_double(ADK::GlobalToolManager, find_class: nil, registered_tool_names: [], reset!: true,
                                         register_tool: true).as_stubbed_const
  }

  # Standard agent initialization arguments
  let(:init_args) do
    {
      name: agent_name,
      description: agent_description,
      instruction: instruction,
      model_name: model_name,
      tool_classes: tool_classes,
      planner: planner_double,
      session_service: session_service_double # Provide directly for tests
    }
  end

  # Helper to create agent instance for tests using keyword args
  def create_agent(**overrides)
    # Ensure required args are present
    args = init_args.merge(overrides)
    args[:description] ||= 'Default description for test' # Ensure description if not in overrides
    ADK::Agent.new(**args)
  end

  # Helper to create agent instance from a definition object
  def create_agent_from_definition(def_double = mock_definition, **overrides)
    ADK::Agent.new(definition: def_double, session_service: session_service_double, **overrides)
  end

  before do
    allow(ADK).to receive(:logger).and_return(logger_double)
    # Mock global components
    allow(ADK).to receive(:config).and_return(mock_config)
    allow(mock_registry).to receive(:register)
    allow(mock_registry).to receive(:find) # Allow find to be called, default return nil
    allow(mock_store).to receive(:get_definition) # Allow get_definition, default return nil

    # Allow the mock definition to pass the is_a? check
    allow(mock_definition).to receive(:is_a?).with(ADK::AgentDefinition).and_return(true)

    # Mock GlobalToolManager calls used during initialization
    tool_classes.each do |tc|
      tool_name = tc.tool_metadata[:name].to_sym rescue nil # Get name safely from metadata
      allow(mock_tool_manager).to receive(:find_class).with(tool_name).and_return(tc) if tool_name
    end
    # Use metadata directly to get names for registered_tool_names mock
    tool_names_from_meta = tool_classes.map { |tc| tc.tool_metadata[:name].to_sym rescue nil }.compact
    allow(mock_tool_manager).to receive(:registered_tool_names).and_return(tool_names_from_meta)
  end

  describe '#initialize with definition:' do
    before do
      # Ensure the mock definition returns the expected tool names
      allow(mock_definition).to receive(:tool_names).and_return([:mock_tool, :another_tool])
      allow(mock_tool_manager).to receive(:find_class).with(:mock_tool).and_return(MockTool)
      allow(mock_tool_manager).to receive(:find_class).with(:another_tool).and_return(MockAnotherTool)
    end

    it 'sets attributes from the definition object' do
      agent = create_agent_from_definition
      expect(agent.name).to eq(agent_name)
      expect(agent.description).to eq(agent_description)
      expect(agent.instruction).to eq(instruction)
      expect(agent.model_name).to eq(model_name)
      expect(agent.definition).to eq(mock_definition)
    end

    it 'registers tools specified in the definition' do
      agent = create_agent_from_definition
      expect(agent.find_tool_class(:mock_tool)).to eq(MockTool)
      expect(agent.find_tool_class(:another_tool)).to eq(MockAnotherTool)
    end

    it 'ignores other keyword arguments if definition is provided' do
      # Pass conflicting args, expect them to be ignored
      agent = create_agent_from_definition(mock_definition, name: :other_name, description: 'other desc',
                                                            model_name: 'other_model')
      expect(agent.name).to eq(agent_name) # Should take from definition
      expect(agent.description).to eq(agent_description)
      expect(agent.model_name).to eq(model_name)
    end

    it 'uses provided session_service if passed' do
      custom_service = instance_double(ADK::SessionService::Base)
      # Stub the methods checked by respond_to? for the custom service double
      allow(custom_service).to receive(:respond_to?).with(:get_session).and_return(true)
      allow(custom_service).to receive(:respond_to?).with(:append_event).and_return(true)

      agent = create_agent_from_definition(mock_definition, session_service: custom_service)
      expect(agent.instance_variable_get(:@session_service)).to eq(custom_service)
    end

    it 'uses default session_service if not passed' do
      # Mock initialize_session_service_from_definition to check it's called
      # We expect it to return the globally configured one (session_service_double in this test setup)
      allow(ADK::Agent).to receive(:new).and_call_original # Ensure original new is called
      expect_any_instance_of(ADK::Agent).to receive(:initialize_session_service_from_definition).and_call_original

      agent = ADK::Agent.new(definition: mock_definition) # Do not pass session_service
      expect(agent.instance_variable_get(:@session_service)).to eq(session_service_double)
    end

    it 'warns if a tool class from definition is not found globally' do
      allow(mock_definition).to receive(:tool_names).and_return([:mock_tool, :missing_tool])
      allow(mock_tool_manager).to receive(:find_class).with(:missing_tool).and_return(nil)

      create_agent_from_definition
      expect(logger_double).to have_received(:warn).with(/Could not find globally registered classes for tools: missing_tool/)
    end
  end

  describe '#initialize with keyword args' do
    it 'sets name, description, model, and instruction' do
      agent = create_agent
      expect(agent.name).to eq(agent_name)
      expect(agent.description).to eq(agent_description)
      expect(agent.model_name).to eq(model_name)
      expect(agent.instruction).to eq(instruction)
      expect(agent.definition).to be_nil
    end

    it 'uses default model if not provided' do
      agent = create_agent(model_name: nil)
      expect(agent.model_name).to eq(ADK::Agent::DEFAULT_MODEL)
    end

    it 'registers tool classes provided' do
      agent = create_agent
      expect(agent.find_tool_class(:mock_tool)).to eq(MockTool)
      expect(agent.find_tool_class(:another_tool)).to eq(MockAnotherTool)
    end

    it 'uses provided session_service if passed' do
      custom_service = instance_double(ADK::SessionService::Base)
      # Stub the methods checked by respond_to? for the custom service double
      allow(custom_service).to receive(:respond_to?).with(:get_session).and_return(true)
      allow(custom_service).to receive(:respond_to?).with(:append_event).and_return(true)

      agent = create_agent(session_service: custom_service)
      expect(agent.instance_variable_get(:@session_service)).to eq(custom_service)
    end

    it 'uses default session_service if not passed' do
      allow(ADK::Agent).to receive(:new).and_call_original
      expect_any_instance_of(ADK::Agent).to receive(:initialize_session_service_from_args).and_call_original

      # Do not pass session_service in init_args for this test
      args_no_service = init_args.reject { |k, _| k == :session_service }
      agent = ADK::Agent.new(**args_no_service)
      expect(agent.instance_variable_get(:@session_service)).to eq(session_service_double) # Expect the globally configured one
    end

    it 'raises ArgumentError if name is missing' do
      expect {
        ADK::Agent.new(description: agent_description)
      }.to raise_error(ArgumentError, /Agent name must be provided/)
    end

    # Description is no longer strictly required in initializer if definition not provided
    # It defaults to empty string. Test this behaviour.
    it 'defaults description to empty string if not provided' do
      agent = ADK::Agent.new(name: agent_name) # No description
      expect(agent.description).to eq('')
    end

    it 'raises ConfigurationError if session service is invalid' do
      expect {
        create_agent(session_service: Object.new)
      }.to raise_error(ADK::ConfigurationError, /requires a valid Session Service/)
    end

    it 'raises ConfigurationError if planner is invalid' do
      expect { create_agent(planner: Object.new) }.to raise_error(ADK::ConfigurationError, /requires a valid Planner/)
    end
  end

  # --- Tool Management Tests ---
  describe 'Tool Management' do
    subject(:agent) { create_agent }

    describe '#add_tool' do
      let(:new_tool_class) { ADK::Tools::Calculator }
      let(:new_tool_name) { :calculator }
      let(:new_tool_instance) { new_tool_class.new }

      before do
        # Ensure Calculator tool is globally known for these tests
        allow(mock_tool_manager).to receive(:find_class).with(new_tool_name).and_return(new_tool_class)
        # allow(mock_tool_manager).to receive(:get_tool_name).with(new_tool_class).and_return(new_tool_name) # Removed
      end

      it 'adds a valid tool class' do
        expect(agent.add_tool(new_tool_class)).to be true
        expect(agent.find_tool_class(new_tool_name)).to eq(new_tool_class)
        expect(logger_double).to have_received(:debug).with(/Agent \'#{agent_name}\' add_tool: Registering tool_name=:#{new_tool_name}/)
      end

      it 'adds a valid tool instance' do
        expect(agent.add_tool(new_tool_instance)).to be true
        expect(agent.find_tool_class(new_tool_name)).to eq(new_tool_class)
        expect(logger_double).to have_received(:debug).with(/Agent \'#{agent_name}\' add_tool: Registering tool_name=:#{new_tool_name}/)
      end

      it 'warns and overwrites when adding a duplicate tool' do
        agent.add_tool(new_tool_class) # Add first time
        # Expect warning from ToolRegistry (adjust regex/message as needed)
        expect(logger_double).to receive(:warn).with(/ToolRegistry: Tool \'#{new_tool_name}\' is already registered/).at_least(:once)
        expect(agent.add_tool(new_tool_class)).to be true # Add again
        expect(agent.find_tool_class(new_tool_name)).to eq(new_tool_class) # Should still be there
      end

      it 'errors and does not add an invalid object' do
        invalid_object = Object.new
        expect(agent.add_tool(invalid_object)).to be false
        expect(logger_double).to have_received(:error).with("Agent '#{agent_name}' add_tool: Attempted to add invalid tool: #{invalid_object.inspect}")
      end

      it 'adds a tool using its inferred name if metadata name is missing' do
        # Requires GlobalToolManager mock adjustment for this specific tool
        allow(MockToolNoName).to receive(:tool_metadata).and_return({ name: nil, description: 'Desc' }) # Simulate missing name in metadata
        # allow(mock_tool_manager).to receive(:get_tool_name).with(MockToolNoName).and_return(:mock_tool_no_name) # Removed # Simulate inference in manager

        expect(agent.add_tool(MockToolNoName)).to be true
        expect(agent.find_tool_class(:mock_tool_no_name)).to eq(MockToolNoName)
        expect(logger_double).to have_received(:debug).with(/Registering tool_name=:mock_tool_no_name/)
      end

      it 'logs error and does not add tool if name cannot be determined' do
        # Define class locally to make it anonymous / prevent easy inference
        klass_no_name = Class.new(ADK::Tool) do
          tool_description 'Desc only'
          # Simulate metadata returning nil even if inference might otherwise work
          def self.tool_metadata; { name: nil, description: 'Desc only' }; end
        end
        # Ensure GlobalToolManager also fails to find a name if asked (via metadata)
        allow(klass_no_name).to receive(:tool_metadata).and_return({ name: nil })

        expect(agent.add_tool(klass_no_name)).to be false
        expect(logger_double).to have_received(:error).with(/Could not determine tool name for class.*Cannot add tool/)
      end
    end

    describe '#tools' do
      it 'returns an array of tool instances' do
        agent = create_agent(tool_classes: [MockTool, MockAnotherTool]) # Explicitly pass for clarity
        tool_instances = agent.tools
        expect(tool_instances).to be_an(Array)
        expected_classes = [MockTool, MockAnotherTool, ADK::Tools::CheckJobStatusTool] # Assume CheckJobStatusTool is present
        expect(tool_instances.size).to eq(expected_classes.size)
        expect(tool_instances).to all(be_a(ADK::Tool))
        expect(tool_instances.map(&:class)).to contain_exactly(*expected_classes)
      end

      it 'returns only auto-registered tools if no others registered' do
        agent = create_agent(tool_classes: [])
        expected_tools = [an_instance_of(ADK::Tools::CheckJobStatusTool)] # Assume CheckJobStatusTool is present
        expect(agent.tools).to match_array(expected_tools)
      end

      it 'skips tool instance creation and warns if name cannot be retrieved' do
        # Define class locally
        klass_no_name = Class.new(ADK::Tool) do
          tool_description 'Desc only'
          def self.tool_metadata; { name: nil, description: 'Desc only' }; end
        end
        # Create agent *with* this problematic class registered
        # Need to ensure add_tool *succeeds* initially if based on inference, then fails later
        # Let's assume add_tool works fine based on inference, but metadata call later fails
        agent_no_name_tool = create_agent(tool_classes: []) # Start empty
        allow(klass_no_name).to receive(:tool_metadata).and_return({ name: :klass_no_name, description: 'Desc' }) # Allow registration
        agent_no_name_tool.add_tool(klass_no_name)

        # NOW, mock the metadata call within #tools to return nil name
        allow(klass_no_name).to receive(:tool_metadata).and_return({ name: nil })

        # Expect the warning log
        expect(logger_double).to receive(:warn).with(/Skipping tool instance creation for class .* as it has no retrievable name/)

        # Run the method under test
        tool_instances = agent_no_name_tool.tools
      end
    end

    describe '#find_tool' do
      subject(:agent) { create_agent } # Uses MockTool, AnotherTool

      it 'returns the tool instance if found' do
        tool = agent.find_tool(:mock_tool)
        expect(tool).to be_an_instance_of(MockTool)
      end

      it 'returns nil if the tool is not found' do
        expect(agent.find_tool(:non_existent_tool)).to be_nil
      end

      it 'accepts string name' do
        tool = agent.find_tool('mock_tool')
        expect(tool).to be_an_instance_of(MockTool)
      end
    end

    describe '#available_tools_metadata' do
      it 'returns metadata list from the tool registry (including auto-registered)' do
        metadata = agent.available_tools_metadata
        expect(metadata).to be_an(Array)
        expected_tools_count = 3 # MockTool, AnotherTool, CheckJobStatusTool
        expect(metadata.size).to eq(expected_tools_count)
        expect(metadata).to include(hash_including(name: :mock_tool))
        expect(metadata).to include(hash_including(name: :another_tool))
        expect(metadata).to include(hash_including(name: :check_job_status))
      end

      it 'returns only auto-registered tools if registry has no others' do
        agent = create_agent(tool_classes: [])
        expected_metadata = [hash_including(name: :check_job_status)]
        expect(agent.available_tools_metadata).to match_array(expected_metadata)
      end
    end

    describe '#find_tool_class' do
      subject(:agent) { create_agent }

      it 'returns the tool class if found' do
        expect(agent.find_tool_class(:mock_tool)).to eq(MockTool)
      end

      it 'returns nil if the tool class is not found' do
        expect(agent.find_tool_class(:non_existent_tool)).to be_nil
      end

      it 'accepts string name' do
        expect(agent.find_tool_class('mock_tool')).to eq(MockTool)
      end
    end

    describe '#register_tool_class' do
      subject(:agent) { create_agent(tool_classes: []) } # Start with empty agent registry
      let(:new_tool_class) { ADK::Tools::Calculator }
      let(:new_tool_name) { :calculator }

      before do
        # Mock GlobalToolManager for the new tool
        allow(mock_tool_manager).to receive(:find_class).with(new_tool_name).and_return(new_tool_class)
        # allow(mock_tool_manager).to receive(:get_tool_name).with(new_tool_class).and_return(new_tool_name) # Removed
      end

      it 'registers a valid tool class' do
        expect(agent.register_tool_class(new_tool_class)).to be true
        expect(agent.find_tool_class(new_tool_name)).to eq(new_tool_class)
        # Check logger? Maybe check registry directly
        expect(agent.instance_variable_get(:@tool_registry).find_class(new_tool_name)).to eq(new_tool_class)
      end

      it 'warns and overwrites when registering a duplicate tool class in agent' do
        agent.register_tool_class(new_tool_class) # First time
        # Expect warning from ToolRegistry
        expect(logger_double).to receive(:warn).with(/ToolRegistry: Tool \'#{new_tool_name}\' is already registered/).at_least(:once)
        expect(agent.register_tool_class(new_tool_class)).to be true # Second time
        expect(agent.find_tool_class(new_tool_name)).to eq(new_tool_class)
      end

      it 'logs error and does not register an invalid class' do
        invalid_class = String # Not a tool
        expect(agent.register_tool_class(invalid_class)).to be false
        expect(agent.find_tool_class(:string)).to be_nil # Assuming name would be :string
        expect(logger_double).to have_received(:error).with(/Attempted to register invalid object \(must inherit from ADK::Tool\): String/)
      end

      it 'logs error and does not register class without metadata name' do
        # Adjust mocks for this specific test
        allow(MockToolNoName).to receive(:tool_metadata).and_return({ description: 'Desc' }) # Missing name
        expect(agent.register_tool_class(MockToolNoName)).to be false
        expect(logger_double).to have_received(:error).with(/Tool class MockToolNoName missing name in its metadata. Cannot register./)
      end
    end
  end # End Tool Management

  # --- Runtime State ---
  describe '#start/#stop/#running?' do
    subject(:agent) { create_agent }

    it 'starts the agent' do
      expect(agent.running?).to be false
      agent.start
      expect(agent.running?).to be true
      expect(logger_double).to have_received(:info).with("Agent '#{agent_name}' runtime started.")
    end

    it 'stops the agent' do
      agent.start # Start first
      expect(agent.running?).to be true
      agent.stop
      expect(agent.running?).to be false
      expect(logger_double).to have_received(:info).with("Agent '#{agent_name}' runtime stopped.")
    end

    it 'does nothing if stop is called when not running' do
      expect(agent.running?).to be false
      agent.stop # Call stop without starting
      expect(agent.running?).to be false
      expect(logger_double).not_to have_received(:info).with(/Stopping agent/)
    end

    it 'does nothing if start is called when already running' do
      agent.start
      expect(logger_double).to have_received(:info).with("Agent '#{agent_name}' runtime started.").once
      agent.start # Call start again
      expect(logger_double).to have_received(:info).with("Agent '#{agent_name}' runtime started.").once # Should not log again
    end
  end # End Runtime State

  # --- Run Task ---
  describe '#run_task' do
    subject(:agent) {
      # Important: Provide the *real* session service for run_task tests
      # Also ensure the agent has the necessary tools registered
      create_agent(
        session_service: ADK::SessionService::InMemory.new,
        tool_classes: [MockTool, MockAnotherTool, ADK::Tools::Echo, MockToolWithPending,
                       ADK::Tools::CheckJobStatusTool, MockToolWithError, MockToolWithArgError, MockToolInvalidResult, MockToolPreparationError],
        planner: planner_double # Use planner double by default
      )
    }
    let(:real_session_service) { agent.instance_variable_get(:@session_service) }

    before do
      # Ensure the agent is running for most run_task tests
      agent.start unless RSpec.current_example.metadata[:skip_agent_start]

      # Get the *actual* service instance from the subject
      svc = agent.instance_variable_get(:@session_service)
      expect(svc).to be_an_instance_of(ADK::SessionService::InMemory) # Verify it's the real one

      # Create session using the real service instance
      svc.create_session(app_name: 'app1', user_id: 'user1')

      # Stub get_session on the real service to return our session_double
      allow(svc).to receive(:get_session).with(session_id: session_id).and_return(session_double)
      allow(svc).to receive(:get_session).with(session_id: 'non_existent_session').and_return(nil)
      # Revert: Allow append_event on the real service AND let it call the original method (which calls session_double.add_event)
      allow(svc).to receive(:append_event).and_call_original
    end

    context 'pre-execution checks' do
      it 'returns error hash if agent is not running', :skip_agent_start do
        expect(agent.running?).to be false
        result = agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
        expect(result).to be_a(ADK::Event)
        expect(result.role).to eq(:agent)
        expect(result.content).to eq({ status: :error,
                                       error_message: "Agent '#{agent_name}' runtime is not active (stopped)." })
      end

      it 'returns error hash if session not found' do
        non_existent_session_id = 'non_existent_session'
        result = agent.run_task(session_id: non_existent_session_id, user_input: user_input,
                                session_service: real_session_service)
        expect(result).to be_a(ADK::Event)
        expect(result.role).to eq(:agent)
        expect(result.content).to eq({ status: :error, error_message: "Session not found: #{non_existent_session_id}" })
      end
    end

    context 'successful single-step execution' do
      let(:plan) { [{ tool: :mock_tool, params: { input: 'step 1 data' } }] }

      before do
        allow(planner_double).to receive(:plan).and_return(plan)
      end

      it 'records user, tool request, tool result, and agent events' do
        agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
        session = real_session_service.get_session(session_id: session_id)
        history = session.events
        expect(history.size).to eq(4) # user, tool_request, tool_result, agent
        expect(history[0]).to have_attributes(role: :user, content: user_input)
        expect(history[1]).to have_attributes(role: :tool_request, tool_name: :mock_tool,
                                              content: { input: 'step 1 data' })
        expect(history[2]).to have_attributes(role: :tool_result, tool_name: :mock_tool,
                                              content: hash_including(status: :success, result: 'Mock tool processed: step 1 data'))
        expect(history[3]).to have_attributes(role: :agent,
                                              content: hash_including(status: :success, result: 'Mock tool processed: step 1 data',
                                                                      plan_details: an_instance_of(Array)))
      end

      it 'returns the final agent event with the tool result hash' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input,
                                     session_service: real_session_service)
        expect(final_event).to be_a(ADK::Event)
        expect(final_event.role).to eq(:agent)
        expect(final_event.content).to include(
          status: :success,
          result: 'Mock tool processed: step 1 data'
        )
        expect(final_event.content[:plan_details].first[:result]).to include(status: :success,
                                                                             result: 'Mock tool processed: step 1 data')
      end
    end

    context 'successful multi-step execution with injection' do
      let(:plan_step1) { { tool: :mock_tool, params: { input: 'data for step 1' } } }
      # Step 2 uses placeholder expecting result from step 1
      let(:plan_step2) { { tool: :another_tool, params: { value: '[Result from previous step]' } } }
      # Define the full plan upfront
      let(:full_plan) { [plan_step1, plan_step2] }

      before do
        # Simulate planner returning the full plan initially
        allow(planner_double).to receive(:plan).and_return(full_plan)

        # Need to allow append_event multiple times
        allow(real_session_service).to receive(:append_event).and_call_original
      end

      it 'injects result from step 1 into step 2 params' do
        # Need to trace the call to execute_step for step 2
        expect(agent).to receive(:execute_step).with(
          hash_including(tool: :mock_tool, params: { input: 'data for step 1' }), any_args
        ).and_call_original.ordered
        # Expect execute_step for step 2 to be called with injected value (result of step 1)
        # The value injected should be the actual result string, not its length * 2
        expect(agent).to receive(:execute_step).with(
          hash_including(tool: :another_tool,
                         params: { value: 'Mock tool processed: data for step 1' }), any_args
        ).and_call_original.ordered

        agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
      end

      it 'records events for both steps' do
        agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
        session = real_session_service.get_session(session_id: session_id)
        history = session.events
        expect(history.size).to eq(6) # user, req1, res1, req2, res2, agent
        expect(history.map(&:role)).to eq([:user, :tool_request, :tool_result, :tool_request, :tool_result, :agent])
        expect(history[1].tool_name).to eq(:mock_tool)
        expect(history[3].tool_name).to eq(:another_tool)
        # Check the actual result of the second tool - string duplication
        expect(history[4].content).to include(status: :success, result: ('Mock tool processed: data for step 1' * 2))
      end

      it 'returns the final agent event with the result of the last step' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input,
                                     session_service: real_session_service)
        expect(final_event.role).to eq(:agent)
        expect(final_event.content[:status]).to eq(:success)
        # The final result should be the result of the *last* tool (:another_tool) - string duplication
        expect(final_event.content[:result]).to eq('Mock tool processed: data for step 1' * 2)
      end
    end

    context 'when a step returns a pending status' do
      let(:plan) { [{ tool: :pending_tool, params: { job_request: 'long task' } }] }
      before do
        allow(planner_double).to receive(:plan).and_return(plan)
      end

      it 'returns the final agent event with the pending hash as content' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input,
                                     session_service: real_session_service)
        expect(final_event.role).to eq(:agent)
        expect(final_event.content).to include(
          status: :pending,
          message: /Job submitted/,
          job_id: /job-\d+/
        )
        expect(final_event.content[:plan_details].first[:result]).to include(status: :pending, job_id: /job-\d+/)
      end
    end

    context 'multi-step execution with job_id injection' do
      let(:plan_step1) { { tool: :pending_tool, params: { job_request: 'start async job' } } }
      let(:plan_step2) {
        { tool: :check_job_status, params: { job_id: '[Result from previous step]' } }
      } # Placeholder for job_id
      # Define the full plan upfront
      let(:full_plan) { [plan_step1, plan_step2] }
      let(:mock_job_id) { 'job-12345' }

      before do
        # Simulate planner returning the full plan initially
        allow(planner_double).to receive(:plan).and_return(full_plan)

        # Mock the pending tool to return a predictable job_id
        allow_any_instance_of(MockToolWithPending).to receive(:perform_execution).and_return({ status: :pending,
                                                                                               job_id: mock_job_id, message: 'Job submitted' })
        # Mock the check status tool to return success when called with the correct job_id
        # Target execute on the instance double
        check_tool_instance_double = instance_double(ADK::Tools::CheckJobStatusTool)
        allow(ADK::Tools::CheckJobStatusTool).to receive(:new).and_return(check_tool_instance_double)
        # Mock the execute method to simulate perform_execution returning success
        allow(check_tool_instance_double).to receive(:execute) do |params, context|
          # Simulate successful execution based on job_id
          if params[:job_id] == mock_job_id
            # Ensure correct keys are returned
            { status: :success, job_status: 'completed', result: 'Async job finished!' }
          else
            { status: :error, error_message: "Job not found: #{params[:job_id]}" }
          end
        end
        allow(real_session_service).to receive(:append_event).and_call_original
      end

      it 'injects job_id from step 1 into step 2 params' do
        # Trace execute_step calls
        expect(agent).to receive(:execute_step).with(hash_including(tool: :pending_tool),
                                                     any_args).and_call_original.ordered
        # Expect step 2 to be called with the injected job_id
        expect(agent).to receive(:execute_step).with(
          hash_including(tool: :check_job_status, params: { job_id: mock_job_id }), any_args
        ).and_call_original.ordered

        agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
      end

      it 'returns the final agent event with the result of the check tool' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input,
                                     session_service: real_session_service)
        expect(final_event.role).to eq(:agent)
        # Check the final content includes the expected keys from the successful check
        expect(final_event.content).to include(
          status: :success,
          job_status: 'completed', # This key comes from CheckJobStatusTool
          result: 'Async job finished!'
        )
        # Check plan details include the final step's sanitized result
        expect(final_event.content[:plan_details].last[:result]).to include(status: :success,
                                                                            result: 'Async job finished!')
      end
    end

    context 'multi-step execution with error and plan halting' do
      let(:plan_step1) { { tool: :mock_tool, params: { input: 'good data' } } }
      let(:plan_step2_fails) { { tool: :error_tool, params: { fail_message: 'step 2 boom' } } }
      let(:plan_step3) { { tool: :another_tool, params: { value: 10 } } } # Should not be reached
      # Define the full plan upfront
      let(:full_plan) { [plan_step1, plan_step2_fails, plan_step3] }

      before do
        # Simulate planner returning the full plan initially
        allow(planner_double).to receive(:plan).and_return(full_plan)
        allow(real_session_service).to receive(:append_event).and_call_original
      end

      it 'stops execution after the failed step' do
        expect(agent).to receive(:execute_step).with(hash_including(tool: :mock_tool),
                                                     any_args).and_call_original.ordered
        expect(agent).to receive(:execute_step).with(hash_including(tool: :error_tool),
                                                     any_args).and_call_original.ordered
        # Should NOT call execute_step for step 3
        expect(agent).not_to receive(:execute_step).with(hash_including(tool: :another_tool), any_args)

        agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
      end
    end
  end # End Run Task
end
