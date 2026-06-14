# frozen_string_literal: true

require 'spec_helper'
require 'legate/agent'
require 'legate/tool'
require 'legate/errors'
require 'legate/global_tool_manager'
require 'legate/global_definition_registry'
require 'legate/session_service/in_memory'

RSpec.describe 'Agent error paths' do
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

  let(:ok_tool_class) do
    Class.new(Legate::Tool) do
      self.explicit_tool_name = :ok_tool
      tool_description 'Always succeeds'
      parameter :input, type: :string, required: false

      private

      def perform_execution(_params, _context)
        { status: :success, result: 'done' }
      end
    end
  end

  let(:exploding_tool_class) do
    Class.new(Legate::Tool) do
      self.explicit_tool_name = :exploding_tool
      tool_description 'Always raises'
      parameter :input, type: :string, required: false

      private

      def perform_execution(_params, _context)
        raise 'kaboom'
      end
    end
  end

  def build_agent(tools:, callbacks: {})
    tools.each { |t| Legate::GlobalToolManager.register_tool(t) }

    tool_names = tools.map { |t| t.tool_metadata[:name] }
    definition = Legate::AgentDefinition.new
    definition.define do |d|
      d.name :test_agent
      d.description 'Test agent'
      d.instruction 'test instruction'
      tool_names.each { |tn| d.use_tool tn }
    end

    planner = instance_double('Planner')
    allow(planner).to receive(:plan)

    agent = Legate::Agent.new(definition: definition, planner_override: planner)
    agent.instance_variable_set(:@before_tool_callback, callbacks[:before_tool]) if callbacks[:before_tool]
    agent.instance_variable_set(:@after_tool_callback, callbacks[:after_tool]) if callbacks[:after_tool]
    agent.start
    agent
  end

  describe '#execute_step' do
    describe 'invalid step format' do
      it 'returns error for nil step' do
        agent = build_agent(tools: [ok_tool_class])
        session = session_service.create_session(app_name: 'test', user_id: 'u1')

        result = agent.send(:execute_step, nil, session, session_service)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include('Invalid step format')
      end

      it 'returns error for step without params hash' do
        agent = build_agent(tools: [ok_tool_class])
        session = session_service.create_session(app_name: 'test', user_id: 'u1')

        result = agent.send(:execute_step, { tool: :ok_tool, params: 'not_a_hash' }, session, session_service)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include('Invalid step format')
      end
    end

    describe 'unknown tool' do
      it 'returns error for unregistered tool name' do
        agent = build_agent(tools: [ok_tool_class])
        session = session_service.create_session(app_name: 'test', user_id: 'u1')

        result = agent.send(:execute_step, { tool: :nonexistent, params: {} }, session, session_service)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include('Unknown tool')
      end
    end

    describe 'tool execution error' do
      it 'catches tool exceptions and returns error result' do
        agent = build_agent(tools: [exploding_tool_class])
        session = session_service.create_session(app_name: 'test', user_id: 'u1')

        result = agent.send(:execute_step, { tool: :exploding_tool, params: {} }, session, session_service)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include('kaboom')
      end

      it 'logs a tool_result event with the error' do
        agent = build_agent(tools: [exploding_tool_class])
        session = session_service.create_session(app_name: 'test', user_id: 'u1')

        agent.send(:execute_step, { tool: :exploding_tool, params: {} }, session, session_service)

        events = session_service.get_session(session_id: session.id).events
        tool_results = events.select { |e| e.role == :tool_result }
        expect(tool_results).not_to be_empty
        expect(tool_results.last.content[:status]).to eq(:error)
      end
    end

    describe 'callback error paths' do
      it 'returns error when before_tool callback raises' do
        bad_before = ->(_tool, _params, _ctx) { raise 'before_tool broke' }
        agent = build_agent(tools: [ok_tool_class], callbacks: { before_tool: bad_before })
        session = session_service.create_session(app_name: 'test', user_id: 'u1')

        result = agent.send(:execute_step, { tool: :ok_tool, params: {} }, session, session_service)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include('before_tool_callback')
      end

      it 'still returns tool result when after_tool callback raises' do
        bad_after = ->(_tool, _params, _ctx, _result) { raise 'after_tool broke' }
        agent = build_agent(tools: [ok_tool_class], callbacks: { after_tool: bad_after })
        session = session_service.create_session(app_name: 'test', user_id: 'u1')

        result = agent.send(:execute_step, { tool: :ok_tool, params: {} }, session, session_service)
        expect(result[:status]).to eq(:success)
      end
    end
  end
end
