# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'adk/web/app'

RSpec.describe ADK::Web::App do
  include Rack::Test::Methods

  def app
    ADK::Web::App.new
  end

  before do
    # Suppress logging during tests
    allow(ADK).to receive(:logger).and_return(instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil))
  end

  describe 'Security Headers' do
    it 'sets security headers on response' do
      get '/'

      # Expect strong security headers
      expect(last_response.headers['X-Frame-Options']).to eq('SAMEORIGIN')
      expect(last_response.headers['X-Content-Type-Options']).to eq('nosniff')
      expect(last_response.headers['X-XSS-Protection']).to eq('1; mode=block')
      expect(last_response.headers['Referrer-Policy']).to eq('strict-origin-when-cross-origin')
    end
  end
end
