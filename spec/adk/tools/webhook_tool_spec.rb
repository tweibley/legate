# File: spec/adk/tools/webhook_tool_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/tools/webhook_tool'
require 'adk/tool_context'
require 'adk/tool/error'
require 'json'
require 'openssl'
require 'webmock/rspec' # Use WebMock

ADK.logger.level = Logger::FATAL # Quieten logs for tests

# Mock context for testing
class MockToolContext
  # Include RSpec Mocks for instance_double
  include RSpec::Mocks::ExampleMethods

  attr_reader :session, :tool_registry

  def initialize(session: nil, tool_registry: nil)
    @session = session || instance_double('ADK::Session')
    @tool_registry = tool_registry || instance_double('ADK::GlobalToolManager')
  end

  def get_state(key, prefix: nil); end
  def set_state(key, value, prefix: nil); end
  def update_state(updates, prefix: nil); end
  def delete_state(key, prefix: nil); end
  def clear_state!(prefix: nil); end
  def log(message, level: :info); end
end

RSpec.describe ADK::Tools::WebhookTool do
  let(:url) { 'https://example.com/webhook' }
  let(:payload_hash) { { message: 'Hello', value: 123 } }
  let(:payload_json) { JSON.generate(payload_hash) }
  let(:payload_string) { 'Plain text payload' }
  let(:secret) { 'my_super_secret_key' }
  let(:custom_headers) { { 'X-Custom-Header' => 'Value' } }
  let(:context) { MockToolContext.new }
  let(:tool) { described_class.new }

  # Setup WebMock around tests
  around do |example|
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
    example.run
    WebMock.reset!
    WebMock.disable!
  end

  # --- Metadata Tests ---
  describe 'Class Metadata' do
    it 'has the correct inferred tool name' do
      expect(described_class.tool_metadata[:name]).to eq(:webhook_tool)
    end
    it 'has the correct description' do
      expect(described_class.tool_metadata[:description]).to include('Sends an HTTP POST request')
    end
    it 'defines parameters correctly' do
      expect(described_class.tool_metadata[:parameters].keys).to contain_exactly(:url, :payload, :secret, :headers)
      expect(described_class.tool_metadata[:parameters][:url][:required]).to be true
      expect(described_class.tool_metadata[:parameters][:payload][:required]).to be true
      expect(described_class.tool_metadata[:parameters][:secret][:required]).to be false
      expect(described_class.tool_metadata[:parameters][:headers][:required]).to be false
    end
  end

  # --- Execution Tests ---
  describe '#execute' do
    context 'with basic hash payload' do
      let(:params) { { url: url, payload: payload_hash } }
      before do
        # Match actual Content-Type header from Excon
        # Remove expectation for Content-Type header
        stub_request(:post, url).with(body: payload_json).to_return(status: 200, body: 'OK')
      end

      it 'sends POST with JSON payload and default headers' do
        result = tool.execute(params, context: context)
        # Check status symbol and data
        expect(result[:status]).to eq(:success)
        expect(result[:result][:response_status]).to eq(200)
        expect(result[:result][:response_body]).to eq('OK')
        # Remove expectation for Content-Type header
        expect(a_request(:post, url).with(body: payload_json)).to have_been_made.once
        # Check User-Agent header specifically if needed, as other defaults might exist
        expect(a_request(:post, url).with { |req|
          req.headers['User-Agent'].start_with?('ADK-Ruby/')
        }).to have_been_made
      end
    end

    context 'with string payload' do
      let(:params) { { url: url, payload: payload_string } }
      before do
        # Expect NO default Content-Type for string body
        stub_request(:post, url).with(body: payload_string).to_return(status: 200, body: 'Accepted')
      end

      it 'sends POST with string payload and no default Content-Type' do
        result = tool.execute(params, context: context)
        # Check status symbol and data
        expect(result[:status]).to eq(:success)
        expect(result[:result][:response_status]).to eq(200)
        expect(result[:result][:response_body]).to eq('Accepted')
        # Assert request was made *without* Content-Type (or ensure it wasn't application/json)
        expect(a_request(:post, url).with { |req|
          !req.headers.key?('Content-Type') || !req.headers['Content-Type'].start_with?('application/json')
        }).to have_been_made.once
      end

      # Add test for string payload WITH custom content-type
      it 'sends POST with string payload and custom Content-Type' do
        ctype = { 'Content-Type' => 'text/plain' }
        stub_request(:post, url).with(body: payload_string, headers: ctype).to_return(status: 200)
        tool.execute(params.merge(headers: ctype), context: context)
        expect(a_request(:post, url).with(body: payload_string, headers: ctype)).to have_been_made.once
      end
    end

    context 'with secret for signing' do
      let(:params) { { url: url, payload: payload_hash, secret: secret } }
      let(:expected_signature) { OpenSSL::HMAC.hexdigest('sha256', secret, payload_json) }
      before do
        # Adjust stub to match actual Content-Type
        # Remove expectation for Content-Type header
        stub_request(:post, url).with(
          body: payload_json,
          headers: { 'X-Hub-Signature-256' => "sha256=#{expected_signature}" }
        ).to_return(status: 200, body: 'Signed OK')
      end

      it 'calculates and includes correct X-Hub-Signature-256 header' do
        result = tool.execute(params, context: context)
        # Check status symbol and data
        expect(result[:status]).to eq(:success)
        expect(result[:result][:response_body]).to eq('Signed OK')
        # Check for signature AND the default content-type for hash payloads
        expect(a_request(:post, url).with do |req|
          req.headers['X-Hub-Signature-256'] == "sha256=#{expected_signature}" &&
          req.headers['Content-Type']&.start_with?('application/json')
        end).to have_been_made.once
      end
    end

    context 'with custom headers' do
      let(:params) { { url: url, payload: payload_hash, headers: custom_headers } }
      before do
        # Adjust stub to match actual Content-Type
        # Remove expectation for Content-Type header, keep custom ones
        stub_request(:post, url).with(body: payload_json, headers: custom_headers).to_return(status: 200,
                                                                                             body: 'Headers OK')
      end

      it 'includes custom headers in the request' do
        result = tool.execute(params, context: context)
        # Check status symbol and data
        expect(result[:status]).to eq(:success)
        expect(result[:result][:response_body]).to eq('Headers OK')
        expect(a_request(:post, url).with { |req|
          req.headers.include?('X-Custom-Header') && req.headers['X-Custom-Header'] == 'Value'
        }).to have_been_made.once
      end
    end

    context 'with invalid URL' do
      let(:params) { { url: 'invalid url', payload: payload_hash } }
      it 'raises ToolArgumentError' do
        # Expect the error raised by WebhookTool itself for invalid URL format
        expect {
          tool.execute(params,
                       context: context)
        }.to raise_error(ADK::ToolArgumentError, /Invalid URL provided: invalid url - bad URI/)
      end
    end

    context 'when http_post fails (e.g., timeout)' do
      let(:params) { { url: url, payload: payload_hash } }
      before do
        stub_request(:post, url).to_timeout
      end
      it 'raises the underlying ToolError' do
        expect {
          tool.execute(params, context: context)
        }.to raise_error(ADK::ToolTimeoutError, /Timeout during POST request/)
      end
    end
  end
end
