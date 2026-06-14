# frozen_string_literal: true

require 'spec_helper'
require 'legate/tool_context'
require 'legate/auth/schemes/api_key'
require 'legate/auth/credential'
require 'legate/auth/manager'

RSpec.describe Legate::ToolContext do
  let(:session_id) { 'test-session-123' }
  let(:user_id) { 'test-user-456' }
  let(:app_name) { 'test-app' }
  let(:session_service) { instance_double('Legate::SessionService::InMemory') }
  let(:token_store) { instance_double('Legate::Auth::TokenStore') }
  let(:token_manager) { instance_double('Legate::Auth::TokenManager') }
  let(:auth_manager) { instance_double('Legate::Auth::Manager') }

  let(:api_key_scheme) { Legate::Auth::Schemes::ApiKey.new }
  let(:api_key_credential) do
    Legate::Auth::Credential.new(
      auth_type: :api_key,
      api_key: 'test-api-key-123'
    )
  end

  let(:context) do
    ctx = Legate::ToolContext.new(
      session_id: session_id,
      user_id: user_id,
      app_name: app_name,
      session_service: session_service
    )
    allow(ctx).to receive(:get_token_store).and_return(token_store)
    allow(ctx).to receive(:get_token_manager).and_return(token_manager)
    ctx
  end

  before do
    allow(Legate::Auth::Manager).to receive(:instance).and_return(auth_manager)
  end

  describe '#authenticate_request' do
    let(:request) { { url: 'https://api.example.com/v1/data', headers: {} } }

    it 'uses token manager when available' do
      expect(token_manager).to receive(:get_token).with(api_key_scheme, api_key_credential, force_refresh: false).and_return(nil)
      expect(api_key_scheme).to receive(:apply_to_request).with(request, api_key_credential).and_return(request.merge(headers: { 'X-API-Key' => 'test-api-key-123' }))

      result = context.authenticate_request(request, api_key_scheme, api_key_credential)
      expect(result[:headers]).to include('X-API-Key' => 'test-api-key-123')
    end
  end

  describe '#authentication_error?' do
    it 'identifies 401 responses as authentication errors' do
      response = { status: 401, body: 'Unauthorized' }
      expect(context.authentication_error?(response)).to be true
    end

    it 'identifies 403 responses as authentication errors' do
      response = { status: 403, body: 'Forbidden' }
      expect(context.authentication_error?(response)).to be true
    end

    it 'identifies responses with auth error messages' do
      response = { status: 400, body: 'Invalid API Key provided' }
      expect(context.authentication_error?(response)).to be true
    end

    it 'returns false for successful responses' do
      response = { status: 200, body: 'Success' }
      expect(context.authentication_error?(response)).to be false
    end
  end

  describe '#requires_authentication?' do
    it 'identifies API URLs as requiring authentication' do
      request = { url: 'https://api.example.com/v1/data' }
      expect(context.requires_authentication?(request)).to be true
    end

    it 'identifies non-GET methods as requiring authentication' do
      request = { url: 'https://example.com/data', method: 'POST' }
      expect(context.requires_authentication?(request)).to be true
    end

    it 'returns false for public URLs with GET method' do
      request = { url: 'https://example.com/public', method: 'GET' }
      expect(context.requires_authentication?(request)).to be false
    end
  end

  describe '#get_token' do
    let(:exchanged_credential) { instance_double('Legate::Auth::ExchangedCredential') }

    it 'uses token manager when available' do
      expect(token_manager).to receive(:get_token).with(api_key_scheme, api_key_credential, force_refresh: false).and_return(exchanged_credential)

      result = context.get_token(api_key_scheme, api_key_credential)
      expect(result).to eq(exchanged_credential)
    end

    it 'forces refresh when specified' do
      expect(token_manager).to receive(:get_token).with(api_key_scheme, api_key_credential, force_refresh: true).and_return(exchanged_credential)

      result = context.get_token(api_key_scheme, api_key_credential, force_refresh: true)
      expect(result).to eq(exchanged_credential)
    end
  end

  describe '#refresh_token' do
    let(:token) { instance_double('Legate::Auth::ExchangedCredential') }
    let(:refreshed_token) { instance_double('Legate::Auth::ExchangedCredential') }

    it 'uses token manager when available' do
      expect(token_manager).to receive(:refresh_token).with(api_key_scheme, api_key_credential, token).and_return(refreshed_token)

      result = context.refresh_token(api_key_scheme, api_key_credential, token)
      expect(result).to eq(refreshed_token)
    end
  end

  describe '#store_token' do
    let(:token) { instance_double('Legate::Auth::ExchangedCredential') }

    it 'stores token in token store' do
      cache_key = 'auth_token_key'
      expect(Legate::Auth::ToolIntegration).to receive(:generate_cache_key).with(api_key_scheme, api_key_credential).and_return(cache_key)
      expect(token_store).to receive(:store).with(cache_key, token).and_return(true)

      result = context.store_token(api_key_scheme, api_key_credential, token)
      expect(result).to be true
    end
  end

  describe '#clear_token' do
    it 'clears token from token store' do
      cache_key = 'auth_token_key'
      expect(Legate::Auth::ToolIntegration).to receive(:generate_cache_key).with(api_key_scheme, api_key_credential).and_return(cache_key)
      expect(token_store).to receive(:clear).with(cache_key).and_return(true)

      result = context.clear_token(api_key_scheme, api_key_credential)
      expect(result).to be true
    end
  end

  describe '#revoke_token' do
    let(:token) { instance_double('Legate::Auth::ExchangedCredential') }

    it 'uses token manager when available' do
      expect(token_manager).to receive(:revoke_token).with(api_key_scheme, api_key_credential, token).and_return(true)

      result = context.revoke_token(api_key_scheme, api_key_credential, token)
      expect(result).to be true
    end
  end

  describe '#handle_request_auth' do
    let(:request) { { url: 'https://api.example.com/v1/data', headers: {} } }

    it 'automatically applies authentication when needed' do
      expect(context).to receive(:requires_authentication?).with(request).and_return(true)
      expect(auth_manager).to receive(:find_scheme_and_credential).with(
        url: 'https://api.example.com/v1/data',
        scheme_type: nil,
        credential_name: nil
      ).and_return([api_key_scheme, api_key_credential])

      expect(context).to receive(:authenticate_request).with(request, api_key_scheme, api_key_credential).and_return(
        request.merge(headers: { 'X-API-Key' => 'test-api-key-123' })
      )

      result = context.handle_request_auth(request)
      expect(result[:headers]).to include('X-API-Key' => 'test-api-key-123')
    end

    it 'respects provided options' do
      expect(context).to receive(:requires_authentication?).with(request).and_return(true)
      expect(auth_manager).to receive(:find_scheme_and_credential).with(
        url: 'https://api.example.com/v1/data',
        scheme_type: :api_key,
        credential_name: :my_api_key
      ).and_return([api_key_scheme, api_key_credential])

      expect(context).to receive(:authenticate_request).with(request, api_key_scheme, api_key_credential).and_return(
        request.merge(headers: { 'X-API-Key' => 'test-api-key-123' })
      )

      result = context.handle_request_auth(request, scheme_type: :api_key, credential_name: :my_api_key)
      expect(result[:headers]).to include('X-API-Key' => 'test-api-key-123')
    end

    it 'returns original request when authentication not needed' do
      expect(context).to receive(:requires_authentication?).with(request).and_return(false)

      result = context.handle_request_auth(request)
      expect(result).to eq(request)
    end

    it 'returns original request when no authentication found' do
      expect(context).to receive(:requires_authentication?).with(request).and_return(true)
      expect(auth_manager).to receive(:find_scheme_and_credential).and_return(nil)

      result = context.handle_request_auth(request)
      expect(result).to eq(request)
    end
  end
end
