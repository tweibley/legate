# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'adk/web/app'

RSpec.describe ADK::Web::App do
  include Rack::Test::Methods

  def app
    ADK::Web::App
  end

  # Suppress errors during tests if they occur (like template missing)
  # But we use /healthz so it should be fine.

  describe 'Security Headers' do
    it 'sets standard security headers on HTTP requests' do
      get '/healthz'

      expect(last_response.headers['X-Content-Type-Options']).to eq('nosniff')
      expect(last_response.headers['X-Frame-Options']).to eq('DENY')
      expect(last_response.headers['X-XSS-Protection']).to eq('1; mode=block')
      expect(last_response.headers['Referrer-Policy']).to eq('strict-origin-when-cross-origin')
      # HSTS should NOT be set on non-SSL
      expect(last_response.headers['Strict-Transport-Security']).to be_nil
    end

    it 'sets HSTS header on HTTPS requests' do
      get '/healthz', {}, { 'HTTPS' => 'on' }

      expect(last_response.headers['Strict-Transport-Security']).to eq('max-age=31536000; includeSubDomains')
    end
  end
end
