# frozen_string_literal: true

require 'spec_helper'
require 'adk/tools/base/http_client'
require 'adk/errors'

class VulnerableHttpTool
  include ADK::Tools::Base::HttpClient

  def initialize
    # Setup with a dummy base url
    setup_http_client(base_url: 'https://example.com')
  end

  def unsafe_get(url)
    # Using absolute URL which currently bypasses checks in HttpClient
    http_get(url)
  end
end

RSpec.describe ADK::Tools::Base::HttpClient do
  let(:tool) { VulnerableHttpTool.new }

  describe 'SSRF Protection' do
    # We expect these to fail until we implement the protection

    it 'raises error when accessing localhost' do
      expect {
        tool.unsafe_get('http://localhost:3000/secret')
      }.to raise_error(ADK::ToolSecurityError, /Security Error: Blocked access/)
    end

    it 'raises error when accessing private IP' do
      expect {
        tool.unsafe_get('http://192.168.1.5/admin')
      }.to raise_error(ADK::ToolSecurityError, /Security Error: Blocked access/)
    end

    it 'raises error when accessing cloud metadata' do
      expect {
        tool.unsafe_get('http://169.254.169.254/latest/meta-data/')
      }.to raise_error(ADK::ToolSecurityError, /Security Error: Blocked access/)
    end
  end
end
