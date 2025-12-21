# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'adk/web/app'

RSpec.describe ADK::Web::App do
  include Rack::Test::Methods

  def app
    ADK::Web::App
  end

  describe 'Security Headers' do
    it 'sets X-Frame-Options to DENY' do
      get '/'
      expect(last_response.headers['X-Frame-Options']).to eq('DENY')
    end

    it 'sets X-Content-Type-Options to nosniff' do
      get '/'
      expect(last_response.headers['X-Content-Type-Options']).to eq('nosniff')
    end

    it 'sets X-XSS-Protection to 1; mode=block' do
      get '/'
      expect(last_response.headers['X-XSS-Protection']).to eq('1; mode=block')
    end

    it 'sets Referrer-Policy to strict-origin-when-cross-origin' do
      get '/'
      expect(last_response.headers['Referrer-Policy']).to eq('strict-origin-when-cross-origin')
    end
  end
end
