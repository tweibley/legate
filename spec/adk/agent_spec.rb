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

    # Mock ToolRegistry
    # allow_any_instance_of(ADK::ToolRegistry).to receive(:find_class) do |_, name|
    #   case name.to_sym
    #   when :tool_a then MockToolA
    #   when :tool_b then MockToolB
    #   when :check_job_status then ADK::Tools::CheckJobStatusTool
    #   else nil
    #   end
    # end
    # allow_any_instance_of(ADK::ToolRegistry).to receive(:create_instance) do |_, name|
    #   case name.to_sym
    #   when :tool_a then mock_tool_a
    #   when :tool_b then mock_tool_b
    #   when :check_job_status then mock_status_tool
    #   else nil
    #   end
    # end

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
  end

  describe '#add_tool' do
    let(:mock_registry) { instance_double(ADK::ToolRegistry) }

    before do
      allow(ADK::ToolRegistry).to receive(:new).and_return(mock_registry)
      allow(mock_registry).to receive(:tools).and_return({})
      allow(mock_registry).to receive(:register).with(:check_job_status, ADK::Tools::CheckJobStatusTool)
      allow(mock_registry).to receive(:register).with(:tool_a, MockToolA)
      allow(mock_registry).to receive(:register).with(:tool_b, MockToolB)
      allow(mock_registry).to receive(:create_instance)
      # Add find_class stub for initialization check
      allow(mock_registry).to receive(:find_class).with(:check_job_status).and_return(nil)
      allow(mock_registry).to receive(:find_class).with(:tool_a).and_return(MockToolA)
      # Mock ADK.logger
      allow(ADK).to receive(:logger).and_return(mock_logger)
      # Mock Planner for agent initialization
      allow(ADK::Planner).to receive(:new).and_return(mock_planner)
    end

    it 'adds a valid tool' do
      puts "[Test add_tool] Agent registry ID BEFORE add: #{agent.tool_registry.object_id}"
      result = agent.add_tool(MockToolA)
      puts "[Test add_tool] Agent registry ID AFTER add: #{agent.tool_registry.object_id}"
      puts "[Test add_tool] add_tool result: #{result.inspect}"
      expect(result).to be true
      # Also check find_tool immediately after adding
      puts "[Test add_tool] Agent registry ID BEFORE find_tool: #{agent.tool_registry.object_id}"
      found_tool = agent.find_tool(:tool_a)
      puts "[Test add_tool] find_tool result: #{found_tool.inspect}"
      expect(found_tool).to be_an_instance_of(MockToolA)
    end

    it 'warns and overwrites when adding a duplicate tool' do
      agent = described_class.new(name: 'test_agent', description: 'Test agent for tool tests')
      allow(mock_registry).to receive(:find_class).with(:tool_a).and_return(MockToolA)
      expect(mock_logger).to receive(:warn).with(/Tool 'tool_a' already added. Overwriting./)
      agent.add_tool(MockToolA)
    end

    it 'errors and does not add an invalid object' do
      agent = described_class.new(name: 'test_agent', description: 'Test agent for tool tests')
      invalid_object = Object.new
      expect(mock_logger).to receive(:error).with(/Attempted to add invalid tool/)
      expect(agent.add_tool(invalid_object)).to be false
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
end # End RSpec.describe ADK::Agent
