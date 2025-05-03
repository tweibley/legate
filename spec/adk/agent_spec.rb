# File: spec/adk/agent_spec.rb
require 'spec_helper'
require 'adk/agent'
require 'adk/tool' # For stubbing tool classes
require 'adk/planner' # For stubbing planner
require 'adk/session'
require 'adk/event'
require 'adk/session_service/in_memory'
require 'adk/mcp/client' # For MCP tests
require 'adk/mcp/tool_wrapper'
require 'adk/global_tool_manager' # For tool discovery tests
require 'adk/tool_registry' # For checking registry
require 'sidekiq/testing' # For testing async tool integration

# Define dummy tools globally for tests
class EchoTool < ADK::Tool; tool_description 'Echoes'; def perform_execution(params, context) {status: :success, result: params[:message]} end; end
class CalcTool < ADK::Tool; tool_description 'Calculates'; def perform_execution(params, context) {status: :success, result: 42} end; end
class AsyncTool < ADK::Tools::BaseAsyncJobTool; tool_description 'Async'; def sidekiq_worker_class; end; def prepare_job_arguments(params, ctx); []; end; end

RSpec.describe ADK::Agent do
  let(:agent_name) { 'test_agent' }
  let(:agent_desc) { 'Test Description' }
  let(:agent_instruction) { 'Be helpful.' }
  let(:model_name) { 'gemini-test' }
  let(:tool_registry_instance) { instance_double(ADK::ToolRegistry, register: true, tools: {}, list_tools: [], find_class: nil, create_instance: nil) }
  let(:planner_instance) { instance_double(ADK::Planner) }
  let(:session_service) { ADK::SessionService::InMemory.new }
  let(:session) { session_service.create_session(app_name: agent_name, user_id: 'test_user') }
  let(:context) { ADK::ToolContext.new(session_id: session.id, tool_registry: tool_registry_instance) } # Basic context

  # --- Stubs for Global Dependencies ---
  before do
    allow(ADK).to receive(:logger).and_return(instance_double(Logger, info: nil, debug: nil, warn: nil, error: nil))
    allow(ADK::ToolRegistry).to receive(:new).and_return(tool_registry_instance) # Stub registry creation
    allow(ADK::Planner).to receive(:new).and_return(planner_instance) # Stub planner creation
    allow(ADK::GlobalToolManager).to receive(:find_class).and_return(nil) # Default: no tools found globally
    allow(ADK::GlobalToolManager).to receive(:registered_tool_names).and_return([]) # Default: no global tools
    allow(ADK::GlobalToolManager).to receive(:list_all_tools).and_return([]) # Default: no global tools
    # Stub registry methods used during initialization
    allow(tool_registry_instance).to receive(:find_class).and_return(nil)
  end
  # ----------------------------------

  # --- Shared Agent Instantiation Logic ---
  # Use this in contexts where a standard agent instance is needed
  shared_context 'with standard agent' do
    let(:agent) do
      # Mock global finds for standard tools if needed for setup
      allow(ADK::GlobalToolManager).to receive(:find_class).with(:echo).and_return(EchoTool)
      allow(ADK::GlobalToolManager).to receive(:find_class).with(:calculator).and_return(CalcTool)
      # Mock registry calls during init
      allow(tool_registry_instance).to receive(:register).with(:echo, EchoTool).and_return(true)
      allow(tool_registry_instance).to receive(:register).with(:calculator, CalcTool).and_return(true)
      allow(tool_registry_instance).to receive(:find_class).with(:echo).and_return(EchoTool)
      allow(tool_registry_instance).to receive(:find_class).with(:calculator).and_return(CalcTool)
      allow(tool_registry_instance).to receive(:find_class).with(:check_job_status).and_return(nil) # Assume not needed unless testing Sidekiq
      
      ADK::Agent.new(
        name: agent_name,
        description: agent_desc,
        instruction: agent_instruction,
        tool_classes: [EchoTool, CalcTool] # Pass classes
      )
    end
  end
  # ----------------------------------------
  
  # --- Tests for Initialization from Definition (`definition:` kwarg) ---
  describe '#initialize with definition:' do
    let(:agent_def) { ADK::AgentDefinition.new } 
    let(:tool_names_from_def) { [:echo, :calculator] }
    let(:model_from_def) { 'gemini-from-def' }
    let(:instruction_from_def) { 'Instruction from Def' }
    
    before do
      # Capture let variables for use inside the define block
      inst = instruction_from_def
      model = model_from_def
      tools = tool_names_from_def
      
      # Setup the definition object
      agent_def.define do |a|
        a.name :agent_from_def
        a.description 'Defined Agent Desc'
        a.instruction inst # Use captured variable
        a.model_name model # Use captured variable
        tools.each { |tn| a.use_tool tn } # Use captured variable
      end
      
      # Stub GlobalToolManager to find the classes for the tools in the definition
      allow(ADK::GlobalToolManager).to receive(:find_class).with(:echo).and_return(EchoTool)
      allow(ADK::GlobalToolManager).to receive(:find_class).with(:calculator).and_return(CalcTool)
      # Stub registry interactions expected during init from definition
      allow(tool_registry_instance).to receive(:register).with(:echo, EchoTool).and_return(true)
      allow(tool_registry_instance).to receive(:register).with(:calculator, CalcTool).and_return(true)
    end
    
    subject(:agent_from_def) { ADK::Agent.new(definition: agent_def) }
    
    it 'sets attributes from the definition object' do
      expect(agent_from_def.name).to eq(:agent_from_def)
      expect(agent_from_def.description).to eq('Defined Agent Desc')
      expect(agent_from_def.instruction).to eq(instruction_from_def)
      expect(agent_from_def.model_name).to eq(model_from_def.to_sym)
      expect(agent_from_def.definition).to eq(agent_def)
    end
    
    it 'registers tools specified in the definition' do
      # Trigger initialization by accessing the subject
      agent_from_def 
      expect(tool_registry_instance).to have_received(:register).with(:echo_tool, EchoTool)
      expect(tool_registry_instance).to have_received(:register).with(:calc_tool, CalcTool)
    end
    
    it 'ignores other keyword arguments if definition is provided' do
      expect { 
        ADK::Agent.new(definition: agent_def, name: 'ignored', description: 'ignored') 
      }.not_to raise_error
      agent = ADK::Agent.new(definition: agent_def, name: 'ignored', description: 'ignored')
      expect(agent.name).to eq(:agent_from_def) # Name comes from definition
    end
    
    it 'raises ArgumentError if definition is not an AgentDefinition' do
      expect { ADK::Agent.new(definition: {}) }.to raise_error(ArgumentError, /must be an ADK::AgentDefinition/)
    end
  end
  # --- End Tests for Initialization from Definition ---

  # --- Tests for Original Initialization (keyword args) ---
  describe '#initialize with keyword args' do
    # ... (Keep existing initialize tests, ensure they still pass) ...
    # Example adjustment:
    it 'sets name, description, model, and instruction' do
      agent = ADK::Agent.new(name: agent_name, description: agent_desc, model_name: model_name, instruction: agent_instruction)
      expect(agent.name).to eq(agent_name)
      expect(agent.description).to eq(agent_desc)
      expect(agent.model_name).to eq(model_name)
      expect(agent.instruction).to eq(agent_instruction)
      expect(agent.definition).to be_nil # No separate definition object in this path
    end
    
    # ... other existing init tests ...
    
    # Test that error is raised if neither definition nor name is given
    it 'raises ArgumentError if both name and definition are nil' do
      expect { ADK::Agent.new }.to raise_error(ArgumentError, /Agent name must be provided/)
    end
  end
  # --- End Tests for Original Initialization ---

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

  # --- REMOVE THE INNER RSpec.describe BLOCK ---
  # The block `RSpec.describe ADK::Agent do` from line 226 to the end should be removed.
  
end # End RSpec.describe ADK::Agent (Outer block started on line 21)