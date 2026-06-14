# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'legate/web/app'

RSpec.describe 'CSRF Protection', type: :request do
  include Rack::Test::Methods

  def app
    Legate::Web::App.new
  end

  def csrf_token_from_session
    last_request.env['rack.session'][:csrf]
  end

  before do
    allow(Legate).to receive(:logger).and_return(instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil))
  end

  describe 'token generation' do
    it 'sets a CSRF token in the session on first request' do
      get '/'
      expect(last_request.env['rack.session'][:csrf]).to be_a(String)
      expect(last_request.env['rack.session'][:csrf].length).to be >= 32
    end

    it 'reuses the same token across requests in the same session' do
      get '/'
      token = csrf_token_from_session
      get '/'
      expect(csrf_token_from_session).to eq(token)
    end
  end

  describe 'safe methods bypass CSRF' do
    it 'allows GET requests without a token' do
      get '/'
      expect(last_response.status).not_to eq(403)
    end

    it 'allows HEAD requests without a token' do
      head '/'
      expect(last_response.status).not_to eq(403)
    end
  end

  describe 'state-changing methods require CSRF token' do
    it 'rejects POST without a token' do
      post '/agents', name: 'test'
      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Invalid CSRF token')
    end

    it 'rejects DELETE without a token' do
      delete '/agents/test'
      expect(last_response.status).to eq(403)
    end

    it 'rejects PUT without a token' do
      put '/agents/test/update/model'
      expect(last_response.status).to eq(403)
    end
  end

  describe 'valid CSRF token allows requests' do
    it 'accepts POST with token in X-CSRF-Token header' do
      get '/'
      token = csrf_token_from_session

      header 'X-CSRF-Token', token
      post '/agents', name: 'test'
      expect(last_response.status).not_to eq(403)
    end

    it 'accepts POST with token in authenticity_token param' do
      get '/'
      token = csrf_token_from_session

      post '/agents', name: 'test', authenticity_token: token
      expect(last_response.status).not_to eq(403)
    end
  end

  describe 'invalid CSRF token is rejected' do
    it 'rejects POST with wrong token' do
      get '/'

      header 'X-CSRF-Token', 'wrong-token'
      post '/agents', name: 'test'
      expect(last_response.status).to eq(403)
    end
  end

  describe 'no blanket prefix exemption' do
    # /api and /healthz are GET-only, so they are already exempt via safe
    # methods; there is intentionally no prefix that exempts state-changing
    # requests from CSRF (a blanket /api/ exemption would silently expose any
    # future non-GET /api route).
    it 'requires a token for a state-changing /api request' do
      post '/api/test'
      expect(last_response.status).to eq(403)
    end

    it 'allows GET /healthz without a token (safe method)' do
      get '/healthz'
      expect(last_response.status).not_to eq(403)
    end
  end
end
