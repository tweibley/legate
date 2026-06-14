# File: spec/legate/tools/webhook_tool_ssrf_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'legate/tools/webhook_tool'
require 'legate/tool_context'
require 'webmock/rspec'

RSpec.describe Legate::Tools::WebhookTool do
  let(:context) { instance_double('Legate::ToolContext') }
  let(:tool) { described_class.new }
  let(:payload) { { message: 'hello' } }

  around do |example|
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: false)

    example.run

    WebMock.reset!
    WebMock.disable!
  end

  before do
    allow(Legate.logger).to receive(:info)
    allow(Legate.logger).to receive(:debug)
    allow(Legate.logger).to receive(:error)
  end

  describe 'SSRF Protection' do
    it 'blocks requests to 127.0.0.1 (loopback)' do
      url = 'http://127.0.0.1:9292/webhook'

      expect {
        tool.execute({ url: url, payload: payload }, context: context)
      }.to raise_error(Legate::ToolArgumentError, /Security Error: Blocked access/)
    end

    it 'blocks requests to localhost' do
      url = 'http://localhost:9292/webhook'

      expect {
        tool.execute({ url: url, payload: payload }, context: context)
      }.to raise_error(Legate::ToolArgumentError)
    end

    it 'blocks requests to private IPs (192.168.x.x)' do
      url = 'http://192.168.1.1/admin'

      expect {
        tool.execute({ url: url, payload: payload }, context: context)
      }.to raise_error(Legate::ToolArgumentError, /Security Error: Blocked access/)
    end

    it 'blocks requests to private IPs (10.x.x.x)' do
      url = 'http://10.0.0.1/admin'

      expect {
        tool.execute({ url: url, payload: payload }, context: context)
      }.to raise_error(Legate::ToolArgumentError, /Security Error: Blocked access/)
    end

    it 'blocks requests to cloud metadata (169.254.169.254)' do
      url = 'http://169.254.169.254/latest/meta-data/'

      expect {
        tool.execute({ url: url, payload: payload }, context: context)
      }.to raise_error(Legate::ToolArgumentError, /Security Error: Blocked access/)
    end

    it 'blocks requests to 0.0.0.0/8 (this network)' do
      url = 'http://0.0.0.0/admin'

      expect {
        tool.execute({ url: url, payload: payload }, context: context)
      }.to raise_error(Legate::ToolArgumentError, /Security Error: Blocked access/)
    end

    it 'blocks requests to CGNAT range (100.64.0.0/10)' do
      url = 'http://100.64.0.1/admin'

      expect {
        tool.execute({ url: url, payload: payload }, context: context)
      }.to raise_error(Legate::ToolArgumentError, /Security Error: Blocked access/)
    end

    it 'allows requests to public IPs' do
      url = 'http://8.8.8.8/webhook'
      stub_request(:post, url).to_return(status: 200)

      result = tool.execute({ url: url, payload: payload }, context: context)
      expect(result[:status]).to eq(:success)
    end
  end

  describe 'DNS rebinding prevention' do
    it 'pins connection to the resolved IP' do
      # Simulate DNS resolving to a public IP
      a_record = double('A', address: double('addr', to_s: '203.0.113.50'))
      dns = instance_double(Resolv::DNS)
      allow(Resolv::DNS).to receive(:open).and_yield(dns)
      allow(dns).to receive(:timeouts=)
      allow(dns).to receive(:getresources)
        .with('safe.example.com', Resolv::DNS::Resource::IN::A)
        .and_return([a_record])
      allow(dns).to receive(:getresources)
        .with('safe.example.com', Resolv::DNS::Resource::IN::AAAA)
        .and_return([])

      # WebMock should see the request go to the resolved IP, not the hostname
      stub_request(:post, 'http://203.0.113.50/webhook')
        .with(headers: { 'Host' => 'safe.example.com' })
        .to_return(status: 200, body: 'OK')

      result = tool.execute({ url: 'http://safe.example.com/webhook', payload: payload }, context: context)
      expect(result[:status]).to eq(:success)
      expect(result[:result][:response_status]).to eq(200)
    end

    it 'blocks hostnames that resolve to private IPs' do
      a_record = double('A', address: double('addr', to_s: '10.0.0.1'))
      dns = instance_double(Resolv::DNS)
      allow(Resolv::DNS).to receive(:open).and_yield(dns)
      allow(dns).to receive(:timeouts=)
      allow(dns).to receive(:getresources)
        .with('evil.example.com', Resolv::DNS::Resource::IN::A)
        .and_return([a_record])
      allow(dns).to receive(:getresources)
        .with('evil.example.com', Resolv::DNS::Resource::IN::AAAA)
        .and_return([])

      expect {
        tool.execute({ url: 'http://evil.example.com/webhook', payload: payload }, context: context)
      }.to raise_error(Legate::ToolArgumentError, /Security Error: Blocked access.*10\.0\.0\.1/)
    end

    it 'raises on unresolvable hostnames' do
      dns = instance_double(Resolv::DNS)
      allow(Resolv::DNS).to receive(:open).and_yield(dns)
      allow(dns).to receive(:timeouts=)
      allow(dns).to receive(:getresources).and_return([])

      expect {
        tool.execute({ url: 'http://nonexistent.invalid/webhook', payload: payload }, context: context)
      }.to raise_error(Legate::ToolArgumentError, /Could not resolve hostname/)
    end
  end

  describe '#validate_url_security' do
    it 'returns the resolved IP for connection pinning' do
      ip = tool.send(:validate_url_security, '8.8.8.8')
      expect(ip).to eq('8.8.8.8')
    end

    it 'returns first resolved IP for hostnames' do
      a_record = double('A', address: double('addr', to_s: '203.0.113.1'))
      dns = instance_double(Resolv::DNS)
      allow(Resolv::DNS).to receive(:open).and_yield(dns)
      allow(dns).to receive(:timeouts=)
      allow(dns).to receive(:getresources)
        .with('public.example.com', Resolv::DNS::Resource::IN::A)
        .and_return([a_record])
      allow(dns).to receive(:getresources)
        .with('public.example.com', Resolv::DNS::Resource::IN::AAAA)
        .and_return([])

      ip = tool.send(:validate_url_security, 'public.example.com')
      expect(ip).to eq('203.0.113.1')
    end
  end
end
