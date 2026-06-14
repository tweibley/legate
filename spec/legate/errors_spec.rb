# frozen_string_literal: true

require 'spec_helper'
require 'legate/errors'

RSpec.describe 'Legate error hierarchy' do
  describe 'inheritance' do
    it 'all Legate errors descend from Legate::Error' do
      expect(Legate::ConfigurationError.ancestors).to include(Legate::Error)
      expect(Legate::InvalidPrefixError.ancestors).to include(Legate::Error)
      expect(Legate::SerializationError.ancestors).to include(Legate::Error)
      expect(Legate::ToolError.ancestors).to include(Legate::Error)
      expect(Legate::ToolArgumentError.ancestors).to include(Legate::ToolError)
      expect(Legate::ToolNetworkError.ancestors).to include(Legate::ToolError)
      expect(Legate::ToolCertificateError.ancestors).to include(Legate::ToolNetworkError)
      expect(Legate::ToolTimeoutError.ancestors).to include(Legate::ToolError)
      expect(Legate::ToolHttpError.ancestors).to include(Legate::ToolError)
      expect(Legate::WebhookConfigurationError.ancestors).to include(Legate::Error)
      expect(Legate::StoreError.ancestors).to include(Legate::Error)
    end

    it 'MCP errors descend from Legate::Mcp::Error' do
      expect(Legate::Mcp::Error.ancestors).to include(Legate::Error)
      expect(Legate::Mcp::ConnectionError.ancestors).to include(Legate::Mcp::Error)
      expect(Legate::Mcp::ProtocolError.ancestors).to include(Legate::Mcp::Error)
      expect(Legate::Mcp::RemoteToolError.ancestors).to include(Legate::Mcp::Error)
    end

    it 'DefinitionStore errors descend from Legate::DefinitionStore::Error' do
      expect(Legate::DefinitionStore::Error.ancestors).to include(Legate::Error)
      expect(Legate::DefinitionStore::StoreError.ancestors).to include(Legate::DefinitionStore::Error)
    end
  end

  describe Legate::ToolError do
    it 'stores a message' do
      err = Legate::ToolError.new('something broke')
      expect(err.message).to eq('something broke')
      expect(err.cause).to be_nil
    end

    it 'wraps an original cause exception' do
      original = RuntimeError.new('original problem')
      original.set_backtrace(caller)
      err = Legate::ToolError.new('wrapped', cause: original)
      expect(err.cause).to eq(original)
      expect(err.backtrace).to eq(original.backtrace)
    end
  end

  describe Legate::ToolHttpError do
    it 'stores a response object alongside the message' do
      response = double('response', status: 500, body: 'error')
      err = Legate::ToolHttpError.new('server error', response: response)
      expect(err.response).to eq(response)
      expect(err.message).to eq('server error')
    end

    it 'combines cause and response' do
      original = Timeout::Error.new('read timeout')
      response = double('response', status: 504)
      err = Legate::ToolHttpError.new('gateway timeout', response: response, cause: original)
      expect(err.response).to eq(response)
      expect(err.cause).to eq(original)
    end
  end

  describe Legate::Mcp::RemoteToolError do
    it 'stores code and data' do
      err = Legate::Mcp::RemoteToolError.new('tool failed', -32_000, { detail: 'info' })
      expect(err.message).to include('tool failed')
      expect(err.code).to eq(-32_000)
      expect(err.data).to eq({ detail: 'info' })
    end

    it 'formats to_s with code and data' do
      err = Legate::Mcp::RemoteToolError.new('bad request', -32_600, 'extra')
      str = err.to_s
      expect(str).to include('bad request')
      expect(str).to include('Code: -32600')
      expect(str).to include('Data: "extra"')
    end

    it 'formats to_s without code/data when absent' do
      err = Legate::Mcp::RemoteToolError.new('simple error')
      expect(err.to_s).to eq('simple error')
    end
  end

  describe 'error catching patterns' do
    it 'ToolArgumentError can be caught as ToolError' do
      expect {
        raise Legate::ToolArgumentError, 'bad arg'
      }.to raise_error(Legate::ToolError, 'bad arg')
    end

    it 'ToolCertificateError can be caught as ToolNetworkError or ToolError' do
      expect {
        raise Legate::ToolCertificateError, 'cert fail'
      }.to raise_error(Legate::ToolNetworkError)
    end

    it 'Mcp::ConnectionError can be caught as Mcp::Error or Legate::Error' do
      expect {
        raise Legate::Mcp::ConnectionError, 'disconnected'
      }.to raise_error(Legate::Mcp::Error)

      expect {
        raise Legate::Mcp::ConnectionError, 'disconnected'
      }.to raise_error(Legate::Error)
    end
  end
end
