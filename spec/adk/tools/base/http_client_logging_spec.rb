# frozen_string_literal: true

require 'spec_helper'
require 'adk/tools/base/http_client'
require 'webmock/rspec'

class DummyLoggingTool
  include ADK::Tools::Base::HttpClient

  def initialize(base_url:)
    setup_http_client(base_url: base_url)
  end
end

RSpec.describe ADK::Tools::Base::HttpClient do
  let(:base_url) { 'https://api.example.com/' }
  let(:tool) { DummyLoggingTool.new(base_url: base_url) }
  let(:logger_output) { StringIO.new }

  around do |example|
    # Capture logs
    original_log_device = ADK.logger.instance_variable_get(:@logdev)&.dev
    original_level = ADK.logger.level

    # Set up capture
    ADK.logger.level = Logger::DEBUG
    logdev = ADK.logger.instance_variable_get(:@logdev)
    logdev&.instance_variable_set(:@dev, logger_output)

    example.run

    # Restore
    ADK.logger.level = original_level
    logdev&.instance_variable_set(:@dev, original_log_device)
  end

  it 'redacts sensitive query parameters in URL string at INFO level' do
    stub_request(:get, 'https://api.example.com/resource?api_key=secret_in_url').to_return(status: 200)

    tool.http_get('resource?api_key=secret_in_url')

    log_content = logger_output.string
    # Expect encoded [REDACTED] or decoded, depending on implementation detail.
    # URI.to_s usually returns encoded URL.
    expect(log_content).to include('api_key=%5BREDACTED%5D').or include('api_key=[REDACTED]')
    expect(log_content).not_to include('secret_in_url')
  end

  it 'redacts sensitive query parameters in Hash at DEBUG level' do
    stub_request(:get, 'https://api.example.com/resource?api_key=secret_in_hash').to_return(status: 200)

    tool.http_get('resource', query: { api_key: 'secret_in_hash' })

    log_content = logger_output.string
    expect(log_content).to include('[REDACTED]')
    expect(log_content).not_to include('secret_in_hash')
  end

  it 'redacts sensitive headers at DEBUG level' do
    stub_request(:get, 'https://api.example.com/resource').to_return(status: 200)

    tool.http_get('resource', headers: { 'Authorization' => 'Bearer secret_token' })

    log_content = logger_output.string
    expect(log_content).to include('[REDACTED]')
    expect(log_content).not_to include('secret_token')
  end
end
