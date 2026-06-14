# File: spec/legate/tools/http_request_tool_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'legate/tools/http_request_tool'
require 'json'
require 'webmock/rspec'

Legate.logger.level = Logger::FATAL

RSpec.describe Legate::Tools::HttpRequest do
  let(:tool) { described_class.new }

  around do |example|
    WebMock.enable!
    WebMock.disable_net_connect!
    example.run
    WebMock.reset!
    WebMock.disable!
  end

  it 'has the inferred tool name :http_request' do
    expect(described_class.tool_metadata[:name]).to eq(:http_request)
  end

  describe 'SSRF protection' do
    it 'returns an error for a loopback address without making a request' do
      result = tool.execute({ url: 'http://127.0.0.1/secret' }, nil)
      expect(result[:status]).to eq(:error)
      expect(result[:error_message]).to match(/restricted network address/)
    end

    it 'returns an error for cloud metadata' do
      result = tool.execute({ url: 'http://169.254.169.254/latest/meta-data/' }, nil)
      expect(result[:status]).to eq(:error)
    end

    it 'rejects non-http(s) schemes' do
      result = tool.execute({ url: 'file:///etc/passwd' }, nil)
      expect(result[:status]).to eq(:error)
    end
  end

  describe 'requests' do
    it 'performs a GET and returns status, body, and headers' do
      stub_request(:get, 'http://8.8.8.8/data')
        .to_return(status: 200, body: 'hello', headers: { 'X-Test' => 'yes' })

      result = tool.execute({ url: 'http://8.8.8.8/data' }, nil)
      expect(result[:status]).to eq(:success)
      expect(result[:result][:status_code]).to eq(200)
      expect(result[:result][:body]).to eq('hello')
      expect(result[:result][:truncated]).to be(false)
    end

    it 'returns a non-2xx response as a result (not an error)' do
      stub_request(:get, 'http://8.8.8.8/missing').to_return(status: 404, body: 'nope')
      result = tool.execute({ url: 'http://8.8.8.8/missing' }, nil)
      expect(result[:status]).to eq(:success)
      expect(result[:result][:status_code]).to eq(404)
    end

    it 'JSON-encodes a Hash body for POST' do
      stub_request(:post, 'http://8.8.8.8/submit')
        .with(body: '{"a":1}', headers: { 'Content-Type' => %r{application/json} })
        .to_return(status: 201, body: '')
      result = tool.execute({ url: 'http://8.8.8.8/submit', method: 'POST', body: { a: 1 } }, nil)
      expect(result[:result][:status_code]).to eq(201)
    end

    it 'rejects an unsupported HTTP method' do
      result = tool.execute({ url: 'http://8.8.8.8/', method: 'CONNECT' }, nil)
      expect(result[:status]).to eq(:error)
      expect(result[:error_message]).to match(/Unsupported HTTP method/)
    end

    it 'truncates an oversized body' do
      stub_const("#{described_class}::MAX_BODY_BYTES", 5)
      stub_request(:get, 'http://8.8.8.8/big').to_return(status: 200, body: 'abcdefghij')
      result = tool.execute({ url: 'http://8.8.8.8/big' }, nil)
      expect(result[:result][:truncated]).to be(true)
      expect(result[:result][:body].bytesize).to eq(5)
    end
  end

  describe 'auth-awareness' do
    it 'applies headers returned by the context auth handler' do
      context = double('ToolContext', to_h: {})
      allow(context).to receive(:handle_request_auth) do |request|
        request.merge(headers: request[:headers].merge('Authorization' => 'Bearer xyz'))
      end

      stub_request(:get, 'http://8.8.8.8/api/data')
        .with(headers: { 'Authorization' => 'Bearer xyz' })
        .to_return(status: 200, body: 'ok')

      result = tool.execute({ url: 'http://8.8.8.8/api/data' }, context)
      expect(result[:status]).to eq(:success)
      expect(context).to have_received(:handle_request_auth)
    end
  end
end
