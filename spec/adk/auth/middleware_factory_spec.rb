# frozen_string_literal: true

require 'spec_helper'

# Set test environment for OIDC discovery
ENV['RSPEC_ENV'] = 'test'
require 'adk/auth/middleware_factory'
require 'adk/auth/schemes/api_key'
require 'adk/auth/schemes/http_bearer'
require 'adk/auth/schemes/oauth2'
require 'adk/auth/schemes/openid_connect'
require 'adk/auth/schemes/service_account'
require 'adk/auth/token_store'

RSpec.describe ADK::Auth::MiddlewareFactory do
  # Create a mock SessionService that works with TokenStore
  let(:session_service) do
    Class.new do
      def initialize
        @store = {}
      end
      
      def save_scoped_state(scope, key, value)
        @store["#{scope}:#{key}"] = value
        true
      end
      
      def load_scoped_state(scope, key)
        @store["#{scope}:#{key}"]
      end
      
      def clear_scoped_state(scope, key)
        if key == '*'
          @store.keys.each do |k|
            @store.delete(k) if k.start_with?("#{scope}:")
          end
        else
          @store.delete("#{scope}:#{key}")
        end
        true
      end
    end.new
  end
  
  let(:token_store) { ADK::Auth::TokenStore.new(session_service) }
  let(:scheme) { ADK::Auth::Schemes::ApiKey.new }
  let(:credential) { ADK::Auth::Credential.new(auth_type: :api_key, api_key: 'test-api-key') }
  
  describe '.create' do
    it 'creates a middleware instance with the given scheme and credential' do
      middleware = described_class.create(
        scheme: scheme,
        credential: credential
      )
      
      expect(middleware).to be_a(ADK::Auth::ExconMiddleware)
    end
    
    it 'accepts optional parameters' do
      middleware = described_class.create(
        scheme: scheme,
        credential: credential,
        token_store: token_store,
        auto_retry: false,
        max_retries: 2,
        backoff_strategy: :exponential,
        backoff_factor: 0.5
      )
      
      expect(middleware).to be_a(ADK::Auth::ExconMiddleware)
    end
  end
  
  describe '.create_api_key' do
    it 'creates middleware for API key authentication' do
      middleware = described_class.create_api_key(
        api_key: 'test-api-key'
      )
      
      expect(middleware).to be_a(ADK::Auth::ExconMiddleware)
      
      # Verify that the middleware has the correct scheme and credential
      scheme = middleware.instance_variable_get(:@scheme)
      credential = middleware.instance_variable_get(:@credential)
      
      expect(scheme).to be_a(ADK::Auth::Schemes::ApiKey)
      
      expect(credential).to be_a(ADK::Auth::Credential)
      expect(credential.auth_type).to eq(:api_key)
      expect(credential[:api_key]).to eq('test-api-key')
    end
    
    it 'accepts location and name parameters' do
      middleware = described_class.create_api_key(
        api_key: 'test-api-key',
        location: 'query',
        name: 'api_key'
      )
      
      credential = middleware.instance_variable_get(:@credential)
      expect(credential[:location]).to eq('query')
      expect(credential[:name]).to eq('api_key')
    end
  end
  
  describe '.create_bearer' do
    it 'creates middleware for bearer token authentication' do
      middleware = described_class.create_bearer(
        token: 'test-token'
      )
      
      expect(middleware).to be_a(ADK::Auth::ExconMiddleware)
      
      # Verify that the middleware has the correct scheme and credential
      scheme = middleware.instance_variable_get(:@scheme)
      credential = middleware.instance_variable_get(:@credential)
      
      expect(scheme).to be_a(ADK::Auth::Schemes::HTTPBearer)
      
      expect(credential).to be_a(ADK::Auth::Credential)
      expect(credential.auth_type).to eq(:http_bearer)
      expect(credential[:bearer_token]).to eq('test-token')
    end
  end
  
  describe '.create_oauth2' do
    it 'creates middleware for OAuth2 authentication' do
      middleware = described_class.create_oauth2(
        client_id: 'test-client-id',
        client_secret: 'test-client-secret',
        authorization_url: 'https://example.com/auth',
        token_url: 'https://example.com/token',
        scopes: ['read', 'write']
      )
      
      expect(middleware).to be_a(ADK::Auth::ExconMiddleware)
      
      # Verify that the middleware has the correct scheme and credential
      scheme = middleware.instance_variable_get(:@scheme)
      credential = middleware.instance_variable_get(:@credential)
      
      expect(scheme).to be_a(ADK::Auth::Schemes::OAuth2)
      expect(scheme.token_url).to eq('https://example.com/token')
      expect(scheme.scopes).to eq(['read', 'write'])
      
      # We don't check the raw URL anymore as it contains dynamic state params
      expect(scheme.authorization_url).to include('https://example.com/auth')
      
      expect(credential).to be_a(ADK::Auth::Credential)
      expect(credential.auth_type).to eq(:oauth2)
      expect(credential[:client_id]).to eq('test-client-id')
      expect(credential[:client_secret]).to eq('test-client-secret')
    end
  end
  
  describe '.create_oidc' do
    it 'creates middleware for OIDC authentication using discovery' do
      middleware = described_class.create_oidc(
        client_id: 'test-client-id',
        client_secret: 'test-client-secret',
        discovery_url: 'https://example.com/.well-known/openid-configuration',
        authorization_url: 'https://example.com/auth',
        token_url: 'https://example.com/token'
      )
      
      expect(middleware).to be_a(ADK::Auth::ExconMiddleware)
      
      # Verify that the middleware has the correct scheme and credential
      scheme = middleware.instance_variable_get(:@scheme)
      credential = middleware.instance_variable_get(:@credential)
      
      expect(scheme).to be_a(ADK::Auth::Schemes::OIDC)
      expect(scheme.discovery_url).to eq('https://example.com/.well-known/openid-configuration')
      
      expect(credential).to be_a(ADK::Auth::Credential)
      expect(credential.auth_type).to eq(:oidc)
      expect(credential[:client_id]).to eq('test-client-id')
      expect(credential[:client_secret]).to eq('test-client-secret')
    end
    
    it 'creates middleware for OIDC authentication using direct URLs' do
      middleware = described_class.create_oidc(
        client_id: 'test-client-id',
        client_secret: 'test-client-secret',
        authorization_url: 'https://example.com/auth',
        token_url: 'https://example.com/token',
        userinfo_url: 'https://example.com/userinfo',
        jwks_url: 'https://example.com/jwks'
      )
      
      expect(middleware).to be_a(ADK::Auth::ExconMiddleware)
      
      # Verify that the middleware has the correct scheme and credential
      scheme = middleware.instance_variable_get(:@scheme)
      
      expect(scheme).to be_a(ADK::Auth::Schemes::OIDC)
      # Authorization URL contains dynamic state parameter, so just check that it includes the base URL
      expect(scheme.authorization_url).to include('https://example.com/auth')
      expect(scheme.token_url).to eq('https://example.com/token')
      expect(scheme.userinfo_url).to eq('https://example.com/userinfo')
      expect(scheme.jwks_url).to eq('https://example.com/jwks')
    end
  end
  
  describe '.create_service_account' do
    let(:service_account_key) do
      {
        'type' => 'service_account',
        'client_email' => 'test@example.com',
        'private_key' => 'test-private-key',
        'token_uri' => 'https://example.com/token'
      }.to_json
    end
    
    it 'creates middleware for service account authentication' do
      middleware = described_class.create_service_account(
        service_account_key: service_account_key,
        scopes: ['https://example.com/auth/cloud-platform']
      )
      
      expect(middleware).to be_a(ADK::Auth::ExconMiddleware)
      
      # Verify that the middleware has the correct scheme and credential
      scheme = middleware.instance_variable_get(:@scheme)
      credential = middleware.instance_variable_get(:@credential)
      
      expect(scheme).to be_a(ADK::Auth::Schemes::ServiceAccount)
      expect(scheme.token_url).to eq('https://example.com/token')
      expect(scheme.scopes).to eq(['https://example.com/auth/cloud-platform'])
      
      expect(credential).to be_a(ADK::Auth::Credential)
      expect(credential.auth_type).to eq(:service_account)
      expect(credential[:service_account_key]).to eq(service_account_key)
    end
    
    it 'accepts a hash for service account key' do
      key_hash = JSON.parse(service_account_key)
      
      middleware = described_class.create_service_account(
        service_account_key: key_hash,
        scopes: ['https://example.com/auth/cloud-platform']
      )
      
      expect(middleware).to be_a(ADK::Auth::ExconMiddleware)
      
      # Verify the credential has the key as JSON
      credential = middleware.instance_variable_get(:@credential)
      expect(credential[:service_account_key]).to be_a(String)
      
      # Should be able to parse it back to the original hash
      parsed = JSON.parse(credential[:service_account_key])
      expect(parsed).to eq(key_hash)
    end
    
    it 'raises an error for invalid JSON' do
      expect {
        described_class.create_service_account(
          service_account_key: 'not-valid-json',
          scopes: ['https://example.com/auth/cloud-platform']
        )
      }.to raise_error(ArgumentError, /Invalid service account key: not valid JSON/)
    end
  end
end 