# File: spec/adk/agent_spec.rb
require 'spec_helper'
require 'sidekiq/testing'

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
  let(:pending_hash) { { status: :pending, job_id: job_id, message: 'Job enqueued.' } }
  let(:error_hash) { { status: :error, error_message: 'Something failed' } }

  # Events
  let(:user_input) { "Test user input" }
  let(:agent_error_event) { instance_double(ADK::Event, role: :agent, content: "Error message") }

  # --- Agent Instance ---
  let!(:agent) do
    # Mock Planner before agent initialization
    allow(ADK::Planner).to receive(:new).and_return(mock_planner)
    # Mock ToolContext creation (will be called by execute_step)
    allow(ADK::ToolContext).to receive(:new).with(session_id: session_id, user_id: user_id,
                                                  app_name: app_name).and_return(mock_context)
    # Mock ToolRegistry call during agent init for check_job_status
    allow(ADK::ToolRegistry).to receive(:create_instance).with(:check_job_status).and_return(mock_status_tool)
    allow(mock_status_tool).to receive(:is_a?).with(ADK::Tool).and_return(true) # Allow adding the status tool
    # Stub Sidekiq configuration check during init
    allow(Object).to receive(:defined?).with(Sidekiq).and_return(true)

    # Initialize agent
    described_class.new(name: name, description: description, model_name: model_name, logger: mock_logger)
  end

  # --- General Setup ---
  before do
    # Tool type checking
    allow(mock_tool_a).to receive(:is_a?).with(ADK::Tool).and_return(true)
    allow(mock_tool_b).to receive(:is_a?).with(ADK::Tool).and_return(true)
    allow(mock_status_tool).to receive(:is_a?).with(ADK::Tool).and_return(true)
    allow(mock_async_tool).to receive(:is_a?).with(ADK::Tool).and_return(true)
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
      agent_default = described_class.new(name: name, description: description, logger: mock_logger)
      expect(agent_default.model_name).to eq(default_model)
      # Verify planner was initialized with default model
      expect(ADK::Planner).to have_received(:new).with(hash_including(model_name: default_model))
    end

    it 'initializes with a planner' do
      expect(agent.planner).to eq(mock_planner)
    end

    it 'initializes with check_job_status tool if Sidekiq defined' do
      # Check that the check_job_status tool (mocked) is present
      expect(agent.tools).to include(mock_status_tool)
      expect(agent.tools.map(&:name)).to include(:check_job_status)
    end

    it 'automatically adds check_job_status tool if Sidekiq is defined' do
      # Agent initialization is already stubbed in the main let! block
      expect(agent.tools.map(&:name)).to include(:check_job_status)
    end
  end

  describe '#add_tool' do
    it 'adds a valid tool' do
      expect { agent.add_tool(mock_tool_a) }.to change { agent.tools.count }.by(1)
      expect(agent.tools).to include(mock_tool_a)
    end

    it 'warns and does not add a duplicate tool', :log_level do
      agent.add_tool(mock_tool_a) # Add once
      expect(mock_logger).to receive(:warn).with(/already added/)
      expect { agent.add_tool(mock_tool_a) }.not_to change { agent.tools.count }
    end

    it 'errors and does not add an invalid object', :log_level do
      expect(mock_logger).to receive(:error).with(/Attempted to add invalid tool/)
      expect { agent.add_tool("not a tool") }.not_to change { agent.tools.count }
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
        expect(final_event.content).to eq(success_hash_a)
      end
    end

    context 'successful multi-step execution with injection' do
      let(:plan) { [{ tool: :tool_a, params: { p: 1 } }, { tool: :tool_b, params: { data: '[Result from step 1]' } }] }

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
        expect(final_event.content).to eq(success_hash_b)
      end
    end

    context 'when a step returns a pending status' do
      let(:plan) { [{ tool: :async_tool, params: { input: 'go' } }] }

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
        expect(final_event.content).to eq(pending_hash) # Expecting the hash with job_id
      end
    end

    context 'multi-step execution with job_id injection' do
      let(:plan) {
        [{ tool: :async_tool, params: { input: 'start' } },
         { tool: :check_job_status, params: { job_id: '[Result from step 1]' } }]
      }
      let(:check_result_success) { { status: :success, result: 'Job Done' } }

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
        expect(final_event.content).to eq(check_result_success)
      end
    end

    context 'multi-step execution with error and plan halting' do
      let(:plan) { [{ tool: :tool_a, params: { p: 1 } }, { tool: :tool_b, params: { data: '[Result from step 1]' } }] }
      let(:error_event) { ADK::Event.new(role: :agent, content: error_hash) }

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
        allow(mock_tool_a).to receive(:execute).with({ p: 1 }, mock_context).and_return(error_hash)
        allow(ADK::Event).to receive(:new).with(hash_including(role: :agent,
                                                               content: error_hash)).and_return(error_event)
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
        expect(final_event.content).to eq(error_hash)
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
        expect(mock_logger).to receive(:error).with(/Critical error during run_task.*Planner explosion/)
        expect(mock_session_service).to receive(:append_event).with(
          session_id: session_id,
          event: having_attributes(role: :agent,
                                   content: { status: :error,
                                              error_message: /An internal error occurred.*Planner explosion/i })
        )

        result = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
        expect(result).to be_an(ADK::Event)
        expect(result.role).to eq(:agent)
        expected_error_hash = { status: :error, error_message: "An internal error occurred: Planner explosion" }
        expect(result.content).to eq(expected_error_hash)
      end
    end

    context 'when finding a tool raises an error' do
      let(:bad_tool_plan) { [{ tool: :missing_tool, params: {} }] }
      let(:expected_error_hash) { { status: :error, error_message: "Tool 'missing_tool' not found for this agent." } }
      let(:error_event) { ADK::Event.new(role: :agent, content: expected_error_hash) }

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(bad_tool_plan)
        allow(ADK::Event).to receive(:new).with(hash_including(role: :agent,
                                                               content: expected_error_hash)).and_return(error_event)
      end

      it 'returns the final agent event with error content' do
        result = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
        expect(result.role).to eq(error_event.role)
        expect(result.content).to eq(error_event.content)
      end
    end
  end
end
