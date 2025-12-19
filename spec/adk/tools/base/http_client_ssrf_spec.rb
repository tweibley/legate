# frozen_string_literal: true

# spec/adk/tools/base/http_client_ssrf_spec.rb
require 'spec_helper'
require 'adk/tools/base/http_client'
require 'resolv'

RSpec.describe ADK::Tools::Base::HttpClient do
  let(:tool_class) do
    Class.new(ADK::Tool) do
      include ADK::Tools::Base::HttpClient

      self.explicit_tool_name = :ssrf_test_tool
      tool_description 'A tool for testing SSRF'

      def initialize(base_url: nil)
        super()
        # Assuming parameters validation happens elsewhere or arguments are passed directly
        return unless base_url

        setup_http_client(base_url: base_url)
      end

      def call_get(path)
        http_get(path)
      end
    end
  end

  # Helper to mock DNS resolution
  def mock_dns(hostname, ip)
    allow(Resolv).to receive(:getaddresses).with(hostname).and_return([ip])
    # Also handle Resolv.getaddress which returns string
    allow(Resolv).to receive(:getaddress).with(hostname).and_return(ip)
  end

  before do
    # Ensure WebMock doesn't block local requests if we were making them,
    # but we are mocking DNS and logic mainly.
    # However, if the code tries to connect, WebMock will catch it.
  end

  describe 'SSRF Protection' do
    context 'setup_http_client' do
      it 'allows public IPs' do
        mock_dns('8.8.8.8', '8.8.8.8')
        mock_dns('google.com', '142.250.190.46')

        expect {
          tool_class.new(base_url: 'http://8.8.8.8')
        }.not_to raise_error

        expect {
          tool_class.new(base_url: 'http://google.com')
        }.not_to raise_error
      end

      it 'blocks loopback IPs (127.0.0.1)' do
        mock_dns('127.0.0.1', '127.0.0.1')
        expect {
          tool_class.new(base_url: 'http://127.0.0.1')
        }.to raise_error(ADK::ToolSecurityError, /SSRF protection/)
      end

      it 'blocks private IPs (192.168.x.x)' do
        mock_dns('192.168.1.1', '192.168.1.1')
        expect {
          tool_class.new(base_url: 'http://192.168.1.1')
        }.to raise_error(ADK::ToolSecurityError, /SSRF protection/)
      end

      it 'blocks private IPs (10.x.x.x)' do
        mock_dns('10.0.0.5', '10.0.0.5')
        expect {
          tool_class.new(base_url: 'http://10.0.0.5')
        }.to raise_error(ADK::ToolSecurityError, /SSRF protection/)
      end

      it 'blocks localhost' do
        mock_dns('localhost', '127.0.0.1')
        expect {
          tool_class.new(base_url: 'http://localhost')
        }.to raise_error(ADK::ToolSecurityError, /SSRF protection/)
      end

      it 'blocks AWS metadata IP (169.254.169.254)' do
        mock_dns('169.254.169.254', '169.254.169.254')
        expect {
          tool_class.new(base_url: 'http://169.254.169.254')
        }.to raise_error(ADK::ToolSecurityError, /SSRF protection/)
      end
    end

    context 'make_request with absolute URL' do
      let(:tool) do
        # We need to stub setup to bypass SSRF check if we use a private IP in base_url for testing make_request logic separately?
        # But here we use a public base_url.
        mock_dns('example.com', '93.184.216.34')
        tool_class.new(base_url: 'http://example.com')
      end

      it 'blocks absolute URLs pointing to private IPs' do
        mock_dns('10.0.0.1', '10.0.0.1')
        expect {
          tool.call_get('http://10.0.0.1/secret')
        }.to raise_error(ADK::ToolSecurityError, /SSRF protection/)
      end

      it 'blocks absolute URLs pointing to localhost' do
        mock_dns('localhost', '127.0.0.1')
        expect {
          tool.call_get('http://localhost/secret')
        }.to raise_error(ADK::ToolSecurityError, /SSRF protection/)
      end
    end
  end
end
