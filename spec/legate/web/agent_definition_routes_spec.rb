# frozen_string_literal: true

# Characterization specs for the agent-definition web routes. These routes were
# untested; the suite captures their CURRENT behavior so the planned structural
# dedup (the repeated MCP-tool-metadata block, the agent view-hash, and the
# duplicate /update/type & /update/hierarchy routes) can be done behavior-
# preservingly. They assert status + key rendered content + persisted state,
# not exact HTML.
require 'spec_helper'
require 'rack/test'
require 'legate/web/app'

RSpec.describe 'Agent definition routes', type: :request do
  include Rack::Test::Methods

  def app
    Legate::Web::App.new
  end

  # Registers a fresh, MCP-less agent definition (so fetch_mcp_tools is a no-op
  # and the specs make no network calls).
  def register_agent(name: :widget_agent, instruction: 'Be helpful.', description: 'A widget agent.')
    Legate::AgentDefinition.new.define do |a|
      a.name name
      a.instruction instruction
      a.description description
      a.use_tool :echo
      a.use_tool :calculator
    end.tap { |d| Legate::GlobalDefinitionRegistry.register(d) }
  end

  # Establishes a session and returns its CSRF token (state-changing requests
  # need it; the before filter sets it on first request).
  def csrf_token
    get '/'
    last_request.env['rack.session'][:csrf]
  end

  def put_field(name, field, params)
    header 'X-CSRF-Token', csrf_token
    put "/agents/#{name}/update/#{field}", params
  end

  before do
    allow(Legate).to receive(:logger).and_return(instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil))
    Legate::GlobalDefinitionRegistry.clear!
    # spec_helper resets GlobalToolManager after each test, so re-register the
    # built-in tools these routes resolve against.
    [Legate::Tools::Echo, Legate::Tools::Calculator].each { |t| Legate::GlobalToolManager.register_tool(t) }
  end

  after { Legate::GlobalDefinitionRegistry.clear! }

  describe 'GET /agents (list, exercises the MCP-tool-metadata block)' do
    it 'lists registered agents' do
      register_agent
      get '/agents'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('widget_agent')
    end
  end

  describe 'GET /agents/:name (show, exercises the MCP-tool-metadata block)' do
    it 'renders the agent detail' do
      register_agent
      get '/agents/widget_agent'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('widget_agent')
    end

    it '404s for an unknown agent' do
      get '/agents/nope'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'GET /agents/:name/display/:field' do
    before { register_agent }

    %w[description model mcp instruction hierarchy type output_key].each do |field|
      it "renders the #{field} field" do
        get "/agents/widget_agent/display/#{field}"
        expect(last_response.status).to eq(200)
      end
    end

    it '404s for an unsupported field' do
      get '/agents/widget_agent/display/bogus'
      expect(last_response.status).to eq(404)
    end

    it '404s for tools (the tools view is the dedicated tool_table route)' do
      get '/agents/widget_agent/display/tools'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'GET /agents/:name/display/tool_table' do
    it 'renders the tool table' do
      register_agent
      get '/agents/widget_agent/display/tool_table'
      expect(last_response.status).to eq(200)
    end
  end

  describe 'PUT /agents/:name/update/:field' do
    before { register_agent }

    it 'rejects state-changing requests without a CSRF token' do
      put '/agents/widget_agent/update/description', { 'value' => 'x' }
      expect(last_response.status).to eq(403)
    end

    it 'updates the description' do
      put_field('widget_agent', 'description', { 'value' => 'Updated description' })
      expect(last_response.status).to eq(200)
      expect(Legate::GlobalDefinitionRegistry.get_definition(:widget_agent)[:description]).to eq('Updated description')
    end

    it 'updates the model' do
      put_field('widget_agent', 'model', { 'value' => 'gemini-2.0-flash' })
      expect(last_response.status).to eq(200)
      expect(Legate::GlobalDefinitionRegistry.find(:widget_agent).model_name).to eq(:'gemini-2.0-flash')
    end

    it 'updates the instruction' do
      put_field('widget_agent', 'instruction', { 'value' => 'New instruction.' })
      expect(last_response.status).to eq(200)
      expect(Legate::GlobalDefinitionRegistry.find(:widget_agent).instruction).to eq('New instruction.')
    end

    it 'updates the fallback mode' do
      put_field('widget_agent', 'fallback', { 'value' => 'echo' })
      expect(last_response.status).to eq(200)
      expect(Legate::GlobalDefinitionRegistry.find(:widget_agent).fallback_mode).to eq(:echo)
    end

    it 'updates the output_key' do
      put_field('widget_agent', 'output_key', { 'value' => 'result_key' })
      expect(last_response.status).to eq(200)
      expect(Legate::GlobalDefinitionRegistry.find(:widget_agent).output_key).to eq(:result_key)
    end

    it 'updates the selected tools (filters to valid ones)' do
      put_field('widget_agent', 'tools', { 'tools' => %w[echo calculator] })
      expect(last_response.status).to eq(200)
      expect(Legate::GlobalDefinitionRegistry.find(:widget_agent).tool_names.to_a).to contain_exactly(:echo, :calculator)
    end

    it 'updates the MCP servers JSON' do
      put_field('widget_agent', 'mcp', { 'value' => '[]' })
      expect(last_response.status).to eq(200)
    end

    it '404s for an unsupported field' do
      put_field('widget_agent', 'bogus', { 'value' => 'x' })
      expect(last_response.status).to eq(404)
    end
  end

  describe 'agent type / hierarchy updates' do
    before do
      register_agent(name: :coordinator, instruction: 'Coordinate.')
      register_agent(name: :child_agent, instruction: 'Child.')
    end

    it 'updates the agent type via /update/:field' do
      put_field('coordinator', 'type', { 'agent_type' => 'sequential' })
      expect(last_response.status).to eq(200)
      expect(Legate::GlobalDefinitionRegistry.find(:coordinator).agent_type).to eq(:sequential)
    end

    it 'updates the agent type via the standalone /update/type route' do
      header 'X-CSRF-Token', csrf_token
      put '/agents/coordinator/update/type', { 'agent_type' => 'parallel' }
      expect(last_response.status).to eq(200)
      expect(Legate::GlobalDefinitionRegistry.find(:coordinator).agent_type).to eq(:parallel)
    end

    it 'updates the hierarchy via the standalone /update/hierarchy route' do
      header 'X-CSRF-Token', csrf_token
      put '/agents/coordinator/update/hierarchy', { 'sub_agent_names' => ['child_agent'] }
      expect(last_response.status).to eq(200)
    end

    it 'persists planning_strategy alongside the agent type' do
      put_field('coordinator', 'type', { 'agent_type' => 'llm', 'planning_strategy' => 'react' })
      expect(last_response.status).to eq(200)
      expect(Legate::GlobalDefinitionRegistry.find(:coordinator).planning_strategy).to eq(:react)
      expect(last_response.body).to include('ReAct')
    end

    it 'defaults planning_strategy to :plan when an invalid value is submitted' do
      put_field('coordinator', 'type', { 'agent_type' => 'llm', 'planning_strategy' => 'bogus' })
      expect(last_response.status).to eq(200)
      expect(Legate::GlobalDefinitionRegistry.find(:coordinator).planning_strategy).to eq(:plan)
    end
  end
end
