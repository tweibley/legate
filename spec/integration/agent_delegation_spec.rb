# frozen_string_literal: true

require 'spec_helper'
require 'adk/custom_agent_patch'
require 'adk/tools/echo'

RSpec.describe "Agent Delegation Integration", :integration do
  let(:mock_session_service) do
    double(
      get_session: mock_session,
      append_event: true,
      set_state: true,
      respond_to?: true
    )
  end

  let(:mock_session) do
    instance_double(
      ADK::Session,
      id: 'test-session-123',
      user_id: 'test-user-123',
      app_name: 'test-app',
      events: [],
      get_state: nil
    )
  end

  let(:coordinator_definition) do
    ADK::AgentDefinition.new.define do |a|
      a.name :coordinator_agent
      a.description 'Coordinator agent that delegates tasks'
      a.instruction 'You coordinate tasks between specialized agents'
      a.can_delegate_to :calculator_agent, :research_agent
      a.use_tool :echo
      a.fallback_mode :error
    end
  end

  let(:calculator_definition) do
    ADK::AgentDefinition.new.define do |a|
      a.name :calculator_agent
      a.description 'Agent that handles math calculations'
      a.instruction 'You are a specialized calculator agent'
      a.use_tool :calculator
      a.fallback_mode :error
    end
  end

  let(:research_definition) do
    ADK::AgentDefinition.new.define do |a|
      a.name :research_agent
      a.description 'Agent that handles research tasks'
      a.instruction 'You are a specialized research agent'
      a.use_tool :echo
      a.fallback_mode :error
    end
  end

  # Define a proper calculator tool for testing
  let!(:calculator_tool) do
    # Define an anonymous class for the tool to keep it self-contained in the test
    Class.new(ADK::Tool) do
      # Set the explicit tool name directly, as `tool_name` DSL method does not take arguments
      self.explicit_tool_name = :calculator
      tool_description 'Performs calculations'
      parameter :expression, type: :string, description: 'The math expression to evaluate'

      # The main execution method for the tool
      def perform_execution(params, _context)
        # Using `eval` is generally unsafe, but acceptable here in a controlled test environment
        # where we provide the input.
        result = eval(params[:expression])
        { status: :success, result: result }
      rescue StandardError => e
        # Return a structured error if the calculation fails
        { status: :error, error_message: "Calculation error: #{e.message}" }
      end
    end
  end

  # Register built-in tools that are used in the tests
  let!(:echo_tool) { ADK::Tools::Echo }

  before(:each) do
    # Reset tool manager to ensure a clean slate for each test
    ADK::GlobalToolManager.reset!
    ADK::GlobalToolManager.register_tool(calculator_tool)
    ADK::GlobalToolManager.register_tool(echo_tool)

    # Register agent definitions globally
    allow(ADK::GlobalDefinitionRegistry).to receive(:find).with(:coordinator_agent).and_return(coordinator_definition)
    allow(ADK::GlobalDefinitionRegistry).to receive(:find).with(:calculator_agent).and_return(calculator_definition)
    allow(ADK::GlobalDefinitionRegistry).to receive(:find).with(:research_agent).and_return(research_definition)

    # Mock planner to prevent HTTP requests
    mock_planner = instance_double(ADK::Planner)
    allow(mock_planner).to receive(:plan).and_return(
      {
        thought_process: "Processing calculation",
        steps: [
          { tool: :calculator, params: { expression: "6 * 7" } }
        ]
      }
    )
    allow_any_instance_of(ADK::Agent).to receive(:planner).and_return(mock_planner)

    # Allow ADK::Agent.new with any arguments first (for the first coordinator and known agents)
    # IMPORTANT: This broad stub must come BEFORE more specific stubs
    allow(ADK::Agent).to receive(:new).and_call_original
  end

  context "with hierarchical agent structure" do
    let(:coordinator_agent) do
      agent = ADK::Agent.new(definition: coordinator_definition, session_service: mock_session_service)
      allow(agent).to receive(:running?).and_return(true)
      agent
    end

    let(:calculator_agent) do
      agent = ADK::Agent.new(definition: calculator_definition, session_service: mock_session_service)
      allow(agent).to receive(:running?).and_return(true)
      agent
    end

    let(:research_agent) do
      agent = ADK::Agent.new(definition: research_definition, session_service: mock_session_service)
      allow(agent).to receive(:running?).and_return(true)
      agent
    end

    before do
      # Set up parent-child relationships
      calculator_agent.instance_variable_set(:@parent_agent, coordinator_agent)
      research_agent.instance_variable_set(:@parent_agent, coordinator_agent)
      coordinator_agent.instance_variable_set(:@sub_agents, [calculator_agent, research_agent])
    end

    describe "delegation via agent hierarchy" do
      it "can find and delegate to calculator agent" do
        expect(coordinator_agent.find_agent(:calculator_agent)).to eq(calculator_agent)

        # Mock the calculator agent's run_task method
        allow(calculator_agent).to receive(:run_task).and_return(
          ADK::Event.new(role: :agent, content: { result: 42 })
        )

        # Execute delegation
        result = coordinator_agent.transfer_to(
          :calculator_agent,
          "Calculate 6 * 7",
          'test-session-123',
          mock_session_service
        )

        expect(result[:status]).to eq(:success)
        expect(result[:result]).to eq({ result: 42 })
      end

      it "prevents delegation to agents not in delegation_targets" do
        # Add a new agent not in delegation targets
        new_agent_definition = ADK::AgentDefinition.new.define do |a|
          a.name :unauthorized_agent
          a.description 'Agent not in delegation targets'
          a.instruction 'You should not be called'
        end

        new_agent = ADK::Agent.new(definition: new_agent_definition, session_service: mock_session_service)
        new_agent.instance_variable_set(:@parent_agent, coordinator_agent)

        # Update sub-agents list but don't add to delegation targets
        coordinator_agent.instance_variable_set(:@sub_agents,
                                                coordinator_agent.instance_variable_get(:@sub_agents) + [new_agent])

        # Try to delegate
        result = coordinator_agent.transfer_to(
          :unauthorized_agent,
          "Do something",
          'test-session-123',
          mock_session_service
        )

        expect(result[:status]).to eq(:error)
        expect(result[:error_class]).to eq('InvalidDelegationTarget')
      end
    end
  end

  context "with direct delegation using transfer_to" do
    let(:coordinator_agent) do
      agent = ADK::Agent.new(definition: coordinator_definition, session_service: mock_session_service)
      allow(agent).to receive(:running?).and_return(true)
      agent
    end

    let(:calculator_agent) do
      agent = ADK::Agent.new(definition: calculator_definition, session_service: mock_session_service)
      allow(agent).to receive(:running?).and_return(true)
      agent
    end

    before do
      # No parent-child relationship - test direct delegation

      # Stub calculator agent to return a predefined result
      allow(calculator_agent).to receive(:run_task).and_return(
        ADK::Event.new(role: :agent, content: { result: 42 })
      )

      # Register calculator_agent directly in the registry
      allow(ADK::GlobalDefinitionRegistry).to receive(:find).with(:calculator_agent).and_return(calculator_definition)

      # Create a mock calculator agent for when a new one gets instantiated
      mock_calculator_agent = instance_double(ADK::Agent, name: :calculator_agent, running?: false)
      allow(mock_calculator_agent).to receive(:start)
      allow(mock_calculator_agent).to receive(:run_task).and_return(
        ADK::Event.new(role: :agent, content: { result: 42 })
      )

      # Add a specific stub AFTER the general stub
      allow(ADK::Agent).to receive(:new).with(
        hash_including(definition: calculator_definition)
      ).and_return(mock_calculator_agent)
    end

    it "creates a new agent instance for the target if not in hierarchy" do
      # Remove any existing relationship
      coordinator_agent.instance_variable_set(:@sub_agents, [])

      # The target agent should not be found in the hierarchy
      expect(coordinator_agent.find_agent(:calculator_agent)).to be_nil

      # Execute delegation
      result = coordinator_agent.transfer_to(
        :calculator_agent,
        "Calculate 6 * 7",
        'test-session-123',
        mock_session_service
      )

      expect(result[:status]).to eq(:success)
      expect(result[:result]).to eq({ result: 42 })
    end

    it "maintains session continuity during delegation" do
      # Set up session state
      allow(mock_session).to receive(:get_state).with(:previous_calculation).and_return(10)

      # Create a mock calculator agent that uses session state
      session_aware_calculator = instance_double(ADK::Agent, name: :calculator_agent, running?: false)
      allow(session_aware_calculator).to receive(:start)
      allow(session_aware_calculator).to receive(:run_task) do |args|
        # Check if session state is accessible
        session = mock_session_service.get_session(session_id: args[:session_id])
        prev_value = session.get_state(:previous_calculation)

        # Return an event that incorporates the session state
        ADK::Event.new(
          role: :agent,
          content: {
            result: 52, # 42 + previous value of 10
            used_previous_value: prev_value
          }
        )
      end

      # Override the previous stub with one specific to this test
      allow(ADK::Agent).to receive(:new).with(
        hash_including(definition: calculator_definition)
      ).and_return(session_aware_calculator)

      # Execute delegation
      result = coordinator_agent.transfer_to(
        :calculator_agent,
        "Add 42 to previous calculation",
        'test-session-123',
        mock_session_service
      )

      expect(result[:status]).to eq(:success)
      expect(result[:result][:result]).to eq(52) # 42 + 10
      expect(result[:result][:used_previous_value]).to eq(10)
    end
  end

  context "with execute_step processing agent_transfer_to tools" do
    let(:coordinator_agent) do
      agent = ADK::Agent.new(definition: coordinator_definition, session_service: mock_session_service)
      allow(agent).to receive(:running?).and_return(true)
      agent
    end

    before do
      # Mock calculator agent creation and execution
      calc_agent = instance_double(ADK::Agent, name: :calculator_agent, running?: false)
      allow(calc_agent).to receive(:start)
      allow(calc_agent).to receive(:run_task).and_return(
        ADK::Event.new(role: :agent, content: { result: 42 })
      )

      # Add a specific stub AFTER the general stub
      allow(ADK::Agent).to receive(:new).with(
        hash_including(definition: calculator_definition)
      ).and_return(calc_agent)
    end

    it "handles agent_transfer_to_ tools by calling transfer_to" do
      step = {
        tool: :'agent_transfer_to_calculator_agent',
        params: { task: "Calculate 6 * 7" }
      }

      # Expect transfer_to to be called
      expect(coordinator_agent).to receive(:transfer_to).with(
        :calculator_agent,
        "Calculate 6 * 7",
        'test-session-123',
        mock_session_service
      ).and_return({ status: :success, target_agent: 'calculator_agent', result: { result: 42 } })

      # Execute step
      result = coordinator_agent.public_execute_step(step, mock_session, mock_session_service)

      expect(result[:status]).to eq(:success)
      expect(result[:result]).to eq({ result: 42 })
    end
  end
end
