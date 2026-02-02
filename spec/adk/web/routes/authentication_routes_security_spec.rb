# frozen_string_literal: true

require 'spec_helper'
require 'adk/web/routes/authentication_routes'
require 'webmock/rspec'
require 'rack/test'
require 'sinatra/base'

RSpec.describe 'AuthenticationRoutes Helpers Security' do
  include Rack::Test::Methods

  let(:app) do
    Class.new(Sinatra::Base) do
      register ADK::Web::AuthenticationRoutes

      # Expose helper for testing via a route
      get '/test_api_key_security' do
        content_type :json
        credential = {
          auth_type: :api_key,
          api_key: params[:api_key],
          location: 'query',
          name: 'key'
        }

        result = test_api_key_credential(credential, test_url: 'http://example.com/api')
        result.to_json
      end
    end
  end

  it 'prevents parameter injection in API key test' do
    # Malicious API key that attempts to inject a new parameter 'injected=true'
    malicious_key = 'secret&injected=true'

    # We expect the outgoing request to encode the ampersand
    # key=secret%26injected%3Dtrue
    expected_query = "key=#{URI.encode_www_form_component(malicious_key)}"

    stub_request(:get, "http://example.com/api?#{expected_query}")
      .to_return(status: 200, body: 'OK')

    # If the code is vulnerable, it will send key=secret&injected=true
    # which will NOT match the stub above (or we can match any and check what was sent).

    stub_request(:get, 'http://example.com/api?key=secret&injected=true')
      .to_return(status: 200, body: 'VULNERABLE')

    get '/test_api_key_security', api_key: malicious_key

    # We want to assert that the SECURE request was made
    # If the code is vulnerable, it sends "key=secret&injected=true" (two params)
    # If the code is secure, it sends "key=secret%26injected%3Dtrue" (one param)
    expect(WebMock).to have_requested(:get, 'http://example.com/api').with(query: { 'key' => malicious_key })
  end
end
