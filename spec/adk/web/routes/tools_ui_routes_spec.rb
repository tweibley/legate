# frozen_string_literal: true

require 'spec_helper'
require 'adk/web/routes/tools_ui_routes'
require 'adk/web/app'
require 'rack/test'

RSpec.describe ADK::Web::ToolsUIRoutes do
  include Rack::Test::Methods

  # Mock Sinatra app to mix in the module
  let(:app) do
    # Create a subclass of Sinatra::Base to isolate tests
    Class.new(Sinatra::Base) do
      # Mock logger helper
      helpers do
        def logger
          @logger ||= Logger.new(IO::NULL)
        end

        # Mock slim renderer to just return "slim_template"
        def slim(template, options = {})
          "slim_#{template}"
        end

        def fetch_mcp_tools(configs, timeout = 5)
          return [] if configs.empty?
          # Mock response for testing
          configs.map do |config|
            {
              status: :success,
              server: config['name'],
              tools: [
                {
                  name: "mcp_tool_#{config['name']}",
                  description: "A mock MCP tool from #{config['name']}",
                  inputSchema: {
                    type: "object",
                    properties: {
                      arg1: { type: "string" }
                    }
                  }
                }
              ]
            }
          end
        end
      end

      # Mock ADK::GlobalToolManager
      class << self
        def definition_store_mock
          @definition_store_mock
        end

        def definition_store_mock=(val)
          @definition_store_mock = val
        end
      end

      # Register the module under test
      register ADK::Web::ToolsUIRoutes

      def initialize
        super
        # Set the instance variable that the route expects
        @definition_store = self.class.definition_store_mock
      end
    end
  end

  let(:mock_definition_store) { double('DefinitionStore') }

  before do
    # Setup global tool manager mock
    allow(ADK::GlobalToolManager).to receive(:list_all_tools).and_return([
      {
        name: :native_tool_1,
        description: "A native tool",
        parameters: {
          param1: { type: :string, description: "Parameter 1", required: true }
        }
      }
    ])

    allow(ADK::GlobalToolManager).to receive(:find_class).with(:native_tool_1).and_return(Class.new)
    allow(ADK::GlobalToolManager).to receive(:find_class).with(:mcp_tool_server1).and_return(nil)

    # Setup definition store mock
    app.definition_store_mock = mock_definition_store
  end

  describe 'GET /tools' do
    context 'when definition store is available' do
      before do
        allow(mock_definition_store).to receive(:list_definitions).and_return([
          {
            name: "agent1",
            mcp_servers_json: '[{"name": "server1", "command": "cmd"}]'
          }
        ])
      end

      it 'returns success' do
        get '/tools'
        expect(last_response).to be_ok
        expect(last_response.body).to include('slim_tools')
      end
    end

    context 'when definition store is not available' do
      before do
        app.definition_store_mock = nil
      end

      it 'handles nil definition store gracefully' do
        get '/tools'
        expect(last_response).to be_ok
      end
    end
  end

  describe 'GET /tools/:name' do
    context 'for a native tool' do
      it 'returns tool details' do
        get '/tools/native_tool_1'
        expect(last_response).to be_ok
        expect(last_response.body).to include('slim_tool_detail')
      end
    end

    context 'for an MCP tool' do
      before do
        allow(mock_definition_store).to receive(:list_definitions).and_return([
          {
            name: "agent1",
            mcp_servers_json: '[{"name": "server1", "command": "cmd"}]'
          }
        ])
      end

      it 'returns tool details' do
        get '/tools/mcp_tool_server1'
        expect(last_response).to be_ok
        expect(last_response.body).to include('slim_tool_detail')
      end
    end

    context 'for a non-existent tool' do
      before do
        allow(mock_definition_store).to receive(:list_definitions).and_return([])
      end

      it 'returns 404' do
        get '/tools/non_existent_tool'
        expect(last_response.status).to eq(404)
        expect(last_response.body).to include('slim_error_404')
      end
    end
  end
end
