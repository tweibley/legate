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
    it 'sets X-Content-Type-Options' do
      get '/'
      expect(last_response.headers['X-Content-Type-Options']).to eq('nosniff')
    end

    it 'sets X-Frame-Options' do
      get '/'
      expect(last_response.headers['X-Frame-Options']).to eq('DENY')
    end

    it 'sets X-XSS-Protection' do
      get '/'
      expect(last_response.headers['X-XSS-Protection']).to eq('1; mode=block')
    end

    it 'sets Referrer-Policy' do
      get '/'
      expect(last_response.headers['Referrer-Policy']).to eq('strict-origin-when-cross-origin')
    end

    context 'over HTTP' do
      it 'does not set Strict-Transport-Security' do
        get '/'
        expect(last_response.headers['Strict-Transport-Security']).to be_nil
      end
    end

    context 'over HTTPS' do
      it 'sets Strict-Transport-Security' do
        # Simulate HTTPS request
        get '/', {}, { 'HTTPS' => 'on' }
        expect(last_response.headers['Strict-Transport-Security']).to include('max-age=31536000')
      end
    end
  end
end
