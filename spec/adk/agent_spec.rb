# File: spec/adk/agent_spec.rb
require 'spec_helper'

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
  let(:mock_session) { instance_double(ADK::Session, id: session_id, events: []) }

  # Tools
  let(:mock_tool_a) { instance_double(ADK::Tool, name: :tool_a) }
  let(:mock_tool_b) { instance_double(ADK::Tool, name: :tool_b) }

  # Results
  let(:success_hash_a) { { status: :success, result: 'Result A' } }
  let(:success_hash_b) { { status: :success, result: 'Result B' } }
  let(:error_hash) { { status: :error, error_message: 'Something failed' } }

  # Events (use real structs where possible, mock only when necessary)
  let(:user_input) { "Test user input" }
  let(:agent_error_event) { instance_double(ADK::Event, role: :agent, content: "Error message") }
  # Let event creation happen naturally unless we need to intercept it

  # --- Agent Instance ---
  # Use let! to ensure agent is created before tests that might need it implicitly
  let!(:agent) do
    # Stub Planner creation *before* agent is initialized
    allow(ADK::Planner).to receive(:new).and_return(mock_planner)
    # Create the agent instance
    described_class.new(
      name: name,
      description: description,
      model_name: model_name,
      logger: mock_logger
      # Note: Planner is mocked via the allow above
    )
  end

  # --- General Setup ---
  before do
    # Ensure tools respond correctly to is_a? for add_tool
    allow(mock_tool_a).to receive(:is_a?).with(ADK::Tool).and_return(true)
    allow(mock_tool_b).to receive(:is_a?).with(ADK::Tool).and_return(true)

    # Default session service behavior
    allow(mock_session_service).to receive(:get_session).with(session_id: session_id).and_return(mock_session)
    allow(mock_session_service).to receive(:append_event).and_return(true)

    # Allow normal event creation by default
    allow(ADK::Event).to receive(:new).and_call_original

    # Silence the real logger unless needed for specific tests
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

    it 'initializes with an empty tools list' do
      expect(agent.tools).to eq([])
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
    end

    context 'pre-execution checks' do
      it 'returns error hash if agent is not running' do
        # Agent is stopped by default after initialization in `let!`
        result = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
        expect(result).to be_an(ADK::Event)
        expect(result.role).to eq(:agent)
        expect(result.content).to include("not active")
      end

      it 'returns error hash if session not found' do
        agent.start # Agent must be running
        allow(mock_session_service).to receive(:get_session).with(session_id: session_id).and_return(nil)
        result = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
        expect(result).to be_an(ADK::Event)
        expect(result.role).to eq(:agent)
        expect(result.content).to include("Session not found")
      end
    end

    context 'successful single-step execution' do
      let(:plan) { [{ tool: :tool_a, params: { p: 1 } }] }

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
        allow(mock_tool_a).to receive(:execute).with({ p: 1 }).and_return(success_hash_a)
      end

      it 'records user, tool request, tool result, and agent events' do
        expect(mock_session_service).to receive(:append_event).with(session_id: session_id,
                                                                    event: instance_of(ADK::Event)).exactly(4).times.and_return(true)
        agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
      end

      it 'returns the final agent event with the tool result' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input,
                                     session_service: mock_session_service)
        expect(final_event).to be_an(ADK::Event)
        expect(final_event.role).to eq(:agent)
        expect(final_event.content).to eq(success_hash_a[:result])
      end
    end

    context 'successful multi-step execution with injection' do
      let(:plan) { [{ tool: :tool_a, params: { p: 1 } }, { tool: :tool_b, params: { data: '[Result from step 1]' } }] }

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
        allow(mock_tool_a).to receive(:execute).with({ p: 1 }).and_return(success_hash_a)
        allow(mock_tool_b).to receive(:execute).with({ data: 'Result A' }).and_return(success_hash_b)
      end

      it 'injects result from step 1 into step 2 params' do
        expect(mock_tool_b).to receive(:execute).with({ data: 'Result A' }).and_return(success_hash_b)
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
        expect(final_event.content).to eq(success_hash_b[:result])
      end
    end

    context 'multi-step execution with error and plan halting' do
      let(:plan) { [{ tool: :tool_a, params: { p: 1 } }, { tool: :tool_b, params: { data: '[Result from step 1]' } }] }
      let(:error_event) {
        instance_double(ADK::Event, role: :agent,
                                    content: "Completed plan with error on last step: #{error_hash[:error_message]}")
      }

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
        allow(mock_tool_a).to receive(:execute).with({ p: 1 }).and_return(error_hash)
        allow(ADK::Event).to receive(:new).with(hash_including(role: :agent,
                                                               content: /Completed plan with error/i)).and_return(error_event)
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
        expect(final_event).to be_an(ADK::Event)
        expect(final_event.role).to eq(:agent)
        expect(final_event.content).to include("Error during processing: #{error_hash[:error_message]}")
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
        expect(result.content).to include("I cannot fulfill this request with the available tools")
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
          event: having_attributes(role: :agent, content: /internal error.*Planner explosion/i)
        )

        result = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
        expect(result).to be_an(ADK::Event)
        expect(result.role).to eq(:agent)
        expect(result.content).to include("An internal error occurred during task processing: Planner explosion")
      end
    end

    context 'when finding a tool raises an error' do
      let(:bad_tool_plan) { [{ tool: :missing_tool, params: {} }] }
      let(:error_event) {
        instance_double(ADK::Event, role: :agent,
                                    content: "Completed plan with error on last step: Tool 'missing_tool' not found for this agent.")
      }

      before do
        agent.start
        allow(mock_planner).to receive(:plan).with(user_input).and_return(bad_tool_plan)
        allow(ADK::Event).to receive(:new).with(hash_including(role: :agent,
                                                               content: /Tool 'missing_tool' not found/)).and_return(error_event)
      end

      it 'returns the final agent event with error content' do
        result = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
        expect(result).to eq(error_event)
        expect(result.content).to include("Tool 'missing_tool' not found")
      end
    end
  end
end
