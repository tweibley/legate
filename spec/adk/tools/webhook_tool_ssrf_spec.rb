# File: spec/adk/tools/webhook_tool_ssrf_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/tools/webhook_tool'
require 'adk/tool_context'
require 'webmock/rspec'
require 'adk/errors'

RSpec.describe ADK::Tools::WebhookTool do
  let(:context) { instance_double('ADK::ToolContext') }
  let(:tool) { described_class.new }
  let(:payload) { { message: 'hello' } }

  before do
    allow(ADK.logger).to receive(:info)
    allow(ADK.logger).to receive(:debug)
    allow(ADK.logger).to receive(:error)
  end

  describe 'SSRF Protection' do
    it 'blocks requests to localhost' do
      url = 'http://localhost:9292/webhook'
      # No stub needed because it should fail before request

      expect {
        tool.execute({ url: url, payload: payload }, context: context)
      }.to raise_error(ADK::ToolSecurityError, /Security Error: Blocked access/)
    end

    it 'blocks requests to private IPs' do
      url = 'http://192.168.1.1/admin'

      expect {
        tool.execute({ url: url, payload: payload }, context: context)
      }.to raise_error(ADK::ToolSecurityError, /Security Error: Blocked access/)
    end

    it 'blocks requests to cloud metadata' do
      url = 'http://169.254.169.254/latest/meta-data/'

      expect {
        tool.execute({ url: url, payload: payload }, context: context)
      }.to raise_error(ADK::ToolSecurityError, /Security Error: Blocked access/)
    end

    it 'allows requests to public IPs' do
      url = 'http://8.8.8.8/webhook' # Google DNS IP (public)
      stub_request(:post, url).to_return(status: 200)

      result = tool.execute({ url: url, payload: payload }, context: context)
      expect(result[:status]).to eq(:success)
    end
  end
end
