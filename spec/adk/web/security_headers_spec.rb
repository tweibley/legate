# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'adk/web/app'

RSpec.describe 'Security Headers' do
  include Rack::Test::Methods

  def app
    ADK::Web::App.new
  end

  before do
    # Mock Redis to avoid connection errors during App initialization
    redis_mock = instance_double(Redis, ping: true).as_null_object
    allow(redis_mock).to receive(:hgetall).and_return({})
    allow(redis_mock).to receive(:get).and_return(nil)
    allow(redis_mock).to receive(:smembers).and_return([])
    allow(redis_mock).to receive(:scan_each).and_return([].to_enum)
    allow(Redis).to receive(:new).and_return(redis_mock)

    # Ensure ADK.config returns a valid config object with session_service
    allow(ADK.config).to receive(:session_service).and_return(ADK::SessionService::InMemory.new)
  end

  it 'sets the correct security headers on responses' do
    get '/'

    expect(last_response).to be_ok

    expect(last_response.headers['X-Frame-Options']).to eq('DENY')
    expect(last_response.headers['X-Content-Type-Options']).to eq('nosniff')
    expect(last_response.headers['X-XSS-Protection']).to eq('1; mode=block')
    expect(last_response.headers['Referrer-Policy']).to eq('strict-origin-when-cross-origin')
  end
end
