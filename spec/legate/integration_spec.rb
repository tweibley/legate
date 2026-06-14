# frozen_string_literal: true

require 'spec_helper'
require 'legate/agent'
require 'legate/tool'
require 'legate/tool_context'
require 'legate/session'
require 'legate/event'
require 'legate/errors'
require 'legate/global_tool_manager'
require 'legate/global_definition_registry'
require 'legate/session_service/in_memory'

RSpec.describe 'Integration: Agent -> Tool -> Session', type: :integration do
  let(:logger_spy) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil, fatal: nil) }
  let(:session_service) { Legate::SessionService::InMemory.new }

  before do
    allow(Legate).to receive(:logger).and_return(logger_spy)
    allow(logger_spy).to receive(:info)
    allow(logger_spy).to receive(:debug)
    allow(logger_spy).to receive(:error)
    allow(logger_spy).to receive(:warn)
    Legate::GlobalToolManager.reset!
    Legate::GlobalDefinitionRegistry.clear!
  end

  let(:counter_tool_class) do
    Class.new(Legate::Tool) do
      self.explicit_tool_name = :counter
      tool_description 'Increments a counter in session state'
      parameter :amount, type: :integer, required: false

      private

      def perform_execution(params, context)
        current = context.state_get(:counter) || 0
        increment = params[:amount] || 1
        new_val = current + increment
        context.state_set(:counter, new_val)
        { status: :success, result: new_val }
      end
    end
  end

  let(:greeting_tool_class) do
    Class.new(Legate::Tool) do
      self.explicit_tool_name = :greeting
      tool_description 'Returns a greeting with name'
      parameter :name, type: :string, required: true

      private

      def perform_execution(params, _context)
        { status: :success, result: "Hello, #{params[:name]}!" }
      end
    end
  end

  def build_agent(tools:)
    tools.each { |t| Legate::GlobalToolManager.register_tool(t) }
    tool_names = tools.map { |t| t.tool_metadata[:name] }

    definition = Legate::AgentDefinition.new
    definition.define do |d|
      d.name :integration_agent
      d.description 'Integration test agent'
      d.instruction 'test'
      tool_names.each { |tn| d.use_tool tn }
    end

    planner = instance_double('Planner')
    allow(planner).to receive(:plan)

    agent = Legate::Agent.new(definition: definition, planner_override: planner)
    agent.start
    agent
  end

  let(:typed_result_tool_class) do
    Class.new(Legate::Tool) do
      self.explicit_tool_name = :typed_greeting
      tool_description 'Returns a greeting via a typed ToolResult'
      parameter :name, type: :string, required: true

      private

      def perform_execution(params, _context)
        Legate::ToolResult.success("Hello, #{params[:name]}!")
      end
    end
  end

  describe 'tool execution with real classes' do
    it 'normalizes a tool that returns a ToolResult, end to end' do
      agent = build_agent(tools: [typed_result_tool_class])
      session = session_service.create_session(app_name: 'test', user_id: 'u1')

      result = agent.send(:execute_step,
                          { tool: :typed_greeting, params: { name: 'World' } },
                          session, session_service)

      expect(result).to eq(status: :success, result: 'Hello, World!')
      tool_event = session_service.get_session(session_id: session.id).events.find { |e| e.role == :tool_result }
      expect(tool_event.content).to eq(status: :success, result: 'Hello, World!')
    end

    it 'executes a tool and persists the result event in session' do
      agent = build_agent(tools: [greeting_tool_class])
      session = session_service.create_session(app_name: 'test', user_id: 'u1')

      result = agent.send(:execute_step,
                          { tool: :greeting, params: { name: 'World' } },
                          session, session_service)

      expect(result[:status]).to eq(:success)
      expect(result[:result]).to eq('Hello, World!')

      updated_session = session_service.get_session(session_id: session.id)
      events = updated_session.events
      tool_results = events.select { |e| e.role == :tool_result }
      expect(tool_results.size).to eq(1)
      expect(tool_results.first.content[:result]).to eq('Hello, World!')
    end

    it 'persists state_delta from ToolContext into session state' do
      agent = build_agent(tools: [counter_tool_class])
      session = session_service.create_session(app_name: 'test', user_id: 'u1')

      agent.send(:execute_step,
                 { tool: :counter, params: { amount: 5 } },
                 session, session_service)

      updated_session = session_service.get_session(session_id: session.id)
      tool_event = updated_session.events.find { |e| e.role == :tool_result }
      expect(tool_event.state_delta).to include(counter: 5)
      expect(updated_session.get_state(:counter)).to eq(5)
    end

    it 'validates required parameters via real Tool.execute' do
      agent = build_agent(tools: [greeting_tool_class])
      session = session_service.create_session(app_name: 'test', user_id: 'u1')

      result = agent.send(:execute_step,
                          { tool: :greeting, params: {} },
                          session, session_service)

      expect(result[:status]).to eq(:error)
      expect(result[:error_message]).to include('Missing required parameters')
    end

    it 'coerces parameter types via real Tool validation' do
      agent = build_agent(tools: [counter_tool_class])
      session = session_service.create_session(app_name: 'test', user_id: 'u1')

      result = agent.send(:execute_step,
                          { tool: :counter, params: { amount: '3' } },
                          session, session_service)

      expect(result[:status]).to eq(:success)
      expect(result[:result]).to eq(3)
    end

    it 'records both tool_request and tool_result events' do
      agent = build_agent(tools: [greeting_tool_class])
      session = session_service.create_session(app_name: 'test', user_id: 'u1')

      agent.send(:execute_step,
                 { tool: :greeting, params: { name: 'Test' } },
                 session, session_service)

      updated = session_service.get_session(session_id: session.id)
      roles = updated.events.map(&:role)
      expect(roles).to include(:tool_request)
      expect(roles).to include(:tool_result)
    end
  end

  describe 'state accumulation across multiple tool calls' do
    it 'accumulates state across sequential execute_step calls' do
      agent = build_agent(tools: [counter_tool_class])
      session = session_service.create_session(app_name: 'test', user_id: 'u1')

      3.times do
        agent.send(:execute_step,
                   { tool: :counter, params: { amount: 1 } },
                   session, session_service)
      end

      updated = session_service.get_session(session_id: session.id)
      expect(updated.get_state(:counter)).to eq(3)
      expect(updated.events.select { |e| e.role == :tool_result }.size).to eq(3)
    end
  end
end
