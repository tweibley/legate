# File: spec/adk/web/webhook_listener_static_routes_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'adk/web/webhook_listener'
require 'adk/configuration'

RSpec.describe ADK::Web::WebhookListener do
  include Rack::Test::Methods

  # Define a simple WebhookConfig class for our tests
  let(:route_config_class) do
    Struct.new(:handler, :validator, :secret, keyword_init: true)
  end

  # Create configurations for different HTTP methods
  let(:post_handler) do
    ->(request) { [200, { 'Content-Type' => 'application/json' }, ['{"method":"POST","status":"success"}']] }
  end

  let(:get_handler) do
    ->(request) { [200, { 'Content-Type' => 'application/json' }, ['{"method":"GET","status":"success"}']] }
  end

  let(:put_handler) do
    ->(request) { [200, { 'Content-Type' => 'application/json' }, ['{"method":"PUT","status":"success"}']] }
  end

  let(:delete_handler) do
    ->(request) { [200, { 'Content-Type' => 'application/json' }, ['{"method":"DELETE","status":"success"}']] }
  end

  let(:error_handler) do
    ->(request) { raise StandardError, "Handler error" }
  end

  # Default static routes
  let(:static_routes) do
    {
      "POST /api/webhook" => route_config_class.new(handler: post_handler, validator: nil, secret: nil),
      "GET /api/data" => route_config_class.new(handler: get_handler, validator: nil, secret: nil),
      "PUT /api/update" => route_config_class.new(handler: put_handler, validator: nil, secret: nil),
      "DELETE /api/remove" => route_config_class.new(handler: delete_handler, validator: nil, secret: nil),
      "GET /api/error" => route_config_class.new(handler: error_handler, validator: nil, secret: nil)
    }
  end

  # Define the webhook config
  let(:webhook_config) do
    instance_double(
      ADK::Configuration::Webhooks,
      static_routes: static_routes,
      # Other required config values
      enable_dynamic_agent_handler: true,
      dynamic_agent_route_pattern: '/agents/:agent_name/trigger',
      base_path: '/',
      global_validator: nil,
      find_validator: nil
    )
  end

  # Mock the rest of the ADK.config
  before do
    allow(ADK).to receive(:config).and_return(
      instance_double(
        ADK::Configuration,
        webhooks: webhook_config
      )
    )

    # Stub logger to reduce noise in tests
    allow(ADK).to receive(:logger).and_return(
      instance_double(
        Logger,
        info: nil,
        debug: nil,
        warn: nil,
        error: nil
      )
    )
  end

  # Set the app for Rack::Test
  def app
    ADK::Web::WebhookListener.new
  end

  describe "static routes basic functionality" do
    it "responds to POST /api/webhook endpoint" do
      post "/api/webhook"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq('{"method":"POST","status":"success"}')
    end

    it "responds to GET /api/data endpoint" do
      get "/api/data"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq('{"method":"GET","status":"success"}')
    end

    it "handles PUT requests" do
      put "/api/update"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq('{"method":"PUT","status":"success"}')
    end

    it "handles DELETE requests" do
      delete "/api/remove"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq('{"method":"DELETE","status":"success"}')
    end

    it "returns 404 for undefined routes" do
      get "/undefined/route"
      expect(last_response.status).to eq(404)
    end

    it "returns 500 when handler raises an error" do
      get "/api/error"
      expect(last_response.status).to eq(500)
      expect(JSON.parse(last_response.body)['error_message']).to include('Internal Server Error')
    end
  end
end
