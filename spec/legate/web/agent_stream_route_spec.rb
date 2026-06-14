# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'legate/web'

# Behavioral coverage of POST /agents/:name/stream (R3 SSE endpoint).
RSpec.describe 'Agent streaming SSE route', type: :request do
  include Rack::Test::Methods

  def app
    @app ||= Legate::Web::App.new
  end

  # App.new returns a Sinatra::Wrapper; the actual app instance (holding @agents
  # and @session_service, shared with each per-request dup) is its @instance.
  def app_instance
    app.instance_variable_get(:@instance)
  end

  let(:greeting_tool_class) do
    Class.new(Legate::Tool) do
      self.explicit_tool_name = :greeting
      tool_description 'Greets a name'
      parameter :name, type: :string, required: true

      private

      def perform_execution(params, _context)
        { status: :success, result: "Hello, #{params[:name]}!" }
      end
    end
  end

  before do
    allow(Legate).to receive(:logger).and_return(instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil))
    Legate::GlobalToolManager.reset!
    Legate::GlobalToolManager.register_tool(greeting_tool_class)
  end

  # The before filter sets session[:csrf]; POSTs must echo it back.
  def csrf_token
    get '/'
    last_request.env['rack.session'][:csrf]
  end

  def start_agent(name)
    service = app_instance.instance_variable_get(:@session_service)
    planner = instance_double(Legate::Planner)
    allow(planner).to receive(:plan).and_return(
      { thought_process: 'greet', steps: [{ tool: :greeting, params: { name: 'World' }, reason: 'greet' }] }
    )
    definition = Legate::AgentDefinition.new
    definition.define do |d|
      d.name name.to_sym
      d.description 'Greets'
      d.instruction 'Greet people.'
      d.use_tool :greeting
    end
    agent = Legate::Agent.new(definition: definition, session_service: service, planner_override: planner)
    agent.start
    app_instance.instance_variable_get(:@agents)[name] = agent
  end

  it 'streams message frames then a done frame for a running agent' do
    start_agent('greeter')
    header 'X-CSRF-Token', csrf_token
    post '/agents/greeter/stream', { 'message' => 'greet World' }

    expect(last_response.status).to eq(200)
    expect(last_response.content_type).to include('text/event-stream')
    body = last_response.body
    expect(body).to include('event: message')
    expect(body).to include('"role":"tool_result"')
    expect(body).to include('event: done')
    expect(body).to include('Hello, World!')
  end

  it 'emits an error frame when the agent is not running' do
    header 'X-CSRF-Token', csrf_token
    post '/agents/missing/stream', { 'message' => 'hi' }

    expect(last_response.content_type).to include('text/event-stream')
    expect(last_response.body).to include('event: error')
    expect(last_response.body).to include('is not running')
  end

  it 'emits an error frame when the message is blank' do
    start_agent('greeter')
    header 'X-CSRF-Token', csrf_token
    post '/agents/greeter/stream', { 'message' => '' }

    expect(last_response.body).to include('event: error')
    expect(last_response.body).to include("Missing 'message'")
  end

  it 'rejects a POST without a CSRF token' do
    post '/agents/greeter/stream', { 'message' => 'hi' }
    expect(last_response.status).to eq(403)
  end
end
