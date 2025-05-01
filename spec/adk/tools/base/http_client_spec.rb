# File: spec/adk/tools/base/http_client_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/tools/base/http_client'
require 'adk/tool' # Need a base tool class to include the module in
require 'faraday'
require 'webmock/rspec'

# A dummy tool class to test the HttpClient module
class DummyHttpTool < ADK::Tool
  include ADK::Tools::Base::HttpClient
  tool_description 'A dummy tool for testing HttpClient'

  # Expose protected/private methods for testing
  public :setup_http_client, :http_get, :http_post, :parse_json_response

  def execute(params:, context: nil)
    # Dummy execute method
    { status: :success, result: 'dummy execution' }
  end
end

RSpec.describe ADK::Tools::Base::HttpClient do
  let(:base_url) { 'https://api.test.com' }
  let(:tool_instance) { DummyHttpTool.new }

  before do
    # Stub ADK.logger to avoid actual logging during tests
    allow(ADK).to receive(:logger).and_return(instance_double('Logger', debug: nil, info: nil, warn: nil, error: nil))
    # Stub ADK::VERSION if needed for User-Agent header tests
    stub_const("ADK::VERSION", "0.test.0")
  end

  describe '#setup_http_client' do
    it 'initializes a Faraday connection with the correct base URL' do
      tool_instance.setup_http_client(base_url: base_url)
      client = tool_instance.instance_variable_get(:@http_client)
      expect(client).to be_a(Faraday::Connection)
      expect(client.url_prefix.to_s).to eq(base_url + '/') # Faraday adds trailing slash
    end

    it 'sets default timeouts' do
      tool_instance.setup_http_client(base_url: base_url)
      client = tool_instance.instance_variable_get(:@http_client)
      expect(client.options.timeout).to eq(ADK::Tools::Base::HttpClient::DEFAULT_TIMEOUT)
      expect(client.options.open_timeout).to eq(ADK::Tools::Base::HttpClient::DEFAULT_OPEN_TIMEOUT)
    end

    it 'allows overriding timeouts' do
      tool_instance.setup_http_client(base_url: base_url, timeout: 10, open_timeout: 5)
      client = tool_instance.instance_variable_get(:@http_client)
      expect(client.options.timeout).to eq(10)
      expect(client.options.open_timeout).to eq(5)
    end

    it 'sets default headers including User-Agent' do
      tool_instance.setup_http_client(base_url: base_url)
      client = tool_instance.instance_variable_get(:@http_client)
      expect(client.headers['User-Agent']).to eq("ADK-Ruby Tool/0.test.0")
    end

    it 'merges custom headers with defaults' do
      tool_instance.setup_http_client(base_url: base_url, headers: { 'X-Custom' => 'value' })
      client = tool_instance.instance_variable_get(:@http_client)
      expect(client.headers['User-Agent']).to eq("ADK-Ruby Tool/0.test.0")
      expect(client.headers['X-Custom']).to eq('value')
    end

    it 'raises ADK::ToolError if Faraday initialization fails' do
      allow(Faraday).to receive(:new).and_raise(Faraday::Error.new("Setup failed"))
      expect {
        tool_instance.setup_http_client(base_url: base_url)
      }.to raise_error(ADK::ToolError, /Failed to initialize Faraday connection.*Setup failed/)
      expect(tool_instance.instance_variable_get(:@http_client)).to be_nil
    end
  end

  context 'when client is initialized' do
    before do
      tool_instance.setup_http_client(base_url: base_url)
    end

    describe '#http_get' do
      let(:path) { '/resource' }
      let(:full_url) { base_url + path }

      it 'performs a GET request to the correct URL' do
        stub_request(:get, full_url).to_return(status: 200, body: '{}')
        tool_instance.http_get(path)
        expect(a_request(:get, full_url)).to have_been_made.once
      end

      it 'includes query parameters' do
        params = { key: 'value', num: 123 }
        stub_request(:get, full_url).with(query: params).to_return(status: 200, body: '{}')
        tool_instance.http_get(path, params: params)
        expect(a_request(:get, full_url).with(query: params)).to have_been_made.once
      end

      it 'includes additional headers' do
        headers = { 'Accept' => 'application/json' }
        stub_request(:get, full_url).with(headers: headers).to_return(status: 200, body: '{}')
        tool_instance.http_get(path, headers: headers)
        # Note: Webmock merges headers, so check for the specific one
        expect(a_request(:get, full_url).with { |req|
          req.headers['Accept'] == 'application/json'
        }).to have_been_made.once
      end

      it 'returns the Faraday::Response object on success' do
        stub_request(:get, full_url).to_return(status: 200, body: 'Success')
        response = tool_instance.http_get(path)
        expect(response).to be_a(Faraday::Response)
        expect(response.status).to eq(200)
        expect(response.body).to eq('Success')
      end

      it 'raises ADK::ToolError on Faraday::TimeoutError' do
        stub_request(:get, full_url).to_timeout
        expect {
          tool_instance.http_get(path)
        }.to raise_error(ADK::ToolError, /Connection failed during GET request.*execution expired/)
      end

      it 'raises ADK::ToolError on Faraday::ConnectionFailed' do
        stub_request(:get, full_url).to_raise(Faraday::ConnectionFailed.new("Failed to connect"))
        expect {
          tool_instance.http_get(path)
        }.to raise_error(ADK::ToolError, /Connection failed during GET request.*Failed to connect/)
      end

      it 'raises ADK::ToolError on Faraday::Error (e.g., 4xx/5xx)' do
        stub_request(:get, full_url).to_return(status: 404, body: 'Not Found')
        expect {
          tool_instance.http_get(path)
        }.to raise_error(ADK::ToolError, /HTTP error during GET request.*Status: 404/)
      end

      it 'raises ADK::ToolError on other StandardError during request' do
        allow(tool_instance.instance_variable_get(:@http_client)).to receive(:run_request).and_raise(StandardError.new("Unexpected issue"))
        expect {
          tool_instance.http_get(path)
        }.to raise_error(ADK::ToolError, /Unexpected error during GET request.*Unexpected issue/)
      end
    end

    describe '#http_post' do
      let(:path) { '/create' }
      let(:full_url) { base_url + path }
      let(:request_body) { { name: 'test', value: 1 } }
      let(:request_headers) { { 'Content-Type' => 'application/json' } }

      it 'performs a POST request to the correct URL' do
        stub_request(:post, full_url).to_return(status: 201, body: '{}')
        tool_instance.http_post(path, body: request_body, headers: request_headers)
        expect(a_request(:post, full_url)).to have_been_made.once
      end

      it 'sends the request body' do
        stub_request(:post, full_url).with(body: request_body).to_return(status: 201, body: '{}')
        tool_instance.http_post(path, body: request_body, headers: request_headers)
        expect(a_request(:post, full_url).with(body: request_body)).to have_been_made.once
      end

      it 'sends the specified headers' do
        stub_request(:post, full_url).with(headers: request_headers).to_return(status: 201, body: '{}')
        tool_instance.http_post(path, body: request_body, headers: request_headers)
        expect(a_request(:post, full_url).with { |req|
          req.headers['Content-Type'] == 'application/json'
        }).to have_been_made.once
      end

      it 'returns the Faraday::Response object on success' do
        stub_request(:post, full_url).to_return(status: 201, body: 'Created')
        response = tool_instance.http_post(path, body: request_body, headers: request_headers)
        expect(response).to be_a(Faraday::Response)
        expect(response.status).to eq(201)
        expect(response.body).to eq('Created')
      end

      it 'raises ADK::ToolError on errors (similar to http_get)' do
        stub_request(:post, full_url).to_timeout
        expect {
          tool_instance.http_post(path, body: request_body, headers: request_headers)
        }.to raise_error(ADK::ToolError, /Connection failed during POST request.*execution expired/)
      end
    end

    describe '#parse_json_response' do
      it 'parses valid JSON body' do
        response = instance_double(Faraday::Response, body: '{"key": "value", "num": 123}')
        parsed = tool_instance.parse_json_response(response)
        expect(parsed).to eq({ "key" => "value", "num" => 123 })
      end

      it 'raises ADK::ToolError on invalid JSON' do
        response = instance_double(Faraday::Response, body: 'invalid json')
        expect {
          tool_instance.parse_json_response(response)
        }.to raise_error(ADK::ToolError, /Error parsing JSON response/)
      end
    end
  end

  context 'when client is not initialized' do
    it '#http_get raises ADK::ToolError' do
      expect {
        tool_instance.http_get('/path')
      }.to raise_error(ADK::ToolError, /HTTP client has not been initialized/)
    end

    it '#http_post raises ADK::ToolError' do
      expect {
        tool_instance.http_post('/path', body: {})
      }.to raise_error(ADK::ToolError, /HTTP client has not been initialized/)
    end
  end
end
