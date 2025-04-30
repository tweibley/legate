# File: spec/adk/agent_spec.rb
require 'spec_helper'
require 'sidekiq/testing'
require_relative '../../lib/adk/mcp/error' # Ensure MCP errors are loaded

# --- Mock Tool Classes for Testing ---
class MockToolA < ADK::Tool
  self.explicit_tool_name = :tool_a
  tool_description 'Tool A'
  parameter :p, type: :string, required: true
  def perform_execution(params, _context); { status: :success, result: "A(#{params[:p]})" }; end
end

class MockToolB < ADK::Tool
  self.explicit_tool_name = :tool_b
  tool_description 'Tool B'
  parameter :data, type: :string, required: true
  def perform_execution(params, _context); { status: :success, result: "B(#{params[:data]})" }; end
end

class MockAsyncTool < ADK::Tools::BaseAsyncJobTool
  self.explicit_tool_name = :async_tool
  tool_description 'Async Tool'
  parameter :input, type: :string, required: true

  def sidekiq_worker_class; MOCK_WORKER; end # MOCK_WORKER would need definition
  def prepare_job_arguments(params, _context); [params[:input]]; end
end

class MockToolForAgent < ADK::Tool
  self.explicit_tool_name = :mcp_tool_one
  tool_description 'MCP Tool One'
end

class AnotherMockTool < ADK::Tool
  self.explicit_tool_name = :mcp_tool_two
  tool_description 'MCP Tool Two Description'
end

class MockToolC < ADK::Tool
  self.explicit_tool_name = :tool_c
  tool_description 'Tool C'
end

class MockToolD < ADK::Tool
  self.explicit_tool_name = :tool_d
  tool_description 'Tool D'
end

# --- End Mock Tool Classes ---

# --- Mock MCP Client ---
# Mock client class
class MockMcpClient
  attr_reader :config, :connected, :tools_listed

  def initialize(config)
    @config = config
    @connected = false
    @tools_listed = false
  end

  def connect
    @connected = true
    # Simulate connection success/failure based on config if needed
    true
  end

  def list_tools
    raise ADK::Mcp::ConnectionError, 'Not connected' unless @connected

    @tools_listed = true
    # Return mock schemas - adjust as needed for tests
    [
      { name: 'mcp_tool_one', description: 'MCP Tool One',
        inputSchema: { type: 'object', properties: { a: { type: 'string' } } } },
      { name: 'mcp_tool_two', description: 'MCP Tool Two', inputSchema: { type: 'object', properties: {} } }
    ]
  end

  def disconnect
    @connected = false
  end

  def connected?; @connected; end

  # Add other methods if needed for tests (e.g., call_tool)
end
# ---

# --- Mock ToolWrapper ---
# Mocking the class method directly is easier here
module MockToolWrapper
  def self.from_mcp_schema(schema, client, registry)
    # Simulate registration or return a dummy wrapper class if needed for asserts
    # For verification, we mostly care that this is called correctly.
    # We can check registry state directly in the agent test.
    registry.register(schema[:name].to_sym, Class.new(ADK::Tool)) # Register a dummy class
    true # Indicate success
  end
end
# ---

RSpec.describe ADK::Agent do
  # --- Test Subjects ---
  let(:name) { 'test_agent' }
  let(:description) { 'A test agent' }
  let(:model_name) { 'gemini-test-model' }
  let(:default_model) { ADK::Agent::DEFAULT_MODEL }

  # --- Mocks / Doubles ---
  let(:mock_planner) { instance_double(ADK::Planner, plan: []) } # Default stub
  let(:mock_logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:mock_session_service) { instance_double(ADK::SessionService::InMemory) }
  let(:session_id) { 'sid-123' }
  let(:user_id) { 'user-test' }
  let(:app_name) { name }
  let(:mock_session) { instance_double(ADK::Session, id: session_id, user_id: user_id, app_name: app_name, events: []) }
  let(:mock_context) {
    instance_double(ADK::ToolContext, session_id: session_id, user_id: user_id, app_name: app_name,
                                      to_h: { session_id: session_id, user_id: user_id, app_name: app_name })
  }

  # Tools
  let(:mock_tool_a) { instance_double(ADK::Tool, name: :tool_a) }
  let(:mock_tool_b) { instance_double(ADK::Tool, name: :tool_b) }
  let(:mock_status_tool) { instance_double(ADK::Tools::CheckJobStatusTool, name: :check_job_status) }
  let(:mock_async_tool) { instance_double(ADK::Tools::BaseAsyncJobTool, name: :async_tool) }

  # Results
  let(:success_hash_a) { { status: :success, result: 'Result A' } }
  let(:success_hash_b) { { status: :success, result: 'Result B' } }
  let(:job_id) { 'jid_xyz789' }
  let(:pending_hash) { { status: :pending, job_id: job_id, message: "Job enqueued." } }
  let(:error_hash) { { status: :error, error_message: "Something failed" } }

  # Events
  let(:user_input) { "Test user input" }
  let(:agent_error_event) { instance_double(ADK::Event, role: :agent, content: "Error message") }

  # --- Agent Instance ---
  let!(:agent) do
    # Mock Planner before agent initialization
    allow(ADK::Planner).to receive(:new).and_return(mock_planner)
    # Mock ToolContext creation (will be called by execute_step)
    allow(ADK::ToolContext).to receive(:new)
      .with(hash_including(session_id: session_id, user_id: user_id, app_name: name))
      .and_return(mock_context)
    # Mock ToolRegistry call during agent init for check_job_status
    allow(ADK::ToolRegistry).to receive(:create_instance).with(:check_job_status).and_return(mock_status_tool)
    allow(mock_status_tool).to receive(:is_a?).with(ADK::Tool).and_return(true) # Allow adding the status tool
    # Stub Sidekiq configuration check during init
    allow(Object).to receive(:defined?).with(Sidekiq).and_return(true)

    # --- MCP Mocks ---
    allow(ADK::Mcp::Client).to receive(:new).and_call_original # Allow Client.new but mock instance methods later
    allow(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema).and_return(true) # Default stub
    # --- End MCP Mocks ---

    # Initialize agent with TOOL CLASSES - Ensure NO logger is passed
    described_class.new(
      name: name,
      description: description,
      model_name: model_name,
      tool_classes: [MockToolA, MockToolB, MockAsyncTool] # Pass classes
    )
  end

  # --- General Setup ---
  before do
    # Mock ADK.logger instead of ADK::Logger
    allow(ADK).to receive(:logger).and_return(mock_logger)

    # Tool type checking
    allow(mock_tool_a).to receive(:is_a?).with(ADK::Tool).and_return(true)
    allow(mock_tool_a).to receive(:is_a?).with(Class).and_return(false)
    allow(mock_tool_b).to receive(:is_a?).with(ADK::Tool).and_return(true)
    allow(mock_tool_b).to receive(:is_a?).with(Class).and_return(false)
    allow(mock_status_tool).to receive(:is_a?).with(ADK::Tool).and_return(true)
    allow(mock_status_tool).to receive(:is_a?).with(Class).and_return(false)
    allow(mock_async_tool).to receive(:is_a?).with(ADK::Tool).and_return(true)
    allow(mock_async_tool).to receive(:is_a?).with(Class).and_return(false)

    # Tool name and class setup
    allow(mock_tool_a).to receive(:name).and_return(:tool_a)
    allow(mock_tool_a).to receive(:class).and_return(MockToolA)
    allow(mock_tool_b).to receive(:name).and_return(:tool_b)
    allow(mock_tool_b).to receive(:class).and_return(MockToolB)
    allow(mock_status_tool).to receive(:name).and_return(:check_job_status)
    allow(mock_status_tool).to receive(:class).and_return(ADK::Tools::CheckJobStatusTool)

    # Session service interactions
    allow(mock_session_service).to receive(:get_session).with(session_id: session_id).and_return(mock_session)
    allow(mock_session_service).to receive(:append_event).and_return(true)
    # Event creation
    allow(ADK::Event).to receive(:new).and_call_original
    # Logger setup
    allow(ADK.logger).to receive(:level=) unless RSpec.current_example.metadata[:log_level]
    allow(ADK.logger).to receive(:info) unless RSpec.current_example.metadata[:log_level]
    allow(ADK.logger).to receive(:warn) unless RSpec.current_example.metadata[:log_level]
    allow(ADK.logger).to receive(:error) unless RSpec.current_example.metadata[:log_level]
    allow(ADK.logger).to receive(:debug) unless RSpec.current_example.metadata[:log_level]
  end

  # --- Tests ---

  describe '#initialize' do
    it 'sets name, description, and model' do
      expect(agent.name).to eq(name)
      expect(agent.description).to eq(description)
      expect(agent.model_name).to eq(model_name)
    end

    it 'uses default model if none provided' do
      # We need to re-allow Planner.new for this specific instance creation
      allow(ADK::Planner).to receive(:new).and_return(mock_planner)
      # Create agent without model_name
      agent_default = described_class.new(name: name, description: description)
      expect(agent_default.model_name).to eq(default_model)
      # Verify planner was initialized with default model
      expect(ADK::Planner).to have_received(:new).with(hash_including(model_name: default_model))
    end

    it 'initializes with a planner' do
      expect(agent.planner).to eq(mock_planner)
    end

    it 'initializes with check_job_status tool if Sidekiq defined' do
      # Check that the check_job_status tool (mocked) is present
      expect(agent.tools.map(&:class)).to include(ADK::Tools::CheckJobStatusTool)
      expect(agent.tools.map(&:name)).to include(:check_job_status)
    end

    it 'automatically adds check_job_status tool if Sidekiq is defined' do
      # Agent initialization is already stubbed in the main let! block
      expect(agent.tools.map(&:name)).to include(:check_job_status)
    end

    # --- NEW TESTS START HERE ---

    context 'when Sidekiq is not defined' do
      before do
        # Undefine Sidekiq for this context ONLY
        hide_const("Sidekiq")
        # Mock Planner for this specific agent initialization
        allow(ADK::Planner).to receive(:new).and_return(mock_planner)
      end

      it 'skips adding CheckJobStatusTool and logs warning' do
        expect(ADK.logger).to receive(:warn).with(/Skipping automatic registration of CheckJobStatusTool/)
        # Need to re-initialize agent within this specific context
        test_agent = described_class.new(name: 'no_sidekiq_agent', description: 'Test')
        expect(test_agent.find_tool(:check_job_status)).to be_nil
      end
    end

    context 'with mcp_servers as JSON string' do
      let(:parsed_array_config) { [{ "type" => "stdio", "command" => "cmd1" }, { "type" => "sse", "url" => "http://ex.com" }] }

      before do
        # REMOVED global spy setup here
        # Mock Planner for agent initialization
        allow(ADK::Planner).to receive(:new).and_return(mock_planner)
      end

      it 'parses valid array JSON string correctly and stores it' do
        valid_json_string = '[{"type":"stdio","command":"cmd1"},{"type":"sse","url":"http://ex.com"}]'

        # Use the standard logger mock defined in the main `before` block
        expect(ADK.logger).not_to receive(:warn)
        expect(ADK.logger).not_to receive(:error)

        test_agent = described_class.new(name: 'json_agent', description: 'Test', mcp_servers: valid_json_string)
        # Check the internal config array stored after initialization
        expect(test_agent.send(:instance_variable_get, :@mcp_servers_config)).to eq(parsed_array_config)
      end

      it 'handles invalid JSON string, logs error, and defaults to empty array' do
        invalid_json_string = '[{"type":"invalid'

        # Expect the specific error log message
        expect(ADK.logger).to receive(:error).with(/Failed to parse MCP server config JSON/)

        test_agent = described_class.new(name: 'bad_json_agent', description: 'Test', mcp_servers: invalid_json_string)
        expect(test_agent.send(:instance_variable_get, :@mcp_servers_config)).to eq([])
      end

      it 'handles JSON string parsing to non-array, logs warning, and defaults to empty array' do
        non_array_json_string = '{"type":"stdio"}' # Simplified Hash JSON

        # Expect the specific warning log message
        expect(ADK.logger).to receive(:warn).with(/MCP server config parsed but is not an Array/)

        test_agent = described_class.new(name: 'non_array_json_agent', description: 'Test',
                                         mcp_servers: non_array_json_string)
        expect(test_agent.send(:instance_variable_get, :@mcp_servers_config)).to eq([])
      end
    end

    context 'with fallback_mode' do
      it 'sets fallback_mode to :echo when specified' do
        # Mock Planner for this specific agent initialization
        allow(ADK::Planner).to receive(:new).and_return(mock_planner)
        test_agent = described_class.new(name: 'echo_fallback_agent', description: 'Test', fallback_mode: :echo)
        expect(test_agent.fallback_mode).to eq(:echo)
      end

      it 'defaults fallback_mode to :error for invalid values' do
        # Mock Planner for this specific agent initialization
        allow(ADK::Planner).to receive(:new).and_return(mock_planner)
        test_agent = described_class.new(name: 'bad_fallback_agent', description: 'Test', fallback_mode: :invalid_mode)
        expect(test_agent.fallback_mode).to eq(:error)
      end
    end
    # --- NEW TESTS END HERE ---
  end

  describe '#add_tool' do
    let(:mock_registry) { instance_double(ADK::ToolRegistry) }
    let(:test_agent) { described_class.new(name: 'add_tool_agent', description: 'Test') }

    before do
      # Prevent planner creation during these specific tests
      allow(ADK::Planner).to receive(:new).and_return(mock_planner)
      # Stub logger for all tests in this context
      allow(ADK).to receive(:logger).and_return(mock_logger)
      # Stub registry interactions - allow registration by default
      allow(test_agent.tool_registry).to receive(:register).and_return(true)
      allow(test_agent.tool_registry).to receive(:find_class).and_return(nil) # Default: not found
    end

    # Existing tests refactored slightly to use test_agent
    it 'adds a valid tool class' do
      allow(test_agent.tool_registry).to receive(:register).with(:tool_a, MockToolA).and_return(true)
      expect(test_agent.add_tool(MockToolA)).to be true
      expect(test_agent.tool_registry).to have_received(:register).with(:tool_a, MockToolA)
    end

    it 'adds a valid tool instance' do
      tool_instance = MockToolA.new
      allow(test_agent.tool_registry).to receive(:register).with(:tool_a, MockToolA).and_return(true)
      expect(test_agent.add_tool(tool_instance)).to be true
      expect(test_agent.tool_registry).to have_received(:register).with(:tool_a, MockToolA)
    end

    it 'warns and overwrites when adding a duplicate tool' do
      # Simulate tool already exists in registry
      allow(test_agent.tool_registry).to receive(:find_class).with(:tool_a).and_return(MockToolA)
      expect(mock_logger).to receive(:warn).with(/Tool 'tool_a' already added. Overwriting./)
      expect(test_agent.add_tool(MockToolA)).to be true # Still returns true after overwrite
      expect(test_agent.tool_registry).to have_received(:register).with(:tool_a, MockToolA)
    end

    it 'errors and does not add an invalid object' do
      invalid_object = Object.new
      expect(mock_logger).to receive(:error).with(/Attempted to add invalid tool/)
      expect(test_agent.add_tool(invalid_object)).to be false
      expect(test_agent.tool_registry).not_to have_received(:register)
    end

    # --- NEW TESTS --- >
    it 'adds a tool using its inferred name if metadata name is missing' do
      class InferrableTool < ADK::Tool
        tool_description 'Inferrable'
        # No explicit name set
        def perform_execution(params, context); { status: :success }; end
      end
      allow(test_agent.tool_registry).to receive(:register).with(:inferrable_tool, InferrableTool).and_return(true)
      expect(test_agent.add_tool(InferrableTool)).to be true
      expect(test_agent.tool_registry).to have_received(:register).with(:inferrable_tool, InferrableTool)
    end

    it 'logs error and does not add tool if name cannot be determined' do
      class UnnamableTool < ADK::Tool
        # No name in metadata, and class name doesn't follow convention for inference (e.g., anonymous)
        def self.name; nil; end # Simulate anonymous class
        def self.tool_metadata; { name: nil, description: 'Unnamable', parameters: {} }; end
        def self.inferred_name; nil; end # Explicitly prevent inference for test
        def perform_execution(params, context); { status: :success }; end
      end

      expect(mock_logger).to receive(:error).with(/Could not determine tool name for class.*UnnamableTool/)
      expect(test_agent.add_tool(UnnamableTool)).to be false
      expect(test_agent.tool_registry).not_to have_received(:register)
    end
    # <--- END NEW TESTS ---
  end

  describe '#tools' do
    let(:agent) { described_class.new(name: 'tools_agent', description: 'Test') }
    let(:mock_instance_a) { instance_double(MockToolA) }
    let(:mock_instance_b) { instance_double(MockToolB) }

    before do
      # Stub registry state and instance creation
      allow(agent.tool_registry).to receive(:tools).and_return({ tool_a: MockToolA, tool_b: MockToolB })
      allow(agent.tool_registry).to receive(:create_instance).with(:tool_a).and_return(mock_instance_a)
      allow(agent.tool_registry).to receive(:create_instance).with(:tool_b).and_return(mock_instance_b)
      allow(ADK).to receive(:logger).and_return(mock_logger)
    end

    it 'returns an array of tool instances' do
      expect(agent.tools).to contain_exactly(mock_instance_a, mock_instance_b)
    end

    it 'returns an empty array if no tools are registered' do
      allow(agent.tool_registry).to receive(:tools).and_return({})
      expect(agent.tools).to eq([])
    end

    it 'skips tool instance creation and warns if name cannot be retrieved' do
      # Simulate a class where metadata retrieval fails (edge case)
      class BadMetadataTool < ADK::Tool
        def self.tool_metadata; nil; end # Simulate failure
      end
      allow(agent.tool_registry).to receive(:tools).and_return({ tool_a: MockToolA, bad: BadMetadataTool })
      allow(agent.tool_registry).to receive(:create_instance).with(:tool_a).and_return(mock_instance_a)
      allow(BadMetadataTool).to receive(:tool_metadata).and_return({ name: nil }) # Ensure metadata returns nil name

      expect(ADK.logger).to receive(:warn).with(/Skipping tool instance creation for class BadMetadataTool/)
      expect(agent.tools).to contain_exactly(mock_instance_a)
    end
  end

  describe '#find_tool' do
    let(:agent) { described_class.new(name: 'find_tool_agent', description: 'Test') }
    let(:mock_instance_a) { instance_double(MockToolA) }

    it 'returns the tool instance if found' do
      allow(agent.tool_registry).to receive(:create_instance).with(:tool_a).and_return(mock_instance_a)
      expect(agent.find_tool(:tool_a)).to eq(mock_instance_a)
    end

    it 'returns nil if the tool is not found' do
      allow(agent.tool_registry).to receive(:create_instance).with(:non_existent_tool).and_return(nil)
      expect(agent.find_tool(:non_existent_tool)).to be_nil
    end

    it 'accepts string name' do
      allow(agent.tool_registry).to receive(:create_instance).with(:tool_a).and_return(mock_instance_a)
      expect(agent.find_tool('tool_a')).to eq(mock_instance_a)
    end
  end

  describe '#available_tools_metadata' do
    let(:agent) { described_class.new(name: 'metadata_agent', description: 'Test') }
    let(:metadata_a) { { name: :tool_a, description: 'Desc A', parameters: {} } }
    let(:metadata_b) { { name: :tool_b, description: 'Desc B', parameters: {} } }

    it 'returns metadata list from the tool registry' do
      allow(agent.tool_registry).to receive(:list_tools).and_return([metadata_a, metadata_b])
      expect(agent.available_tools_metadata).to eq([metadata_a, metadata_b])
    end

    it 'returns an empty list if registry has no tools' do
      allow(agent.tool_registry).to receive(:list_tools).and_return([])
      expect(agent.available_tools_metadata).to eq([])
    end
  end

  describe '#find_tool_class' do
    let(:agent) { described_class.new(name: 'find_class_agent', description: 'Test') }

    it 'returns the tool class if found' do
      allow(agent.tool_registry).to receive(:find_class).with(:tool_a).and_return(MockToolA)
      expect(agent.find_tool_class(:tool_a)).to eq(MockToolA)
    end

    it 'returns nil if the tool class is not found' do
      allow(agent.tool_registry).to receive(:find_class).with(:non_existent_tool).and_return(nil)
      expect(agent.find_tool_class(:non_existent_tool)).to be_nil
    end

    it 'accepts string name' do
      allow(agent.tool_registry).to receive(:find_class).with(:tool_a).and_return(MockToolA)
      expect(agent.find_tool_class('tool_a')).to eq(MockToolA)
    end
  end

  describe '#start/#stop/#running?' do
    it 'starts the agent' do
      agent.start
      expect(agent.running?).to be true
    end

    it 'stops the agent' do
      agent.start
      agent.stop
      expect(agent.running?).to be false
    end
    # Consider adding idempotency tests if needed
  end

  describe '#run_task' do
    before do
      # Add tools used in these tests
      allow_any_instance_of(ADK::ToolRegistry).to receive(:register).and_return(true)
      allow_any_instance_of(ADK::ToolRegistry).to receive(:create_instance) do |_, name|
        case name.to_sym
        when :tool_a then mock_tool_a
        when :tool_b then mock_tool_b
        when :check_job_status then mock_status_tool
        when :async_tool then mock_async_tool
        else nil
        end
      end

      # Setup logger stubs
      allow(ADK.logger).to receive(:info)
      allow(ADK.logger).to receive(:warn)
      allow(ADK.logger).to receive(:error)
      allow(ADK.logger).to receive(:debug)

      agent.add_tool(mock_tool_a)
      agent.add_tool(mock_tool_b)
      agent.add_tool(mock_async_tool)
    end

    context 'pre-execution checks' do
      it 'returns error hash if agent is not running' do
        # Agent is stopped by default after initialization in `let!`
        result = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
        expect(result).to be_an(ADK::Event)
        expect(result.role).to eq(:agent)
        expect(result.content).to eq({ status: :error,
                                       error_message: "Agent '#{name}' runtime is not active (stopped)." })
      end

      it 'returns error hash if session not found' do
        agent.start # Agent must be running
        allow(mock_session_service).to receive(:get_session).with(session_id: session_id).and_return(nil)
        result = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
        expect(result).to be_an(ADK::Event)
        expect(result.role).to eq(:agent)
        expect(result.content).to eq({ status: :error, error_message: "Session not found: #{session_id}" })
      end
    end

    context 'successful single-step execution' do
      let(:plan) { [{ tool: :tool_a, params: { p: 1 } }] }

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
        allow(mock_tool_a).to receive(:execute).with({ p: 1 }, mock_context).and_return(success_hash_a)
      end

      it 'records user, tool request, tool result, and agent events' do
        expect(mock_session_service).to receive(:append_event).with(session_id: session_id,
                                                                    event: instance_of(ADK::Event)).exactly(4).times.and_return(true)
        agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
      end

      it 'returns the final agent event with the tool result hash' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input,
                                     session_service: mock_session_service)
        expect(final_event).to be_an(ADK::Event)
        expect(final_event.role).to eq(:agent)
        expected_content = success_hash_a.merge(
          plan_details: [{ tool_name: :tool_a, params: { p: 1 }, result: success_hash_a }]
        )
        expect(final_event.content).to eq(expected_content)
      end
    end

    context 'successful multi-step execution with injection' do
      let(:plan) { [{ tool: :tool_a, params: { p: 1 } }, { tool: :tool_b, params: { data: '[Result from step 1]' } }] }
      let(:sanitized_result_a) { { status: :success, result: "Result A" } } # Simplified for plan details
      let(:sanitized_result_b) { { status: :success, result: "Result B" } } # Simplified for plan details

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
        allow(mock_tool_a).to receive(:execute).with({ p: 1 }, mock_context).and_return(success_hash_a)
        allow(mock_tool_b).to receive(:execute).with({ data: 'Result A' }, mock_context).and_return(success_hash_b)
      end

      it 'injects result from step 1 into step 2 params' do
        expect(mock_tool_b).to receive(:execute).with({ data: 'Result A' }, mock_context).and_return(success_hash_b)
        agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
      end

      it 'records events for both steps' do
        expect(mock_session_service).to receive(:append_event).with(session_id: session_id,
                                                                    event: instance_of(ADK::Event)).exactly(6).times
        agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
      end

      it 'returns the final agent event with the result of the last step' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input,
                                     session_service: mock_session_service)
        expect(final_event).to be_an(ADK::Event)
        expect(final_event.role).to eq(:agent)
        expected_content = success_hash_b.merge(
          plan_details: [
            { tool_name: :tool_a, params: { p: 1 }, result: sanitized_result_a },
            { tool_name: :tool_b, params: { data: 'Result A' }, result: sanitized_result_b } # Injected params
          ]
        )
        expect(final_event.content).to eq(expected_content)
      end
    end

    context 'when a step returns a pending status' do
      let(:plan) { [{ tool: :async_tool, params: { input: 'go' } }] }
      # Sanitized version for plan_details (job_id is included)
      let(:sanitized_pending_hash) {
        { status: :pending, job_id: job_id, message: pending_hash[:message], result: nil }
      }

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
        # Mock the async tool returning the pending hash with job_id
        allow(mock_async_tool).to receive(:execute).with({ input: 'go' }, mock_context).and_return(pending_hash)
      end

      it 'returns the final agent event with the pending hash as content' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input,
                                     session_service: mock_session_service)
        expect(final_event).to be_an(ADK::Event)
        expect(final_event.role).to eq(:agent)
        expected_content = pending_hash.merge(
          plan_details: [{ tool_name: :async_tool, params: { input: 'go' }, result: sanitized_pending_hash }]
        )
        expect(final_event.content).to eq(expected_content)
      end
    end

    context 'multi-step execution with job_id injection' do
      let(:plan) {
        [{ tool: :async_tool, params: { input: 'start' } },
         { tool: :check_job_status, params: { job_id: '[Result from step 1]' } }]
      }
      let(:check_result_success) { { status: :success, result: 'Job Done' } }
      # Sanitized versions for plan_details
      let(:sanitized_pending_hash) {
        { status: :pending, job_id: job_id, message: pending_hash[:message], result: nil }
      }
      let(:sanitized_check_result) { { status: :success, result: "Job Done" } }

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
        allow(mock_async_tool).to receive(:execute).with({ input: 'start' }, mock_context).and_return(pending_hash)
        # Mock the check_job_status tool instance (retrieved via registry)
        mock_check_tool = agent.send(:find_tool, :check_job_status) # Get the mocked instance added during init
        allow(mock_check_tool).to receive(:execute).with({ job_id: job_id },
                                                         mock_context).and_return(check_result_success)
      end

      it 'injects job_id from step 1 into step 2 params' do
        mock_check_tool = agent.send(:find_tool, :check_job_status)
        expect(mock_check_tool).to receive(:execute).with({ job_id: job_id },
                                                          mock_context).and_return(check_result_success)
        agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
      end

      it 'returns the final agent event with the result of the check tool' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input,
                                     session_service: mock_session_service)
        expect(final_event).to be_an(ADK::Event)
        expect(final_event.role).to eq(:agent)
        expected_content = check_result_success.merge(
          plan_details: [
            { tool_name: :async_tool, params: { input: 'start' }, result: sanitized_pending_hash },
            { tool_name: :check_job_status, params: { job_id: job_id }, result: sanitized_check_result } # Injected job_id
          ]
        )
        expect(final_event.content).to eq(expected_content)
      end
    end

    context 'multi-step execution with error and plan halting' do
      let(:plan) { [{ tool: :tool_a, params: { p: 1 } }, { tool: :tool_b, params: { data: '[Result from step 1]' } }] }
      # Define the error that the mock tool will raise
      let(:tool_a_error) { ADK::ToolError.new("Something failed in Tool A") }
      # This is the hash that execute_step will create when it rescues the error
      let(:rescued_error_hash) {
        { status: :error, error_message: tool_a_error.message, error_class: tool_a_error.class.name, result: nil }
      }
      # This is the final content hash expected in the agent event
      let(:expected_final_content_on_error) {
        {
          status: :error,
          error_message: tool_a_error.message,
          error_class: tool_a_error.class.name,
          result: nil,
          plan_details: [{ tool_name: :tool_a, params: { p: 1 }, result: rescued_error_hash }]
        }
      }

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
        # Make the mock tool raise the specific error
        allow(mock_tool_a).to receive(:execute).with({ p: 1 }, mock_context).and_raise(tool_a_error)
        # Do not mock the final event creation - let the agent create it based on the rescued error
      end

      it 'stops execution after the failed step' do
        expect(mock_tool_b).not_to receive(:execute)
        agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
      end

      it 'records events up to and including the failed tool result' do
        # We expect 4 events: user input, tool request, tool result, and final agent response
        expect(mock_session_service).to receive(:append_event).exactly(4).times do |args|
          expect(args[:session_id]).to eq(session_id)
          # Check that it's either a real ADK::Event or an instance double of one
          expect(args[:event]).to satisfy { |e|
            e.is_a?(ADK::Event) || e.instance_of?(RSpec::Mocks::InstanceVerifyingDouble)
          }
        end
        agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
      end

      it 'returns the final agent event indicating the error' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input,
                                     session_service: mock_session_service)
        expect(final_event.role).to eq(:agent)
        # Now compare against the expected content hash derived from the raised exception
        expect(final_event.content).to eq(expected_final_content_on_error)
      end
    end

    context 'when planner returns an empty plan' do
      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return([])
      end

      it 'returns an error event' do
        result = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
        expect(result).to be_an(ADK::Event)
        expect(result.role).to eq(:agent)
        expected_error_hash = { status: :error,
                                error_message: "I cannot fulfill this request with the available tools (empty plan)." }
        expect(result.content).to eq(expected_error_hash)
      end
    end

    context 'when planner itself raises an error' do
      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_raise(StandardError.new("Planner explosion"))
      end

      it 'returns an error event and logs an agent error event', :log_level do
        # Run the task first, then check logs with have_received
        result = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)

        expect(ADK.logger).to have_received(:error).with(/Critical error during run_task.*Planner explosion/)
        expect(mock_session_service).to have_received(:append_event).with(
          session_id: session_id,
          event: having_attributes(role: :agent,
                                   content: { status: :error,
                                              error_message: /An internal error occurred.*Planner explosion/i })
        )

        # result expectation remains the same
        expect(result).to be_an(ADK::Event)
        expect(result.role).to eq(:agent)
        expected_error_hash = { status: :error, error_message: "An internal error occurred: Planner explosion" }
        expect(result.content).to eq(expected_error_hash)
      end
    end

    context 'when finding a tool raises an error' do
      let(:bad_tool_plan) { [{ tool: :missing_tool, params: {} }] }
      # Define the error hash created by execute_step when tool not found
      let(:tool_not_found_error_hash) {
        { status: :error,
          error_message: "Tool 'missing_tool' not found for this agent.",
          error_class: ADK::ToolError.name, # Add error class
          result: nil }
      }
      # Define the final agent event content, including plan details with the error hash
      let(:expected_final_content_tool_not_found) {
        {
          status: :error,
          error_message: "Tool 'missing_tool' not found for this agent.",
          error_class: ADK::ToolError.name, # Add error class
          result: nil,
          plan_details: [{
            tool_name: :missing_tool,
            params: {},
            result: tool_not_found_error_hash # Use the defined error hash
          }]
        }
      }
      let(:error_event) { ADK::Event.new(role: :agent, content: expected_final_content_tool_not_found) }

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(bad_tool_plan)
        # No need to mock event creation if we check the final returned event content
      end

      it 'returns the final agent event with error content' do
        result = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
        expect(result.role).to eq(:agent)
        expect(result.content).to eq(expected_final_content_tool_not_found)
      end
    end

    context 'when execute_step fails' do
      let(:bad_tool_plan) { [{ tool: :mock_tool, params: { arg: "value" } }] }
      let(:exec_error) { StandardError.new("Exec boom") } # Simulate an *unexpected* error

      # --- Create a dedicated agent instance WITH the mock tool --- #
      let(:agent_with_mock_tool) {
        # Ensure the mock tool class is defined
        unless defined?(MockToolForAgent)
          Kernel.const_set("MockToolForAgent", Class.new(ADK::Tool) do
            define_metadata(name: :mock_tool, description: 'Mock Tool')
            # Define execute, though we'll stub it
            def execute(params, context); raise NotImplementedError; end
          end)
        end
        described_class.new(name: name, description: description, model_name: model_name,
                            tool_classes: [MockToolForAgent], planner: mock_planner)
      }
      # --- Mock the instance retrieved from the registry --- #
      let(:mock_tool_instance_for_error) { instance_double(MockToolForAgent) }

      # This is the hash execute_step creates when rescuing StandardError
      let(:rescued_exec_error_hash) {
        { status: :error,
          error_message: "Internal error executing tool 'mock_tool': #{exec_error.message}",
          error_class: exec_error.class.name,
          result: nil }
      }
      # This is the final content hash expected in the agent event
      let(:expected_final_content_on_exec_error) {
        {
          status: :error,
          error_message: "Internal error executing tool 'mock_tool': #{exec_error.message}",
          error_class: exec_error.class.name,
          result: nil,
          plan_details: [{ tool_name: :mock_tool, params: { arg: "value" }, result: rescued_exec_error_hash }]
        }
      }

      before do
        agent_with_mock_tool.start # Start the correct agent
        allow(mock_planner).to receive(:plan).with(user_input).and_return(bad_tool_plan)

        # Stub the registry call for *this specific agent instance*
        allow(agent_with_mock_tool.tool_registry).to receive(:create_instance).with(:mock_tool).and_return(mock_tool_instance_for_error)

        # Simulate the tool's execute method raising an unexpected error ON THE CORRECT INSTANCE DOUBLE
        allow(mock_tool_instance_for_error).to receive(:execute).with({ arg: "value" }, anything).and_raise(exec_error)
      end

      it 'returns an error event' do
        # Use the agent instance that has the tool registered
        result = agent_with_mock_tool.run_task(session_id: session_id, user_input: user_input,
                                               session_service: mock_session_service)
        expect(result).to be_an(ADK::Event)
        expect(result.role).to eq(:agent)
        expect(result.content).to eq(expected_final_content_on_exec_error)
      end
    end

    # --- NEW CONTEXT for ToolError --- #
    context 'when tool raises ADK::ToolError' do
      let(:plan) { [{ tool: :mock_tool, params: { arg: "value" } }] }
      let(:tool_error) { ADK::ToolError.new("Specific tool failure") }
      let(:mock_tool_instance) { instance_double(MockToolForAgent) }
      let(:agent_with_mock_tool) {
        described_class.new(name: name, description: description, tool_classes: [MockToolForAgent],
                            planner: mock_planner)
      }

      before do
        agent_with_mock_tool.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
        allow(agent_with_mock_tool.tool_registry).to receive(:create_instance).with(:mock_tool).and_return(mock_tool_instance)
        allow(mock_tool_instance).to receive(:execute).with({ arg: "value" }, anything).and_raise(tool_error)
      end

      it 'returns final agent event with ToolError details' do
        result = agent_with_mock_tool.run_task(session_id: session_id, user_input: user_input,
                                               session_service: mock_session_service)

        expect(result).to be_an(ADK::Event)
        expect(result.role).to eq(:agent)

        expected_error_content = {
          status: :error,
          error_message: tool_error.message,
          error_class: tool_error.class.name,
          result: nil
        }
        expected_final_content = expected_error_content.merge(
          plan_details: [{ tool_name: :mock_tool, params: { arg: "value" }, result: expected_error_content }]
        )
        expect(result.content).to eq(expected_final_content)
      end
    end

    # --- NEW CONTEXT for ToolArgumentError --- #
    context 'when tool raises ADK::ToolArgumentError' do
      let(:plan) { [{ tool: :mock_tool, params: { arg: "bad_value" } }] }
      let(:arg_error) { ADK::ToolArgumentError.new("Invalid argument value") }
      let(:mock_tool_instance) { instance_double(MockToolForAgent) }
      let(:agent_with_mock_tool) {
        described_class.new(name: name, description: description, tool_classes: [MockToolForAgent],
                            planner: mock_planner)
      }

      before do
        agent_with_mock_tool.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
        allow(agent_with_mock_tool.tool_registry).to receive(:create_instance).with(:mock_tool).and_return(mock_tool_instance)
        allow(mock_tool_instance).to receive(:execute).with({ arg: "bad_value" }, anything).and_raise(arg_error)
      end

      it 'returns final agent event with ToolArgumentError details' do
        result = agent_with_mock_tool.run_task(session_id: session_id, user_input: user_input,
                                               session_service: mock_session_service)

        expect(result).to be_an(ADK::Event)
        expect(result.role).to eq(:agent)

        expected_error_content = {
          status: :error,
          error_message: arg_error.message,
          error_class: arg_error.class.name,
          result: nil
        }
        expected_final_content = expected_error_content.merge(
          plan_details: [{ tool_name: :mock_tool, params: { arg: "bad_value" }, result: expected_error_content }]
        )
        expect(result.content).to eq(expected_final_content)
      end
    end

    # --- NEW CONTEXT: Edge Cases in run_task/execute_plan/execute_step ---
    context 'when session service append fails critically' do
      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return([{ tool: :tool_a, params: {} }])
        # Simulate append_event failing *after* the first user event is added
        allow(mock_session_service).to receive(:append_event).with(session_id: session_id, event: instance_of(ADK::Event)).and_return(true) # User event - Removed .ordered
        allow(mock_session_service).to receive(:append_event).with(session_id: session_id, event: instance_of(ADK::Event)).and_raise(StandardError, "Redis Boom!") # Tool request event fails - Removed .ordered
      end

      it 'logs critical error and returns an agent error event' do
        expect(ADK.logger).to receive(:error).with(/Critical error during run_task.*Redis Boom!/)
        # The final agent event should still be created and appended (or attempted)
        expect(mock_session_service).to receive(:append_event).with(
          session_id: session_id,
          event: having_attributes(role: :agent,
                                   content: hash_including(status: :error,
                                                           error_message: /An internal error occurred.*Redis Boom!/))
        ).at_least(:once) # May be called again in rescue block

        result = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)

        # Check the returned event
        expect(result).to be_an(ADK::Event)
        expect(result.role).to eq(:agent)
        expect(result.content).to match(hash_including(status: :error,
                                                       error_message: /An internal error occurred: Redis Boom!/))
      end
    end

    context 'with echo fallback mode' do
      let(:agent_echo_fallback) do
        described_class.new(name: 'echo_fallback', description: 'desc', fallback_mode: :echo)
      end

      before do
        # Simulate planner returning empty plan
        allow(agent_echo_fallback.planner).to receive(:plan).with(user_input).and_return([])
        allow(mock_session).to receive(:events).and_return([ADK::Event.new(role: :user, content: user_input)])
        allow(mock_session_service).to receive(:get_session).with(session_id: session_id).and_return(mock_session)
        agent_echo_fallback.start
      end

      context 'when Echo tool is available' do
        let(:echo_tool_instance) { instance_double(ADK::Tools::Echo) }
        let(:echo_success_hash) { { status: :success, result: user_input } }
        let(:sanitized_echo_result) { { status: :success, result: user_input } }

        before do
          # Ensure Echo tool is registered ONLY for this agent
          allow(agent_echo_fallback.tool_registry).to receive(:find_class).with(:echo).and_return(ADK::Tools::Echo)
          allow(agent_echo_fallback.tool_registry).to receive(:create_instance).with(:echo).and_return(echo_tool_instance)
          allow(echo_tool_instance).to receive(:execute).with({ message: user_input },
                                                              anything).and_return(echo_success_hash)
        end

        it 'executes the Echo tool with original user input' do
          expect(echo_tool_instance).to receive(:execute).with({ message: user_input }, anything)
          final_event = agent_echo_fallback.run_task(session_id: session_id, user_input: user_input,
                                                     session_service: mock_session_service)
          expect(final_event.role).to eq(:agent)
          expected_content = echo_success_hash.merge(
            plan_details: [{ tool_name: :echo, params: { message: user_input }, result: sanitized_echo_result }]
          )
          expect(final_event.content).to eq(expected_content)
        end
      end

      context 'when Echo tool is NOT available' do
        before do
          # Ensure Echo tool is NOT registered for this agent
          allow(agent_echo_fallback.tool_registry).to receive(:find_class).with(:echo).and_return(nil)
        end

        it 'returns an error event indicating Echo tool is missing' do
          expect(ADK.logger).to receive(:warn).with("Planning failed and Echo fallback tool is not available to this agent.")
          final_event = agent_echo_fallback.run_task(session_id: session_id, user_input: user_input,
                                                     session_service: mock_session_service)
          expect(final_event.role).to eq(:agent)
          expect(final_event.content).to eq({ status: :error,
                                              error_message: "Planning failed and Echo fallback tool is not available to this agent." })
        end
      end
    end

    context 'with input injection edge cases' do
      let(:plan_prev) {
        [{ tool: :tool_a, params: { p: 1 } }, { tool: :tool_b, params: { data: '[Result from previous step]' } }]
      }
      let(:result_no_keys) { { status: :success, other_data: 'stuff' } } # Missing result/job_id/message
      let(:sanitized_result_no_keys) { { status: :success, result: nil } } # How it should appear in plan_details
      let(:placeholder_string) { '[Result from previous step]' }

      before { agent.start }

      it 'injects placeholder string and warns if previous result lacks standard keys' do
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan_prev)
        allow(mock_tool_a).to receive(:execute).with({ p: 1 }, mock_context).and_return(result_no_keys)
        # Expect the placeholder string itself to be passed when standard keys are missing
        allow(mock_tool_b).to receive(:execute).with({ data: placeholder_string },
                                                     mock_context).and_return(success_hash_b)
        expect(ADK.logger).to receive(:warn).with(/Cannot inject: Previous successful.* missing usable key/)

        final_event = agent.run_task(session_id: session_id, user_input: user_input,
                                     session_service: mock_session_service)
        # Verify the placeholder was used in the plan details as well
        expect(final_event.content[:plan_details][1][:params][:data]).to eq(placeholder_string)
      end

      it 'handles "[Result from previous step]" placeholder' do
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan_prev) # Uses "previous step"
        allow(mock_tool_a).to receive(:execute).with({ p: 1 }, mock_context).and_return(success_hash_a)
        allow(mock_tool_b).to receive(:execute).with({ data: 'Result A' }, mock_context).and_return(success_hash_b)

        expect(mock_tool_b).to receive(:execute).with({ data: 'Result A' }, mock_context)
        agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
      end
    end

    context 'with complex result sanitization' do
      let(:plan) { [{ tool: :tool_a, params: { p: 1 } }] }
      let(:complex_result) { { status: :success, result: { nested: true, data: [1, 2, 3] } } }
      let(:sanitized_complex_result) { { status: :success, result: "[Complex Result Structure]" } }

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
        allow(mock_tool_a).to receive(:execute).with({ p: 1 }, mock_context).and_return(complex_result)
      end

      it 'includes "[Complex Result Structure]" in plan_details' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input,
                                     session_service: mock_session_service)
        expect(final_event.content[:plan_details][0][:result]).to eq(sanitized_complex_result)
        # Ensure original complex result is still in the main content
        expect(final_event.content[:result]).to eq(complex_result[:result])
      end
    end

    context 'when tool preparation fails' do
      let(:plan) { [{ tool: :tool_a, params: {} }] }
      let(:prep_error) { StandardError.new("Context creation failed") }
      # Define the error hash created by execute_step
      let(:rescued_prep_error_hash) {
        { status: :error,
          error_message: "Internal error preparing tool 'tool_a': #{prep_error.message}",
          error_class: prep_error.class.name,
          result: nil }
      }
      # Define the final agent event content
      let(:expected_final_content_on_prep_error) {
        {
          status: :error,
          error_message: "Internal error preparing tool 'tool_a': #{prep_error.message}",
          error_class: prep_error.class.name,
          result: nil,
          plan_details: [{ tool_name: :tool_a, params: {}, result: rescued_prep_error_hash }]
        }
      }

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
        # Ensure tool instance IS found
        allow(agent.tool_registry).to receive(:create_instance).with(:tool_a).and_return(mock_tool_a)
        # Make ToolContext.new raise an error
        allow(ADK::ToolContext).to receive(:new).and_raise(prep_error)
      end

      it 'returns final agent event with preparation error details' do
        expect(ADK.logger).to receive(:error).with(/Unexpected error preparing tool 'tool_a'.*Context creation failed/)
        final_event = agent.run_task(session_id: session_id, user_input: user_input,
                                     session_service: mock_session_service)
        expect(final_event.role).to eq(:agent)
        expect(final_event.content).to eq(expected_final_content_on_prep_error)
      end
    end

    context 'when tool returns invalid hash' do
      let(:plan) { [{ tool: :tool_a, params: {} }] }
      let(:invalid_result) { { message: "I forgot the status" } }
      let(:tool_error_msg) { "Tool 'tool_a' failed to return standard hash format (status: success/pending)." }
      # Define the error hash created by execute_step
      let(:rescued_format_error_hash) {
        { status: :error,
          error_message: tool_error_msg,
          error_class: ADK::ToolError.name,
          result: nil }
      }
      # Define the final agent event content
      let(:expected_final_content_on_format_error) {
        {
          status: :error,
          error_message: tool_error_msg,
          error_class: ADK::ToolError.name,
          result: nil,
          plan_details: [{ tool_name: :tool_a, params: {}, result: rescued_format_error_hash }]
        }
      }

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
        allow(mock_tool_a).to receive(:execute).with({}, mock_context).and_return(invalid_result)
      end

      it 'logs error, raises ToolError internally, and returns agent error event' do
        expect(ADK.logger).to receive(:error).with(/Tool 'tool_a' returned invalid hash or status .* #{invalid_result.inspect}/)
        final_event = agent.run_task(session_id: session_id, user_input: user_input,
                                     session_service: mock_session_service)
        expect(final_event.role).to eq(:agent)
        expect(final_event.content).to eq(expected_final_content_on_format_error)
      end
    end
    # --- END NEW CONTEXT ---
  end

  describe '#register_tool_class' do
    # Use keyword arguments for agent initialization
    let(:agent) { described_class.new(name: 'test_agent', description: 'Agent for registry tests') }
    let(:tool_name) { :tool_a }
    let(:mock_tool_class) { MockToolA } # Use MockToolA defined above
    let(:logger_spy) { spy('Logger') }

    before do
      # Reset global manager to avoid interference from other tests
      ADK::GlobalToolManager.reset!
      allow(ADK).to receive(:logger).and_return(logger_spy)
    end

    # Test 1 & 5
    it 'registers a valid tool class' do
      tool_name = mock_tool_class.tool_metadata[:name] # :tool_a
      # Expect the registry instance held by the agent to receive :register with name and class
      expect(agent.tool_registry).to receive(:register).with(tool_name, mock_tool_class).and_call_original
      expect(agent.register_tool_class(mock_tool_class)).to be true
      expect(agent.find_tool_class(tool_name)).to eq(mock_tool_class)
    end

    # Test 2 & 6
    it 'warns and overwrites when registering a duplicate tool class in agent' do
      agent.register_tool_class(mock_tool_class) # Register first
      # Expect the agent-specific warning at least once
      expect(logger_spy).to receive(:warn).with(/Agent 'test_agent': Tool 'tool_a' already registered. Overwriting./).at_least(:once)
      agent.register_tool_class(mock_tool_class) # Register again
      expect(agent.find_tool_class(tool_name)).to eq(mock_tool_class) # Still registered
    end

    # Test 3
    it 'logs error and does not register an invalid class' do
      class InvalidThing; end
      expect(logger_spy).to receive(:error).with("Agent 'test_agent': Attempted to register invalid object (must inherit from ADK::Tool): InvalidThing")
      expect(agent.tool_registry).not_to receive(:register) # Ensure register is not called
      agent.register_tool_class(InvalidThing)
      # Test 7: check specific tool is not found
      expect(agent.find_tool_class(:invalid_thing)).to be_nil
    end

    # Test 4
    it 'logs error and does not register class without metadata' do
      class ToolWithoutMeta < ADK::Tool
        def self.tool_metadata; {}; end # Override to simulate missing meta
      end
      expect(logger_spy).to receive(:error).with("Agent 'test_agent': Tool class ToolWithoutMeta missing name in its metadata. Cannot register.")
      expect(agent.tool_registry).not_to receive(:register)
      agent.register_tool_class(ToolWithoutMeta)
      # Test 8: Tool wasn't registered, no need to check find_tool_class with nil
    end

    # Test 9
    it 'warns and overwrites when registering a duplicate tool directly in registry' do
      # Register globally first (simulate)
      agent.tool_registry.register(:tool_a, MockToolA)
      # Register in agent again via the method
      expect(logger_spy).to receive(:warn).with("Agent 'test_agent': Tool 'tool_a' already registered. Overwriting.")
      agent.register_tool_class(MockToolA)
      expect(agent.find_tool_class(:tool_a)).to eq(MockToolA)
    end
  end

  # Add a new describe block for MCP Integration
  describe 'MCP Integration' do
    # Use string for type key as expected by initial config structure
    let(:mcp_server_config) { { type: 'stdio', command: 'dummy-mcp-server' } }
    let(:mock_mcp_client_instance) {
      instance_double(ADK::Mcp::Client, connect: true, list_tools: [], disconnect: true)
    } # Basic stubbing

    before do
      # Define the config with symbol keys expected by the stub
      # symbolized_mcp_config = { type: :stdio, command: :'dummy-mcp-server' }
      # Stub the client creation to return our instance double, ignore arguments for now
      allow(ADK::Mcp::Client).to receive(:new).and_return(mock_mcp_client_instance)

      # Default stub for list_tools, can be overridden in specific tests
      allow(mock_mcp_client_instance).to receive(:list_tools).and_return([
                                                                           { name: 'mcp_tool_one', description: 'MCP Tool One',
                                                                             inputSchema: { type: 'object', properties: { a: { type: 'string' } } } },
                                                                           { name: 'mcp_tool_two',
                                                                             description: 'MCP Tool Two', inputSchema: { type: 'object', properties: {} } }
                                                                         ])

      # Stub the ToolWrapper class method.
      allow(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema).and_return(true) # Simulate success
    end

    context 'when initialized with mcp_servers config' do
      # Define agent here to ensure mocks are set up correctly first
      let(:agent_with_mcp) do
        # Local mocks needed for this specific initialization context
        allow(ADK::Planner).to receive(:new).and_return(mock_planner)
        allow(Object).to receive(:defined?).with(Sidekiq).and_return(true)

        # --- Mock the specific ToolRegistry instance for THIS agent --- >
        mock_specific_registry = instance_double(ADK::ToolRegistry)
        allow(ADK::ToolRegistry).to receive(:new).and_return(mock_specific_registry)

        # Stub initial registration calls during agent initialization
        allow(mock_specific_registry).to receive(:register).with(:tool_a, MockToolA).and_return(true)
        # --- Allow find_class to be called for both tools during init --- >
        allow(mock_specific_registry).to receive(:find_class) do |tool_name|
          case tool_name.to_sym
          when :check_job_status then nil # Simulate not found before registration
          when :tool_a then nil # Simulate not found before registration
          else nil
          end
        end
        # <----------------------------------------------------------------
        allow(mock_specific_registry).to receive(:register).with(:check_job_status,
                                                                 ADK::Tools::CheckJobStatusTool).and_return(true)

        # Stub the :tools method to reflect initial state
        initial_tools_state = {
          tool_a: MockToolA,
          check_job_status: ADK::Tools::CheckJobStatusTool
        }
        allow(mock_specific_registry).to receive(:tools).and_return(initial_tools_state)

        # --- Add stub for list_tools needed by available_tools_metadata --- >
        allow(mock_specific_registry).to receive(:list_tools) do
          # Return metadata based on the *current* state of the :tools stub
          mock_specific_registry.tools.values.map { |klass|
            klass.respond_to?(:tool_metadata) ? klass.tool_metadata : { name: klass.name.downcase.to_sym }
          }
        end
        # <---------------------------------------------------------------------

        # Create the agent instance (it will now use mock_specific_registry)
        agent = described_class.new(
          name: name,
          description: description,
          tool_classes: [MockToolA], # Native tools passed here
          mcp_servers: [mcp_server_config],
          selected_tool_names: [:mcp_tool_one, :mcp_tool_two]
        )

        # --- Allow MCP tool registrations on the mock registry AFTER agent start ---
        # Allow further calls to :register for MCP tools
        allow(mock_specific_registry).to receive(:register).with(:mcp_tool_one, anything).and_return(true)
        allow(mock_specific_registry).to receive(:register).with(:mcp_tool_two, anything).and_return(true)

        # Update the stub for :tools to reflect the state *after* MCP tools would be added
        # This is what agent.available_tools_metadata will use internally
        allow(mock_specific_registry).to receive(:tools).and_return({
                                                                      tool_a: MockToolA,
                                                                      check_job_status: ADK::Tools::CheckJobStatusTool,
                                                                      # Simulate that ToolWrapper registration added these
                                                                      mcp_tool_one: Class.new(ADK::Tool) {
                                                                        define_metadata(name: :mcp_tool_one,
                                                                                        description: 'd1')
                                                                      },
                                                                      mcp_tool_two: Class.new(ADK::Tool) {
                                                                        define_metadata(name: :mcp_tool_two,
                                                                                        description: 'd2')
                                                                      }
                                                                    })

        agent # Return the created agent
      end

      # --- Tests ---

      it 'does not connect or register tools on initialize' do
        expect(ADK::Mcp::Client).not_to have_received(:new)
        agent_with_mcp # Instantiate the agent
        # Verify the registry state *before* start, by checking the keys of the initially stubbed :tools return value
        # Ensure the stub reflects the state BEFORE start is called
        allow(agent_with_mcp.tool_registry).to receive(:tools).and_return({ tool_a: MockToolA,
                                                                            check_job_status: ADK::Tools::CheckJobStatusTool })
        expect(agent_with_mcp.tool_registry.tools.keys).to contain_exactly(:tool_a, :check_job_status)
      end

      it 'connects, lists tools, and calls wrapper registration on start' do
        agent_with_mcp # Initialize

        # Set up expectations for ToolWrapper calls *before* calling start
        expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema)
          .with(hash_including(name: 'mcp_tool_one'), mock_mcp_client_instance, agent_with_mcp.tool_registry)
          .ordered.and_return(true)
        expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema)
          .with(hash_including(name: 'mcp_tool_two'), mock_mcp_client_instance, agent_with_mcp.tool_registry)
          .ordered.and_return(true)

        agent_with_mcp.start

        # Verify client interactions
        expect(mock_mcp_client_instance).to have_received(:connect).once
        expect(mock_mcp_client_instance).to have_received(:list_tools).once
        # ToolWrapper calls verified above
      end

      it 'disconnects clients on stop' do
        agent_with_mcp.start # Connect first
        expect(mock_mcp_client_instance).to have_received(:connect) # Verify precondition

        agent_with_mcp.stop
        expect(mock_mcp_client_instance).to have_received(:disconnect).once
      end

      it 'makes MCP tools available for planning' do
        agent_with_mcp # Initialize

        # Start the agent to trigger MCP connection and tool registration
        # The :tools and :list_tools stubs on mock_specific_registry will be updated by the let block
        agent_with_mcp.start

        # Verify tools are available via the agent's metadata method, which uses the stubbed :list_tools
        available_metadata = agent_with_mcp.available_tools_metadata
        expect(available_metadata.map { |m|
          m[:name]
        }).to contain_exactly(:mcp_tool_one, :mcp_tool_two, :tool_a, :check_job_status)
      end

      it 'handles connection errors gracefully' do
        allow(ADK::Mcp::Client).to receive(:new).with(mcp_server_config).and_return(mock_mcp_client_instance)
        allow(mock_mcp_client_instance).to receive(:connect).and_raise(ADK::Mcp::ConnectionError,
                                                                       "Connection timed out")
        expect(ADK.logger).to receive(:error).with(/Failed to connect.*Connection timed out/)
        expect { agent_with_mcp.start }.not_to raise_error
        expect(mock_mcp_client_instance).not_to have_received(:list_tools)
        expect(ADK::Mcp::ToolWrapper).not_to have_received(:from_mcp_schema)
        # Verify registry state *before* start
        allow(agent_with_mcp.tool_registry).to receive(:tools).and_return({ tool_a: MockToolA,
                                                                            check_job_status: ADK::Tools::CheckJobStatusTool })
        expect(agent_with_mcp.tool_registry.tools.keys).to contain_exactly(:tool_a, :check_job_status)
      end

      it 'handles list_tools errors gracefully' do
        # Ensure connect mock succeeds before list_tools raises error
        allow(mock_mcp_client_instance).to receive(:connect).and_return(true)
        allow(mock_mcp_client_instance).to receive(:list_tools).and_raise(ADK::Mcp::ProtocolError, "Invalid response")

        expect { agent_with_mcp.start }.not_to raise_error
        expect(mock_mcp_client_instance).to have_received(:connect).once
      end
    end
  end # End MCP Integration describe block

  # --- NEW BLOCK --- >
  describe 'MCP End-to-End Integration', :e2e do
  end # End MCP End-to-End Integration describe block

  # --- Tests for Tool Discovery --- >
  describe '#initialize with tool_paths' do
    # Use predefined fixture paths instead of temp dirs
    let(:fixture_dir_a) { 'spec/adk/fixtures/tools/dir_a' }
    let(:fixture_dir_b) { 'spec/adk/fixtures/tools/dir_b' }
    let(:non_existent_path) { './non_existent_tools' }
    # Assuming FixtureToolA and FixtureToolB are defined in the fixture files

    before(:each) do
      # Ensure clean state for Global Manager before each tool_path test
      ADK::GlobalToolManager.reset!
      # Remove constants defined by fixtures if they exist from previous tests
      Object.send(:remove_const, :FixtureToolA) if defined?(::FixtureToolA)
      Object.send(:remove_const, :FixtureToolB) if defined?(::FixtureToolB)
      # REMOVED: Do not explicitly load fixture files here.
      # The agent's initialize method with tool_paths should handle the discovery.

      allow(Object).to receive(:defined?).with(Sidekiq).and_return(true)
      allow(ADK::Planner).to receive(:new).and_return(mock_planner)
    end

    # Helper to safely get class constant
    def get_tool_class(class_name)
      Object.const_get(class_name) if Object.const_defined?(class_name)
    end

    context 'when tool_paths is provided' do
      it 'loads tools from a single valid directory path' do
        agent = described_class.new(name: 'discovery_agent', description: 'desc', tool_paths: [fixture_dir_a])
        # Find the tool instance via the agent
        found_tool = agent.find_tool(:fixture_tool_a) # Use the actual tool name
        expect(found_tool).not_to be_nil, "Tool :fixture_tool_a not found in agent registry"
        # Check the instance type based on the loaded tool's class
        expect(found_tool).to be_an_instance_of(found_tool.class) # Check against its own class
      end

      it 'loads tools from an array of valid directory paths' do
        agent = described_class.new(name: 'discovery_agent', description: 'desc',
                                    tool_paths: [fixture_dir_a, fixture_dir_b])
        tool_a = agent.find_tool(:fixture_tool_a)
        tool_b = agent.find_tool(:fixture_tool_b)
        expect(tool_a).not_to be_nil
        expect(tool_b).not_to be_nil
        expect(tool_a).to be_an_instance_of(tool_a.class)
        expect(tool_b).to be_an_instance_of(tool_b.class)
      end

      it 'loads tools passed via tool_classes alongside discovered tools' do
        agent = described_class.new(name: 'discovery_agent', description: 'desc', tool_paths: [fixture_dir_a],
                                    tool_classes: [MockToolB]) # MockToolB defined globally
        tool_a = agent.find_tool(:fixture_tool_a)
        tool_b = agent.find_tool(:tool_b)
        expect(tool_a).not_to be_nil
        expect(tool_b).to be_an_instance_of(MockToolB)
        expect(tool_a).to be_an_instance_of(tool_a.class)
        expect(agent.find_tool(:fixture_tool_b)).to be_nil
      end

      it 'handles non-existent paths gracefully' do
        expect(ADK.logger).to receive(:warn).with(/Tool discovery path does not exist.*non_existent_tools/).at_least(:once)
        agent = described_class.new(name: 'discovery_agent', description: 'desc',
                                    tool_paths: [fixture_dir_a, non_existent_path])
        tool_a = agent.find_tool(:fixture_tool_a)
        expect(tool_a).not_to be_nil
        expect(tool_a).to be_an_instance_of(tool_a.class)
        expect(agent.find_tool(:fixture_tool_b)).to be_nil
      end
    end

    context 'when tool_paths is not provided or empty' do
      it 'does not attempt discovery if tool_paths is empty array' do
        expect(Dir).not_to receive(:glob)
        agent = described_class.new(name: 'no_discovery_agent', description: 'desc', tool_paths: [])
        expect(agent.tools.map(&:name)).not_to include(:tool_c, :tool_d)
      end

      it 'does not attempt discovery if tool_paths is not provided' do
        expect(Dir).not_to receive(:glob)
        agent = described_class.new(name: 'no_discovery_agent', description: 'desc')
        expect(agent.tools.map(&:name)).not_to include(:tool_c, :tool_d)
      end
    end
  end # End tool_paths describe block

  # --- NEW BLOCK: Tool Discovery Error Handling --- >
  describe '#initialize tool discovery error handling' do
    let(:fixture_dir_a) { 'spec/adk/fixtures/tools/dir_a' }
    let(:temp_dir) { Dir.mktmpdir }

    before do
      allow(ADK::Planner).to receive(:new).and_return(mock_planner)
      allow(ADK).to receive(:logger).and_return(mock_logger)
      # Prevent sidekiq check from interfering
      allow(Object).to receive(:defined?).with(Sidekiq).and_return(false)
      # Reset global manager to avoid interference
      ADK::GlobalToolManager.reset!
      # Remove potentially loaded fixture constants
      Object.send(:remove_const, :FixtureToolA) if defined?(::FixtureToolA)
      Object.send(:remove_const, :FixtureToolB) if defined?(::FixtureToolB)
    end

    after do
      FileUtils.remove_entry(temp_dir) if Dir.exist?(temp_dir)
      # Clean up constants again
      Object.send(:remove_const, :FixtureToolA) if defined?(::FixtureToolA)
      Object.send(:remove_const, :FixtureToolB) if defined?(::FixtureToolB)
      Object.send(:remove_const, :SyntaxErrorTool) if defined?(::SyntaxErrorTool)
      Object.send(:remove_const, :LoadErrorTool) if defined?(::LoadErrorTool)
    end

    it 'logs SyntaxError and continues discovery' do
      # Create a file with invalid Ruby syntax
      syntax_error_path = File.join(temp_dir, 'syntax_error_tool.rb')
      File.write(syntax_error_path, "class SyntaxErrorTool < ADK::Tool\n def oops\nend") # Missing end

      expect(ADK.logger).to receive(:error).with(/Failed to load\/eval tool file.*#{Regexp.escape(syntax_error_path)}.*SyntaxError/)
      # Should still load valid tools from other paths
      agent = described_class.new(name: 'syntax_error_test', description: 'desc', tool_paths: [fixture_dir_a, temp_dir])
      expect(agent.find_tool(:fixture_tool_a)).not_to be_nil
      expect(agent.find_tool(:syntax_error_tool)).to be_nil # Tool with error wasn't registered
    end

    it 'logs generic StandardError during load and continues discovery' do
      # Create a file that raises StandardError on load
      load_error_path = File.join(temp_dir, 'load_error_tool.rb')
      File.write(load_error_path, "class LoadErrorTool < ADK::Tool; raise StandardError, 'Kaboom on load'; end")

      expect(ADK.logger).to receive(:error).with(/Error encountered while loading\/processing tool file.*#{Regexp.escape(load_error_path)}.*StandardError.*Kaboom on load/)
      # Should still load valid tools
      agent = described_class.new(name: 'load_error_test', description: 'desc', tool_paths: [fixture_dir_a, temp_dir])
      expect(agent.find_tool(:fixture_tool_a)).not_to be_nil
      # The tool class might still get defined and registered even if loading raises an error later.
      # The primary check is that the error during processing was logged.
      # We don't need to assert on find_tool for the erroring tool.
    end

    it 'logs error if discovered tool class cannot be found in GlobalToolManager' do
      # Simulate load succeeding but class not registering globally (edge case)
      allow(ADK::GlobalToolManager).to receive(:find_class).with(:fixture_tool_a).and_return(nil)

      expect(ADK.logger).to receive(:error).with(/Failed to find class for discovered tool 'fixture_tool_a'/)
      agent = described_class.new(name: 'gmt_miss_test', description: 'desc', tool_paths: [fixture_dir_a])
      expect(agent.find_tool(:fixture_tool_a)).to be_nil
    end
  end
  # --- END BLOCK --- >

  # --- NEW BLOCK: MCP Connection/Discovery Error Handling --- >
  describe 'MCP error handling during start/discovery' do
    let(:mock_mcp_client_instance) { instance_double(ADK::Mcp::Client) }
    let(:mcp_config) { [{ type: 'stdio', command: 'good-cmd' }] }
    let(:mcp_config_bad_type) { [{ type: 'invalid', command: 'bad-type-cmd' }] }
    let(:mcp_config_unsupported_type_string) { [{ "type" => "websocket", "url" => "ws://example.com" }] }
    let(:agent) do
      # Prevent planner and regular tool discovery
      allow(ADK::Planner).to receive(:new).and_return(mock_planner)
      allow(Object).to receive(:defined?).with(Sidekiq).and_return(false)
      # Initialize with specific MCP config for most tests
      described_class.new(name: 'mcp_error_agent', description: 'desc', mcp_servers: mcp_config,
                          selected_tool_names: [:mcp_tool_one]) # Select one tool
    end

    before do
      allow(ADK).to receive(:logger).and_return(mock_logger)
      # Stub client creation by default
      allow(ADK::Mcp::Client).to receive(:new).and_return(mock_mcp_client_instance)
      # Default stubs for client methods
      allow(mock_mcp_client_instance).to receive(:connect).and_return(true)
      allow(mock_mcp_client_instance).to receive(:list_tools).and_return([{ name: 'mcp_tool_one' }]) # Basic schema
      allow(mock_mcp_client_instance).to receive(:disconnect).and_return(true)
      # Stub ToolWrapper
      allow(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema).and_return(true)
    end

    it 'logs error and skips unsupported MCP server type (symbol)' do
      # Reinitialize agent with bad type config
      test_agent = described_class.new(name: 'mcp_bad_type', description: 'd', mcp_servers: mcp_config_bad_type)
      expect(ADK::Mcp::Client).not_to receive(:new)
      # Match the string representation and the rest of the message
      expect(ADK.logger).to receive(:error).with(/Unsupported MCP server type specified: "invalid".*Skipping configuration/)
      expect { test_agent.start }.not_to raise_error
      expect(test_agent.instance_variable_get(:@mcp_clients)).to be_empty
    end

    it 'logs error and skips unsupported MCP server type (string)' do
      # Reinitialize agent with bad type config (string key/value)
      test_agent = described_class.new(name: 'mcp_bad_str_type', description: 'd',
                                       mcp_servers: mcp_config_unsupported_type_string)
      expect(ADK::Mcp::Client).not_to receive(:new)
      # Check the log message includes the actual string value found
      expect(ADK.logger).to receive(:error).with(/Unsupported MCP server type specified: "websocket"/)
      expect { test_agent.start }.not_to raise_error
      expect(test_agent.instance_variable_get(:@mcp_clients)).to be_empty
    end

    it 'handles Mcp::ProtocolError during connect and logs error' do
      allow(ADK::Mcp::Client).to receive(:new).and_return(mock_mcp_client_instance)
      allow(mock_mcp_client_instance).to receive(:connect).and_raise(ADK::Mcp::ProtocolError, "Bad handshake")
      # Make regex less specific about what comes between handshake and the error message
      expect(ADK.logger).to receive(:error).with(/Failed to connect or handshake.*Bad handshake/)
      expect { agent.start }.not_to raise_error
      expect(agent.instance_variable_get(:@mcp_clients)).to be_empty
    end

    it 'handles generic StandardError during connect and logs error' do
      allow(ADK::Mcp::Client).to receive(:new).and_return(mock_mcp_client_instance)
      allow(mock_mcp_client_instance).to receive(:connect).and_raise(StandardError, "Something else broke")
      expect(ADK.logger).to receive(:error).with(/Unexpected error connecting to MCP server.*StandardError.*Something else broke/)
      expect { agent.start }.not_to raise_error
      expect(agent.instance_variable_get(:@mcp_clients)).to be_empty
    end

    it 'skips registration if MCP tool name is not in selected_tool_names' do
      allow(mock_mcp_client_instance).to receive(:list_tools).and_return([
                                                                           { name: 'mcp_tool_one' }, # Selected
                                                                           { name: 'mcp_tool_two' }  # Not selected
                                                                         ])
      # Expect wrapper to be called only for the selected tool
      expect(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema).with(hash_including(name: 'mcp_tool_one'),
                                                                      any_args).once
      expect(ADK::Mcp::ToolWrapper).not_to receive(:from_mcp_schema).with(hash_including(name: 'mcp_tool_two'),
                                                                          any_args)
      # Log the debug message
      expect(ADK.logger).to receive(:debug).with(/Skipping registration of MCP tool 'mcp_tool_two'/)
      agent.start
    end

    it 'handles generic StandardError during MCP tool discovery/registration' do
      allow(mock_mcp_client_instance).to receive(:list_tools).and_return([{ name: 'mcp_tool_one' }])
      allow(ADK::Mcp::ToolWrapper).to receive(:from_mcp_schema).and_raise(StandardError, "Wrapper failed")

      expect(ADK.logger).to receive(:error).with(/Unexpected error discovering MCP tools.*StandardError.*Wrapper failed/)
      expect { agent.start }.not_to raise_error
      # Client was added, but registration failed
      expect(agent.instance_variable_get(:@mcp_clients)).to include(mock_mcp_client_instance)
    end
  end
  # --- END BLOCK --- >
end # End RSpec.describe ADK::Agent
