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
  tool_description 'A tool without an explicit name.'

  def self.tool_metadata
    { name: nil, description: 'A tool without an explicit name.' }
  end

  def self.inferred_name
    nil
  end
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
    raise ADK::ToolError.new("Tool failed as requested: #{params[:fail_message]}")
  end
end

class MockToolWithArgError < ADK::Tool
  tool_description 'A tool that raises argument errors.'
  self.explicit_tool_name = :arg_error_tool
  parameter :number, type: :integer, required: true

  def perform_execution(params, context)
    raise ADK::ToolArgumentError, 'Invalid number provided' unless params[:number] > 0

    { status: :success, result: params[:number] }
  end
end

class MockToolInvalidResult < ADK::Tool
  tool_description 'A tool that returns invalid hash.'
  self.explicit_tool_name = :invalid_result_tool

  def perform_execution(params, context)
    'not a hash'
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
  let(:model_name) { 'test_model' } # Used as a potential value for definition
  let(:instruction) { 'You are a helpful test agent.' }
  # Default tool_classes used by `create_agent` if :tool_names_array is not specified.
  let(:tool_classes) { [MockTool, MockAnotherTool] }
  let(:planner_double) { instance_double(ADK::Planner, plan: []) }
  let(:session_service_double) {
    instance_double(ADK::SessionService::InMemory, get_session: session_double, append_event: true)
  }
  let(:fake_history) { [] }
  let(:session_double) do
    # Create a hash to simulate state storage within the double
    session_state_store = {}

    instance_double(ADK::Session, id: session_id, user_id: 'user1', app_name: 'app1').tap do |double|
      allow(double).to receive(:events).and_return(fake_history)
      allow(double).to receive(:add_event) { |event| fake_history << event }
      # Implement set_state and get_state using the local hash
      allow(double).to receive(:set_state) do |key, value|
        session_state_store[key] = value
      end
      allow(double).to receive(:get_state) do |key|
        session_state_store[key]
      end
    end
  end
  let(:session_id) { "test_session_#{rand(1000)}" }
  let(:user_input) { 'Test user input' }
  let(:logger_double) { spy('Logger') }

  # Mock definition used for tests focusing on behavior with a pre-existing definition object.
  let(:mock_definition) do
    instance_double(ADK::AgentDefinition,
                    name: agent_name,
                    description: agent_description,
                    instruction: instruction,
                    model_name: model_name, # Explicitly use let variable
                    tool_names: %i[mock_tool another_tool].to_set, # Fixed set for stability
                    fallback_mode: :error,
                    mcp_servers: [],
                    webhook_enabled: false,
                    webhook_validator: nil,
                    webhook_secret: nil,
                    webhook_transformer: nil,
                    webhook_session_extractor: nil,
                    sub_agent_names: Set.new, # Allow and provide default
                    output_key: nil, # Allow and provide default
                    # Add callback methods
                    before_agent_callback: nil,
                    after_agent_callback: nil,
                    before_model_callback: nil,
                    after_model_callback: nil,
                    before_tool_callback: nil,
                    after_tool_callback: nil,
                    # Add authentication config methods
                    auth_credential_names: Set.new,
                    auth_url_mappings: [],
                    auth_scheme_assignments: {},
                    auth_credential_assignments: {})
  end
  let(:mock_store) { instance_double(ADK::DefinitionStore::RedisStore, save_definition: true, get_definition: nil) }
  let(:mock_config) {
    instance_double(ADK::Configuration, definition_store: mock_store, session_service: session_service_double)
  }
  let(:mock_tool_manager) {
    class_double(ADK::GlobalToolManager, find_class: nil, registered_tool_names: [], reset!: true,
                                         register_tool: true).as_stubbed_const
  }

  # Helper to create agent instance for tests by dynamically building an AgentDefinition
  def create_agent(**options)
    def_name = options.delete(:name) || agent_name
    def_desc = options.delete(:description) || agent_description
    def_instr = options.delete(:instruction) || instruction
    def_model_name = options.delete(:model_name) # Allow nil, AgentDefinition will use its default
    # Defaults to tool names from the `tool_classes` let variable if not specified.
    def_tool_names = options.delete(:tool_names_array) || tool_classes.map { |tc| tc.tool_metadata[:name].to_sym rescue nil }.compact

    ephemeral_definition = ADK::AgentDefinition.new
    ephemeral_definition.define do |p|
      p.name def_name
      p.description def_desc
      p.instruction def_instr
      p.model_name def_model_name if def_model_name # Only set if provided
      def_tool_names.each { |tn| p.use_tool tn }
      p.fallback_mode options.delete(:fallback_mode) || :error
      p.mcp_servers(*(options.delete(:mcp_servers) || []))
    end

    # Stub GlobalToolManager for the tools in this ephemeral definition
    def_tool_names.each do |tn|
      # Attempt to find the class in a predefined list or the `tool_classes` let variable
      tool_class_to_find = case tn
                           when :mock_tool then MockTool
                           when :another_tool then MockAnotherTool
                           when :context_tool then MockToolNeedsContext
                           when :pending_tool then MockToolWithPending
                           when :error_tool then MockToolWithError
                           when :arg_error_tool then MockToolWithArgError
                           when :invalid_result_tool then MockToolInvalidResult
                           when :prep_error_tool then MockToolPreparationError
                           when :mock_tool_no_name then MockToolNoName
                           when :echo then ADK::Tools::Echo
                           when :calculator then ADK::Tools::Calculator
                           when :check_job_status then ADK::Tools::CheckJobStatusTool
                           # Find from the `tool_classes` let variable if it's a custom tool for a specific test context
                           else tool_classes.find { |tc_let| (tc_let.tool_metadata[:name].to_sym rescue nil) == tn }
                           end
      allow(mock_tool_manager).to receive(:find_class).with(tn).and_return(tool_class_to_find)
    end

    session_svc = options.delete(:session_service) || session_service_double
    planner_svc = options.delete(:planner_override) || planner_double

    ADK::Agent.new(
      definition: ephemeral_definition,
      session_service: session_svc,
      planner_override: planner_svc
    )
  end

  # Helper to create agent instance from a pre-existing definition object (like mock_definition)
  def create_agent_from_definition(def_double = mock_definition, **overrides)
    allow(def_double).to receive(:is_a?).with(ADK::AgentDefinition).and_return(true)
    # Ensure it responds to necessary methods if it's a pure double used in tests
    %i[name description instruction tool_names model_name fallback_mode mcp_servers sub_agent_names output_key webhook_enabled webhook_validator webhook_secret webhook_transformer webhook_session_extractor].each do |method|
      allow(def_double).to receive(:respond_to?).with(method).and_return(true)
    end

    planner_svc = overrides.key?(:planner_override) ? overrides.delete(:planner_override) : planner_double

    ADK::Agent.new(
      definition: def_double,
      session_service: overrides.delete(:session_service) || session_service_double,
      planner_override: planner_svc
      # Any remaining overrides are ignored by ADK::Agent.new unless they are valid params for it
    )
  end

  before do
    allow(ADK).to receive(:logger).and_return(logger_double)
    allow(ADK).to receive(:config).and_return(mock_config)
    allow(mock_tool_manager).to receive(:find_class).with(:mock_tool).and_return(MockTool)
    allow(mock_tool_manager).to receive(:find_class).with(:another_tool).and_return(MockAnotherTool)
    allow(mock_tool_manager).to receive(:find_class).with(:context_tool).and_return(MockToolNeedsContext)
    allow(mock_tool_manager).to receive(:find_class).with(:echo).and_return(ADK::Tools::Echo)
    allow(mock_tool_manager).to receive(:find_class).with(:calculator).and_return(ADK::Tools::Calculator)
    allow(mock_tool_manager).to receive(:find_class).with(:pending_tool).and_return(MockToolWithPending)
    allow(mock_tool_manager).to receive(:find_class).with(:check_job_status).and_return(ADK::Tools::CheckJobStatusTool)
    allow(mock_tool_manager).to receive(:find_class).with(:error_tool).and_return(MockToolWithError)
    allow(mock_tool_manager).to receive(:find_class).with(:arg_error_tool).and_return(MockToolWithArgError)
    allow(mock_tool_manager).to receive(:find_class).with(:invalid_result_tool).and_return(MockToolInvalidResult)
    allow(mock_tool_manager).to receive(:find_class).with(:prep_error_tool).and_return(MockToolPreparationError)
    allow(mock_tool_manager).to receive(:find_class).with(:mock_tool_no_name).and_return(MockToolNoName)

    allow(mock_tool_manager).to receive(:registered_tool_names).and_return(%i[mock_tool another_tool echo calculator])
  end

  describe '#initialize with definition:' do
    it 'sets attributes from the definition object' do
      agent = create_agent_from_definition(mock_definition)
      expect(agent.name).to eq(agent_name)
      expect(agent.description).to eq(agent_description)
      expect(agent.instruction).to eq(instruction)
      expect(agent.model_name).to eq(model_name) # model_name is set on mock_definition
      expect(agent.definition).to eq(mock_definition)
    end

    it 'uses definition model_name if set, otherwise agent default' do
      # Test with model_name explicitly set in definition
      allow(mock_definition).to receive(:model_name).and_return('specific-model-for-def')
      agent1 = create_agent_from_definition(mock_definition)
      expect(agent1.model_name).to eq('specific-model-for-def')

      # Test with model_name being nil in definition (should use Agent::DEFAULT_MODEL)
      allow(mock_definition).to receive(:model_name).and_return(nil)
      agent2 = create_agent_from_definition(mock_definition)
      expect(agent2.model_name).to eq(ADK::Agent::DEFAULT_MODEL)
    end

    it 'registers tools specified in the definition' do
      agent = create_agent_from_definition(mock_definition) # mock_definition has :mock_tool, :another_tool
      expect(agent.find_tool_class(:mock_tool)).to eq(MockTool)
      expect(agent.find_tool_class(:another_tool)).to eq(MockAnotherTool)
    end

    it 'uses provided session_service if passed' do
      custom_service = instance_double(ADK::SessionService::Base)
      allow(custom_service).to receive(:respond_to?).with(:get_session).and_return(true)
      allow(custom_service).to receive(:respond_to?).with(:append_event).and_return(true)

      agent = create_agent_from_definition(mock_definition, session_service: custom_service)
      expect(agent.instance_variable_get(:@session_service)).to eq(custom_service)
    end

    it 'uses default session_service if not passed via definition helper' do
      agent = create_agent_from_definition(mock_definition)
      expect(agent.instance_variable_get(:@session_service)).to eq(session_service_double)
    end

    it 'warns if a tool class from definition is not found globally' do
      allow(mock_definition).to receive(:tool_names).and_return(%i[mock_tool missing_tool])
      allow(mock_tool_manager).to receive(:find_class).with(:missing_tool).and_return(nil) # Ensure it's not found
      # mock_tool is still found via general before block setup

      create_agent_from_definition(mock_definition)
      expect(logger_double).to have_received(:warn).with(/Could not find globally registered classes for tools: missing_tool/)
    end

    it 'raises ArgumentError if definition is not an ADK::AgentDefinition' do
      expect {
        ADK::Agent.new(definition: {}, session_service: session_service_double)
      }.to raise_error(ArgumentError, /must be initialized with an ADK::AgentDefinition object/)
    end

    it 'raises ArgumentError if definition object is missing required methods' do
      incomplete_definition = instance_double(ADK::AgentDefinition)
      allow(incomplete_definition).to receive(:is_a?).with(ADK::AgentDefinition).and_return(true)
      # Missing :name for example
      allow(incomplete_definition).to receive(:respond_to?).with(:name).and_return(false)
      allow(incomplete_definition).to receive(:respond_to?).with(:description).and_return(true)
      allow(incomplete_definition).to receive(:respond_to?).with(:instruction).and_return(true)
      allow(incomplete_definition).to receive(:respond_to?).with(:tool_names).and_return(true)
      allow(incomplete_definition).to receive(:respond_to?).with(:model_name).and_return(true)
      allow(incomplete_definition).to receive(:respond_to?).with(:fallback_mode).and_return(true)
      allow(incomplete_definition).to receive(:respond_to?).with(:mcp_servers).and_return(true)

      expect {
        ADK::Agent.new(definition: incomplete_definition, session_service: session_service_double)
      }.to raise_error(ArgumentError, /Provided definition object does not appear to be a valid ADK::AgentDefinition/)
    end

    it 'uses planner_override if provided' do
      custom_planner = instance_double(ADK::Planner)
      allow(custom_planner).to receive(:respond_to?).with(:plan).and_return(true)
      agent = create_agent_from_definition(mock_definition, planner_override: custom_planner)
      expect(agent.planner).to eq(custom_planner)
    end

    it 'creates a default planner if no override is provided' do
      # Ensure planner_override is nil so the agent creates its own default planner
      agent = create_agent_from_definition(mock_definition, planner_override: nil)
      expect(agent.planner).to be_an_instance_of(ADK::Planner)
      expect(agent.planner.instance_variable_get(:@model_name)).to eq(mock_definition.model_name)
    end

    it 'correctly initializes fallback_mode from definition' do
      allow(mock_definition).to receive(:fallback_mode).and_return(:echo)
      agent = create_agent_from_definition(mock_definition)
      expect(agent.fallback_mode).to eq(:echo)
    end

    it 'correctly initializes mcp_servers from definition' do
      mcp_config = [{ host: 'localhost', port: 1234 }]
      allow(mock_definition).to receive(:mcp_servers).and_return(mcp_config)
      agent = create_agent_from_definition(mock_definition)
      expect(agent.instance_variable_get(:@mcp_servers_config)).to eq(mcp_config)
    end

    context 'with sub-agent instantiation' do
      let(:child_agent_name) { :child_one }
      let(:child_instruction) { 'I am child one.' }
      let(:child_definition) do
        # Capture let variables for the define block
        name_val = child_agent_name
        instruction_val = child_instruction
        ADK::AgentDefinition.new.define do |d|
          d.name name_val
          d.instruction instruction_val
        end
      end
      let(:another_child_agent_name) { :child_two }
      let(:another_child_instruction) { 'I am child two.' }
      let(:another_child_definition) do
        # Capture let variables for the define block
        name_val = another_child_agent_name
        instruction_val = another_child_instruction
        ADK::AgentDefinition.new.define do |d|
          d.name name_val
          d.instruction instruction_val
        end
      end

      let(:parent_definition_declaring_subs) do
        # Capture let variables for the define block
        sub_name_val = child_agent_name
        ADK::AgentDefinition.new.define do |d|
          d.name :parent_with_declared_subs
          d.instruction 'I declare subs.'
          d.sub_agents_define sub_name_val # Declare :child_one
        end
      end

      before do
        # Ensure child definitions are in the GlobalDefinitionRegistry for declarative instantiation tests
        # Stub the class method directly on ADK::GlobalDefinitionRegistry
        allow(ADK::GlobalDefinitionRegistry).to receive(:get).with(child_agent_name).and_return(child_definition)
        allow(ADK::GlobalDefinitionRegistry).to receive(:get).with(another_child_agent_name).and_return(another_child_definition)
        allow(ADK::GlobalDefinitionRegistry).to receive(:register) # Allow register to be called
      end

      context 'when sub_agents parameter is provided (programmatic override)' do
        let(:programmatic_child_instance) { ADK::Agent.new(definition: another_child_definition, session_service: session_service_double) }
        let(:parent_agent) do
          ADK::Agent.new(
            definition: parent_definition_declaring_subs, # This definition *declares* :child_one
            session_service: session_service_double,
            sub_agents: [programmatic_child_instance] # But we provide :child_two programmatically
          )
        end

        it 'uses the programmatically provided sub-agents' do
          expect(parent_agent.sub_agents.count).to eq(1)
          expect(parent_agent.sub_agents.first.name).to eq(another_child_agent_name) # child_two
        end

        it 'sets the parent_agent link on the programmatic sub-agent' do
          expect(parent_agent.sub_agents.first.parent_agent).to eq(parent_agent)
        end

        it 'does not instantiate sub-agents from the definitions sub_agent_names' do
          # Verified by checking that :child_one (from parent_definition_declaring_subs) is not instantiated
          expect(parent_agent.sub_agents.map(&:name)).not_to include(child_agent_name)
        end

        it 'assigns parent session service to programmatic sub-agent if sub-agent lacks one' do
          child_without_service_def = ADK::AgentDefinition.new.define { |d| d.name :child_no_svc; d.instruction 'hi' }
          programmatic_child_no_service = ADK::Agent.new(definition: child_without_service_def)

          # Force nil session service after initialization
          programmatic_child_no_service.instance_variable_set(:@session_service, nil)
          # Verify it's nil after our modification
          expect(programmatic_child_no_service.instance_variable_get(:@session_service)).to be_nil

          parent_with_child_no_service = ADK::Agent.new(
            definition: parent_definition_declaring_subs,
            session_service: session_service_double,
            sub_agents: [programmatic_child_no_service]
          )
          # Now expect the child agent's session service to be the parent's session service
          expect(parent_with_child_no_service.sub_agents.first.instance_variable_get(:@session_service)).to eq(session_service_double)
        end

        it 'warns if programmatic sub-agent has a different session service' do
          different_session_service = instance_double(ADK::SessionService::InMemory, get_session: nil, append_event: nil)
          child_with_diff_service_def = ADK::AgentDefinition.new.define { |d| d.name :child_diff_svc; d.instruction 'hi' }
          programmatic_child_diff_service = ADK::Agent.new(definition: child_with_diff_service_def, session_service: different_session_service)

          expect(logger_double).to receive(:warn).with(/Programmatic sub-agent 'child_diff_svc' has a different session_service than parent/)
          ADK::Agent.new(
            definition: parent_definition_declaring_subs,
            session_service: session_service_double, # Parent's service
            sub_agents: [programmatic_child_diff_service]
          )
        end

        context 'single parent rule enforcement for programmatic sub-agents' do
          let!(:rogue_parent_definition) { ADK::AgentDefinition.new.define { |d| d.name :rogue_parent; d.instruction 'rogue' } }
          let!(:rogue_parent) { ADK::Agent.new(definition: rogue_parent_definition, session_service: session_service_double) }
          let!(:child_with_rogue_parent_def) { ADK::AgentDefinition.new.define { |d| d.name :child_with_parent; d.instruction 'already parented' } }
          let!(:child_with_rogue_parent) do
            # Programmatically create child and assign rogue_parent
            child = ADK::Agent.new(definition: child_with_rogue_parent_def, session_service: session_service_double)
            child.instance_variable_set(:@parent_agent, rogue_parent) # Manually set a different parent
            child
          end

          it 'logs an error and does not adopt a sub-agent that already has a different parent' do
            expect(logger_double).to receive(:error).with(/Cannot adopt sub-agent 'child_with_parent'. It already has a different parent: 'rogue_parent'/)

            parent_trying_to_adopt = ADK::Agent.new(
              definition: parent_definition_declaring_subs, # Does not matter what this declares for this test
              session_service: session_service_double,
              sub_agents: [child_with_rogue_parent]
            )
            expect(parent_trying_to_adopt.sub_agents).to be_empty
            expect(child_with_rogue_parent.parent_agent).to eq(rogue_parent) # Should retain original parent
          end

          it 'handles a sub-agent appearing multiple times in programmatic list (idempotent parenting to self)' do
            # child_one_def is :child_one definition, use it to create a fresh instance for parenting
            child_instance_for_parenting = ADK::Agent.new(definition: child_definition, session_service: session_service_double)

            parent_with_duplicate_sub = ADK::Agent.new(
              definition: parent_definition_declaring_subs,
              session_service: session_service_double,
              sub_agents: [child_instance_for_parenting, child_instance_for_parenting] # Same instance twice
            )
            # Should only be added once (standard Array#<< behavior might add twice, but @sub_agents should be robust)
            # The current logic will attempt to parent it twice. The second time, sub_agent.parent_agent == self, so it proceeds.
            # If @sub_agents is an array, it will be added twice. If it's a Set, once.
            # Let's assume @sub_agents = [] means it will be added twice if not made unique.
            # For now, test that parent link is correct and it exists at least once.
            # To be more robust, @sub_agents should probably be a Set or made unique.
            # Current test: check parent is correct and count reflects one logical sub-agent if it were a Set.
            # However, with `sub_agents << sub_agent`, it *will* add duplicates to an array.
            # The single parent check `sub_agent.parent_agent != self` handles the error case.
            # The `sub_agent.parent_agent.nil?` sets it first time.
            # The implicit `elsif sub_agent.parent_agent == self` branch does nothing to parent link, and child is added again.

            expect(parent_with_duplicate_sub.sub_agents.count).to eq(2) # Because it's added to an array twice
            expect(parent_with_duplicate_sub.sub_agents.all? { |sa| sa.name == :child_one }).to be true
            expect(parent_with_duplicate_sub.sub_agents.all? { |sa| sa.parent_agent == parent_with_duplicate_sub }).to be true
            # No error should be logged for this case
            expect(logger_double).not_to have_received(:error).with(/Cannot adopt sub-agent/)
          end
        end
      end

      context 'when sub_agents parameter is NOT provided (declarative instantiation)' do
        let(:parent_agent) do
          ADK::Agent.new(
            definition: parent_definition_declaring_subs, # Declares :child_one
            session_service: session_service_double
            # No sub_agents: parameter, so should use definition
          )
        end

        it 'instantiates sub-agents based on definition.sub_agent_names' do
          expect(parent_agent.sub_agents.count).to eq(1)
          expect(parent_agent.sub_agents.first.name).to eq(child_agent_name) # :child_one
        end

        it 'sets the parent_agent link on declaratively instantiated sub-agents' do
          expect(parent_agent.sub_agents.first.parent_agent).to eq(parent_agent)
        end

        it 'passes its session_service to declaratively instantiated sub-agents' do
          expect(parent_agent.sub_agents.first.session_service).to eq(session_service_double)
        end

        it 'logs an error and skips if a declared sub-agent definition is not found in registry' do
          allow(ADK::GlobalDefinitionRegistry).to receive(:get).with(child_agent_name).and_return(nil) # Simulate missing definition
          expect(logger_double).to receive(:error).with(/Could not find definition for sub-agent 'child_one'/)
          parent_with_missing_sub_def = ADK::Agent.new(definition: parent_definition_declaring_subs, session_service: session_service_double)
          expect(parent_with_missing_sub_def.sub_agents).to be_empty
        end
      end

      context 'when definition has no sub_agent_names and no sub_agents parameter' do
        let(:parent_definition_no_subs) do
          ADK::AgentDefinition.new.define do |d|
            d.name :parent_no_subs
            d.instruction 'I have no subs.'
            # No sub_agents_define call
          end
        end
        let(:parent_agent) { ADK::Agent.new(definition: parent_definition_no_subs, session_service: session_service_double) }

        it 'initializes with an empty sub_agents list' do
          expect(parent_agent.sub_agents).to be_empty
        end
      end

      context 'when definition is loaded from a store hash (simulating persistence)' do
        let(:child_b_name) { :child_b }
        let(:child_b_definition_obj) do # The actual object
          # Capture let variables for the define block
          name_val = child_b_name
          ADK::AgentDefinition.new.define do |d|
            d.name name_val
            d.instruction 'I am Child B.'
          end
        end

        let(:parent_a_name) { :parent_a }
        let(:parent_a_definition_hash_from_store) do # Simulates what store would return
          {
            name: parent_a_name.to_s, # Store might use strings for names
            description: 'Parent A loaded from store',
            instruction: 'I am Parent A, I have Child B.',
            tool_names: [],
            model_name: nil,
            fallback_mode: 'error',
            mcp_servers: [],
            sub_agent_names: [child_b_name.to_s] # Store might use strings for sub_agent_names too
          }
        end

        let(:loaded_parent_a_definition_obj) do
          ADK::AgentDefinition.from_hash(parent_a_definition_hash_from_store)
        end

        before do
          # Ensure ChildB's full definition object is in the GlobalDefinitionRegistry
          # This is what ADK::Agent#initialize will use to instantiate ChildB
          # Stub the class method directly on ADK::GlobalDefinitionRegistry
          allow(ADK::GlobalDefinitionRegistry).to receive(:get).with(child_b_name).and_return(child_b_definition_obj)

          # Verify that from_hash worked as expected (especially sub_agent_names)
          expect(loaded_parent_a_definition_obj.name).to eq(parent_a_name)
          expect(loaded_parent_a_definition_obj.sub_agent_names).to contain_exactly(child_b_name)
        end

        let(:parent_agent_from_loaded_def) do
          ADK::Agent.new(
            definition: loaded_parent_a_definition_obj,
            session_service: session_service_double
          )
        end

        it 'successfully instantiates ParentA' do
          expect(parent_agent_from_loaded_def.name).to eq(parent_a_name)
        end

        it 'instantiates ChildB as a sub-agent' do
          expect(parent_agent_from_loaded_def.sub_agents.count).to eq(1)
          sub_agent = parent_agent_from_loaded_def.sub_agents.first
          expect(sub_agent.name).to eq(child_b_name)
          expect(sub_agent.instruction).to eq('I am Child B.')
        end

        it 'sets the parent_agent link on ChildB' do
          sub_agent = parent_agent_from_loaded_def.sub_agents.first
          expect(sub_agent.parent_agent).to eq(parent_agent_from_loaded_def)
        end

        it 'passes its session_service to ChildB' do
          sub_agent = parent_agent_from_loaded_def.sub_agents.first
          expect(sub_agent.session_service).to eq(session_service_double)
        end
      end
    end
  end

  # The block 'describe "#initialize with keyword args"' has been removed as it is no longer applicable
  # after ADK::Agent#initialize was refactored to require a definition object for initialization.

  # --- Tool Management Tests ---
  describe 'Tool Management' do
    # `create_agent` by default uses `tool_classes` which are MockTool and MockAnotherTool
    # These will be in the definition of the agent created by `create_agent`.
    subject(:agent) { create_agent() }

    describe '#add_tool' do
      let(:new_tool_class) { ADK::Tools::Calculator }
      let(:new_tool_name) { :calculator }
      let(:new_tool_instance) { new_tool_class.new }

      it 'adds a valid tool class to the agent specific registry' do
        expect(agent.add_tool(new_tool_class)).to be true
        expect(agent.find_tool_class(new_tool_name)).to eq(new_tool_class)
        expect(logger_double).to have_received(:debug).with(/Agent '#{agent_name}' add_tool: Registering tool_name=:#{new_tool_name}/)
      end

      it 'adds a valid tool instance' do
        expect(agent.add_tool(new_tool_instance)).to be true
        expect(agent.find_tool_class(new_tool_name)).to eq(new_tool_class)
      end

      it 'warns and overwrites when adding a duplicate tool' do
        agent.add_tool(new_tool_class)
        expect(logger_double).to receive(:warn).with(/ToolRegistry: Tool '#{new_tool_name}' is already registered/).at_least(:once)
        expect(agent.add_tool(new_tool_class)).to be true
      end

      it 'errors and does not add an invalid object' do
        invalid_object = Object.new
        expect(agent.add_tool(invalid_object)).to be false
        expect(logger_double).to have_received(:error).with("Agent '#{agent_name}' add_tool: Attempted to add invalid tool: #{invalid_object.inspect}")
      end

      it 'adds a tool using its inferred name if metadata name is missing' do
        allow(MockToolNoName).to receive(:tool_metadata).and_return({ name: nil, description: 'Desc' })
        allow(MockToolNoName).to receive(:inferred_name).and_return(:mock_tool_no_name)
        expect(agent.add_tool(MockToolNoName)).to be true
        expect(agent.find_tool_class(:mock_tool_no_name)).to eq(MockToolNoName)
      end

      it 'logs error and does not add tool if name cannot be determined' do
        klass_no_name = Class.new(ADK::Tool) do
          tool_description 'Desc only'
          def self.tool_metadata; { name: nil, description: 'Desc only' }; end
          def self.inferred_name; nil; end
        end
        expect(agent.add_tool(klass_no_name)).to be false
        expect(logger_double).to have_received(:error).with(/Could not determine tool name for class.*Cannot add tool/)
      end
    end

    describe '#tools' do
      it 'returns an array of tool instances based on its definition' do
        # `create_agent` by default includes MockTool and MockAnotherTool
        # CheckJobStatusTool is auto-added if Sidekiq is defined
        agent_with_tools = create_agent(tool_names_array: [:mock_tool, :another_tool])
        tool_instances = agent_with_tools.tools
        expect(tool_instances).to be_an(Array)
        expected_classes = [MockTool, MockAnotherTool]
        expected_classes << ADK::Tools::CheckJobStatusTool if defined?(Sidekiq)
        expect(tool_instances.map(&:class)).to contain_exactly(*expected_classes)
      end

      it 'returns only auto-registered tools if definition has no tools' do
        agent_no_def_tools = create_agent(tool_names_array: []) # Ephemeral def has no tools
        expected_tools_if_sidekiq = defined?(Sidekiq) ? [an_instance_of(ADK::Tools::CheckJobStatusTool)] : []
        expect(agent_no_def_tools.tools).to match_array(expected_tools_if_sidekiq)
      end

      it 'skips tool instance creation and warns if name cannot be retrieved' do
        # Create a class specifically for this test that will change its metadata behavior
        test_tool_class = Class.new(ADK::Tool) do
          tool_description 'A test tool for name checking'

          # Keep track of call count to return different values
          class << self
            attr_accessor :call_count

            def reset_count
              @call_count = 0
            end

            def tool_metadata
              @call_count ||= 0
              @call_count += 1

              if @call_count <= 2
                # First calls during registration return valid name
                { name: :disappearing_tool, description: 'Tool that will lose its name' }
              else
                # Later calls during tools() return nil name
                { name: nil, description: 'Tool with no retrievable name' }
              end
            end

            def inferred_name
              @call_count ||= 0
              @call_count > 2 ? nil : :disappearing_tool
            end
          end
        end

        # Reset the counter before starting
        test_tool_class.reset_count

        # Create a registry and manually register our test tool
        registry = ADK::ToolRegistry.new
        registry.register(:disappearing_tool, test_tool_class)

        # Create an agent and replace its registry with our prepared one
        agent = create_agent(tool_names_array: [])
        agent.instance_variable_set(:@tool_registry, registry)

        # By this point the tool should be registered with a valid name
        expect(agent.find_tool_class(:disappearing_tool)).to eq(test_tool_class)

        # Set up the expectation for the warning
        expect(logger_double).to receive(:warn).with(/Skipping tool instance creation for class .* as its name could not be determined post-registration/)

        # Mock tool_name_from_class to return nil to simulate the test scenario
        allow(agent).to receive(:get_tool_name_from_class).with(test_tool_class).and_return(nil)

        # Call tools() which will trigger the name lookup again, but this time it will return nil
        tools = agent.tools
        expect(tools).to be_empty
      end
    end

    describe '#find_tool' do
      subject(:agent) { create_agent(tool_names_array: [:mock_tool]) }

      it 'returns the tool instance if found' do
        expect(agent.find_tool(:mock_tool)).to be_an_instance_of(MockTool)
      end

      it 'returns nil if the tool is not found' do
        expect(agent.find_tool(:non_existent_tool)).to be_nil
      end
    end

    describe '#available_tools_metadata' do
      it 'returns metadata list from the tool registry' do
        agent_with_tools = create_agent(tool_names_array: [:mock_tool, :another_tool])
        metadata = agent_with_tools.available_tools_metadata
        expect(metadata).to be_an(Array)
        tool_names_in_meta = metadata.map { |m| m[:name] }
        expect(tool_names_in_meta).to include(:mock_tool, :another_tool)
        expect(tool_names_in_meta).to include(:check_job_status) if defined?(Sidekiq)
      end

      it 'returns only auto-registered tools if definition has no tools' do
        agent_no_def_tools = create_agent(tool_names_array: [])
        metadata = agent_no_def_tools.available_tools_metadata
        expected_names = defined?(Sidekiq) ? [:check_job_status] : []
        expect(metadata.map { |m| m[:name] }).to match_array(expected_names)
      end
    end

    describe '#find_tool_class' do
      subject(:agent) { create_agent(tool_names_array: [:mock_tool]) }

      it 'returns the tool class if found' do
        expect(agent.find_tool_class(:mock_tool)).to eq(MockTool)
      end
    end

    describe '#register_tool_class (agent specific registry)' do
      subject(:agent) { create_agent(tool_names_array: []) } # Start with no tools from definition
      let(:new_tool_class) { ADK::Tools::Calculator }
      let(:new_tool_name) { :calculator }

      it 'registers a valid tool class to the agent instance' do
        expect(agent.register_tool_class(new_tool_class)).to be true
        expect(agent.find_tool_class(new_tool_name)).to eq(new_tool_class)
      end
    end
  end # End Tool Management

  # --- Runtime State ---
  describe '#start/#stop/#running?' do
    subject(:agent) { create_agent() }

    it 'starts the agent' do
      expect(agent.running?).to be false
      agent.start
      expect(agent.running?).to be true
      expect(logger_double).to have_received(:info).with("Agent '#{agent_name}' runtime started.")
    end

    it 'stops the agent' do
      agent.start
      agent.stop
      expect(agent.running?).to be false
      expect(logger_double).to have_received(:info).with("Agent '#{agent_name}' runtime stopped.")
    end
  end # End Runtime State

  # --- Run Task ---
  describe '#run_task' do
    let(:run_task_tool_names) { %i[mock_tool another_tool echo pending_tool check_job_status error_tool arg_error_tool invalid_result_tool prep_error_tool] }
    subject(:agent) {
      create_agent(
        tool_names_array: run_task_tool_names,
        session_service: ADK::SessionService::InMemory.new, # Use a real service for these tests
        planner_override: planner_double
      )
    }
    let(:real_session_service) { agent.instance_variable_get(:@session_service) }

    before do
      agent.start unless RSpec.current_example.metadata[:skip_agent_start]
      svc = agent.instance_variable_get(:@session_service)
      expect(svc).to be_an_instance_of(ADK::SessionService::InMemory)
      # Create a session for tests that need it
      # Allow `create_session` on the real service if it hasn't been called yet for this session_id
      # This helps avoid issues if `get_session` is called before `create_session` for `session_id`
      allow(svc).to receive(:create_session).with(app_name: 'app1', user_id: 'user1').and_return(session_double)
      allow(svc).to receive(:get_session).with(session_id: session_id).and_return(session_double)
      allow(svc).to receive(:get_session).with(session_id: 'non_existent_session').and_return(nil)
      allow(svc).to receive(:append_event).and_call_original
    end

    context 'pre-execution checks' do
      it 'returns error event if agent is not running', :skip_agent_start do
        expect(agent.running?).to be false
        result_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
        expect(result_event.content[:status]).to eq(:error)
        expect(result_event.content[:error_message]).to match(/runtime is not active/)
      end

      it 'returns error event if session not found' do
        result_event = agent.run_task(session_id: 'non_existent_session', user_input: user_input, session_service: real_session_service)
        expect(result_event.content[:status]).to eq(:error)
        expect(result_event.content[:error_message]).to match(/Session not found/)
      end
    end

    context 'successful single-step execution' do
      let(:plan) { [{ tool: :mock_tool, params: { input: 'step 1 data' } }] }
      before { allow(planner_double).to receive(:plan).and_return(plan) }

      it 'records user, tool request, tool result, and agent events' do
        agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
        history = session_double.events
        expect(history.map(&:role)).to eq(%i[user tool_request tool_result agent])
      end

      it 'returns the final agent event with the tool result' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
        expect(final_event.content).to include(status: :success, result: 'Mock tool processed: step 1 data')
      end
    end

    context 'successful multi-step execution with injection' do
      let(:plan) { [{ tool: :mock_tool, params: { input: 'data1' } }, { tool: :another_tool, params: { value: '[Result from previous step]' } }] }
      before { allow(planner_double).to receive(:plan).and_return(plan) }

      it 'injects result and returns result of the last step' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
        expect(final_event.content[:result]).to eq('Mock tool processed: data1' * 2)
      end
    end

    context 'when a step returns a pending status' do
      let(:plan) { [{ tool: :pending_tool, params: { job_request: 'long task' } }] }
      before { allow(planner_double).to receive(:plan).and_return(plan) }

      it 'returns final agent event with pending status' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
        expect(final_event.content[:status]).to eq(:pending)
        expect(final_event.content[:job_id]).to match(/job-\d+/)
      end
    end

    context 'multi-step execution with job_id injection' do
      let(:mock_job_id) { 'job-real-123' }
      let(:plan) { [{ tool: :pending_tool, params: { job_request: 'start' } }, { tool: :check_job_status, params: { job_id: '[Result from previous step]' } }] }
      before do
        allow(planner_double).to receive(:plan).and_return(plan)
        allow_any_instance_of(MockToolWithPending).to receive(:perform_execution).and_return({ status: :pending, job_id: mock_job_id, message: '...' })

        check_tool_instance = ADK::Tools::CheckJobStatusTool.new
        # Ensure the agent's tool registry will provide this instance when :check_job_status is looked up
        # Allow other calls to create_instance to proceed as normal (call original)
        allow(agent.tool_registry).to receive(:create_instance).and_call_original
        allow(agent.tool_registry).to receive(:create_instance).with(:check_job_status).and_return(check_tool_instance)

        allow(check_tool_instance).to receive(:execute).with({ job_id: mock_job_id }, anything)
                                                       .and_return({ status: :success, result: 'Job Done', job_status: 'completed' })
      end

      it 'injects job_id and returns result of check tool' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
        expect(final_event.content[:status]).to eq(:success)
        expect(final_event.content[:result]).to eq('Job Done')
        expect(final_event.content[:job_status]).to eq('completed')
      end
    end

    context 'multi-step execution with error and plan halting' do
      let(:plan) { [{ tool: :mock_tool, params: { input: 'good' } }, { tool: :error_tool, params: { fail_message: 'Boom' } }, { tool: :another_tool, params: { value: 1 } }] }
      before { allow(planner_double).to receive(:plan).and_return(plan) }

      it 'stops execution and returns error status' do
        final_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
        expect(final_event.content[:status]).to eq(:error)
        expect(final_event.content[:error_message]).to include('Boom')
        tool_result_events = session_double.events.select { |e| e.role == :tool_result }
        expect(tool_result_events.map { |e| e.tool_name }).not_to include(:another_tool)
      end
    end

    context 'delegation interception' do
      let(:plan) { [{ tool: :agent_transfer_to_calculator, params: { task: 'calc something' } }] }
      before { allow(planner_double).to receive(:plan).and_return(plan) }

      it 'maps agent_transfer_to_ tool to delegate_task' do
        # We need to mock the delegate_task tool (AgentTool) behavior
        # Since Agent#execute_step calls @tool_registry.create_instance(:delegate_task)
        # we need to ensure that returns our mock or spy.
        
        # But wait, create_agent doesn't register AgentTool by default in this test setup unless we add it.
        # Let's add :delegate_task to the tool list for this agent instance or mock the registry lookup.
        
        mock_agent_tool = instance_double(ADK::Tools::AgentTool)
        # Allow execute with any context
        allow(mock_agent_tool).to receive(:execute).and_return({ status: :success, result: 'delegated result' })
        
        # Stub the registry on the agent
        allow(agent.tool_registry).to receive(:create_instance).with(:delegate_task).and_return(mock_agent_tool)
        # Allow other tools to work normally if called (though they shouldn't be with this plan)
        allow(agent.tool_registry).to receive(:create_instance).with(any_args) do |name|
           next mock_agent_tool if name == :delegate_task
           nil # or real behavior if needed, but we only expect delegate_task here
        end

        expect(mock_agent_tool).to receive(:execute).with(
          hash_including(target_agent_name: 'calculator', task: 'calc something'),
          anything
        )
        
        result = agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
        expect(result.content[:result]).to eq('delegated result')
      end
    end

    context 'when plan is empty' do
      before { allow(planner_double).to receive(:plan).and_return([]) }

      context 'with fallback_mode :echo' do
        subject(:agent) {
          create_agent(
            tool_names_array: [:echo],
            fallback_mode: :echo,
            session_service: ADK::SessionService::InMemory.new,
            planner_override: planner_double
          )
        }

        it 'falls back to echo tool' do
          expect(logger_double).to receive(:warn).with(/Falling back to echo mode/)

          final_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)

          expect(final_event.content[:status]).to eq(:success)
          expect(final_event.content[:result]).to eq(user_input)
        end
      end

      context 'with fallback_mode :error (default)' do
        subject(:agent) {
          create_agent(
            tool_names_array: [:mock_tool],
            fallback_mode: :error,
            session_service: ADK::SessionService::InMemory.new,
            planner_override: planner_double
          )
        }

        it 'returns an error event' do
          expect(logger_double).to receive(:warn).with(/I cannot fulfill this request with the available tools/)

          final_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)

          # The agent returns a nested structure on error: { details: { status: :error, ... }, last_result: nil }
          expect(final_event.content[:details][:status]).to eq(:error)
          expect(final_event.content[:details][:error_message]).to match(/cannot fulfill this request/)
        end
      end
    end

    context 'with output_key state management' do
      let(:output_key_name) { :my_agent_output }
      let(:agent_with_output_key) do
        # Capture let variable for the define block
        key_name_val = output_key_name
        definition_with_key = ADK::AgentDefinition.new.define do |d|
          d.name :output_key_agent
          d.instruction 'I save my output.'
          d.use_tool :mock_tool
          d.output_key key_name_val # Set the output key
        end
        # Need to stub find_class for :mock_tool if create_agent helper isn't used or adapted
        allow(mock_tool_manager).to receive(:find_class).with(:mock_tool).and_return(MockTool)

        ADK::Agent.new(
          definition: definition_with_key,
          session_service: real_session_service, # Use the real InMemory service
          planner_override: planner_double
        )
      end

      let(:successful_plan) { [{ tool: :mock_tool, params: { input: 'save this' } }] }
      let(:expected_tool_result_content) { { status: :success, result: 'Mock tool processed: save this' } }

      before do
        allow(planner_double).to receive(:plan).and_return(successful_plan)
        # Ensure the InMemorySessionService will be used and responds to set_state
        # The `real_session_service` is already an InMemory instance.
        # We need to spy on its `set_state` method.
        allow(real_session_service).to receive(:set_state).and_call_original # Spy but allow execution
        agent_with_output_key.start # Start the agent
      end

      it 'calls session_service.set_state with output_key and result content when output_key is defined' do
        final_event = agent_with_output_key.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)

        # The final event content itself will be the value passed to set_state
        # It includes the tool result, plan details, etc.
        expected_value_for_set_state = final_event.content

        # Update to compare with hash values instead of exact match, which allows string or symbol keys
        expect(real_session_service).to have_received(:set_state) do |args|
          expect(args[:session_id]).to eq(session_id)
          expect(args[:key]).to eq(output_key_name)
          expect(args[:value]).to be_a(Hash)
          # Check specific keys that should be present in the value
          expect(args[:value]["result"] || args[:value][:result]).to eq("Mock tool processed: save this")
          expect(args[:value]["status"] || args[:value][:status]).to eq("success")
        end

        # Also check that the state was actually set in the session via InMemory service
        stored_value = real_session_service.get_state(session_id: session_id, key: output_key_name)
        # Compare content more flexibly, allowing for string or symbol keys
        expect(stored_value["result"] || stored_value[:result]).to eq(expected_value_for_set_state["result"] || expected_value_for_set_state[:result])
        # Convert both to strings to avoid symbol vs string comparison issues
        stored_status = stored_value["status"] || stored_value[:status]
        expected_status = expected_value_for_set_state["status"] || expected_value_for_set_state[:status]
        expect(stored_status.to_s).to eq(expected_status.to_s)
        # Verify plan_details exists but don't compare directly
        expect(stored_value["plan_details"] || stored_value[:plan_details]).to be_an(Array)
      end

      it 'does not call session_service.set_state if output_key is not defined' do
        definition_no_key = ADK::AgentDefinition.new.define do |d|
          d.name :no_output_key_agent
          d.instruction 'I do not save output.'
          d.use_tool :mock_tool
          # No output_key
        end
        allow(mock_tool_manager).to receive(:find_class).with(:mock_tool).and_return(MockTool)
        agent_no_output_key = ADK::Agent.new(definition: definition_no_key, session_service: real_session_service, planner_override: planner_double)
        agent_no_output_key.start

        agent_no_output_key.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
        expect(real_session_service).not_to have_received(:set_state)
      end

      it 'logs a warning if session_service does not respond to :set_state' do
        allow(real_session_service).to receive(:respond_to?).with(:set_state).and_return(false)
        # logger_double is already available
        expect(logger_double).to receive(:warn).with(/Session service does not support :set_state/)

        agent_with_output_key.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
        # Ensure it still doesn't try to call it if respond_to? is false
        expect(real_session_service).not_to have_received(:set_state)
      end

      it 'handles errors during set_state and logs them' do
        allow(real_session_service).to receive(:set_state).and_raise(StandardError, 'Failed to write to state store!')
        expect(logger_double).to receive(:error).with(/Failed to set state for key '#{output_key_name}'.*Failed to write to state store!/)

        # The task should still complete and return the final event
        final_event = agent_with_output_key.run_task(session_id: session_id, user_input: user_input, session_service: real_session_service)
        expect(final_event).to be_an(ADK::Event)
      end
    end
  end # End Run Task
end
