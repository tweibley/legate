# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/http_client_utils'
require 'adk/auth/schemes/api_key'
require 'adk/auth/schemes/http_bearer'
require 'adk/auth/token_store'
require 'excon'

RSpec.describe ADK::Auth::HttpClientUtils do
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
  
  let(:api_key_scheme) { ADK::Auth::Schemes::ApiKey.new }
  let(:api_key_credential) { ADK::Auth::Credential.new(auth_type: :api_key, api_key: 'test-api-key') }
  let(:token_store) { ADK::Auth::TokenStore.new(session_service) }
  
  describe '.configure_connection' do
    let(:connection) { Excon.new('https://example.com') }
    
    it 'adds middleware to the connection' do
      result = described_class.configure_connection(
        connection,
        scheme: api_key_scheme,
        credential: api_key_credential,
        session_service: session_service
      )
      
      expect(result).to eq(connection)
      expect(connection.data[:middlewares]).to include(ADK::Auth::ExconMiddleware)
      expect(connection.data[:auth_middleware]).to be_a(ADK::Auth::ExconMiddleware)
    end
    
    it 'accepts additional options for the middleware' do
      result = described_class.configure_connection(
        connection,
        scheme: api_key_scheme,
        credential: api_key_credential,
        token_store: token_store,
        auto_retry: false,
        max_retries: 2
      )
      
      expect(result).to eq(connection)
      
      middleware = connection.data[:auth_middleware]
      expect(middleware.instance_variable_get(:@token_store)).to eq(token_store)
      expect(middleware.instance_variable_get(:@auto_retry)).to eq(false)
      expect(middleware.instance_variable_get(:@max_retries)).to eq(2)
    end
  end
  
  describe '.create_connection' do
    it 'creates a new connection with middleware' do
      connection = described_class.create_connection(
        'https://example.com',
        scheme: api_key_scheme,
        credential: api_key_credential,
        session_service: session_service
      )
      
      expect(connection).to be_a(Excon::Connection)
      expect(connection.data[:middlewares]).to include(ADK::Auth::ExconMiddleware)
      expect(connection.data[:auth_middleware]).to be_a(ADK::Auth::ExconMiddleware)
      expect(connection.data[:hostname]).to eq('example.com')
    end
    
    it 'passes connection options to Excon' do
      connection = described_class.create_connection(
        'https://example.com',
        scheme: api_key_scheme,
        credential: api_key_credential,
        connect_timeout: 10,
        read_timeout: 20,
        session_service: session_service
      )
      
      expect(connection.data[:connect_timeout]).to eq(10)
      expect(connection.data[:read_timeout]).to eq(20)
    end
  end
  
  describe '.create_api_key_connection' do
    it 'creates a connection with API key authentication' do
      connection = described_class.create_api_key_connection(
        'https://example.com',
        api_key: 'test-api-key',
        session_service: session_service
      )
      
      expect(connection).to be_a(Excon::Connection)
      expect(connection.data[:middlewares]).to include(ADK::Auth::ExconMiddleware)
      
      middleware = connection.data[:auth_middleware]
      scheme = middleware.instance_variable_get(:@scheme)
      credential = middleware.instance_variable_get(:@credential)
      
      expect(scheme).to be_a(ADK::Auth::Schemes::ApiKey)
      
      expect(credential).to be_a(ADK::Auth::Credential)
      expect(credential.auth_type).to eq(:api_key)
      expect(credential[:api_key]).to eq('test-api-key')
    end
  end
  
  describe '.create_bearer_connection' do
    it 'creates a connection with bearer token authentication' do
      connection = described_class.create_bearer_connection(
        'https://example.com',
        token: 'test-token',
        session_service: session_service
      )
      
      expect(connection).to be_a(Excon::Connection)
      expect(connection.data[:middlewares]).to include(ADK::Auth::ExconMiddleware)
      
      middleware = connection.data[:auth_middleware]
      scheme = middleware.instance_variable_get(:@scheme)
      credential = middleware.instance_variable_get(:@credential)
      
      expect(scheme).to be_a(ADK::Auth::Schemes::HttpBearer)
      
      expect(credential).to be_a(ADK::Auth::Credential)
      expect(credential.auth_type).to eq(:http_bearer)
      expect(credential[:bearer_token]).to eq('test-token')
    end
  end
  
  describe '.create_service_account_connection' do
    let(:service_account_key) do
      {
        'type' => 'service_account',
        'client_email' => 'test@example.com',
        'private_key' => 'test-private-key',
        'token_uri' => 'https://example.com/token'
      }.to_json
    end
    
    it 'creates a connection with service account authentication' do
      connection = described_class.create_service_account_connection(
        'https://example.com',
        service_account_key: service_account_key,
        scopes: ['https://example.com/auth/cloud-platform']
      )
      
      expect(connection).to be_a(Excon::Connection)
      expect(connection.data[:middlewares]).to include(ADK::Auth::ExconMiddleware)
      
      middleware = connection.data[:auth_middleware]
      scheme = middleware.instance_variable_get(:@scheme)
      credential = middleware.instance_variable_get(:@credential)
      
      expect(scheme).to be_a(ADK::Auth::Schemes::ServiceAccount)
      expect(scheme.scopes).to eq(['https://example.com/auth/cloud-platform'])
      
      expect(credential).to be_a(ADK::Auth::Credential)
      expect(credential.auth_type).to eq(:service_account)
    end
  end
  
  describe '.authenticate_request' do
    let(:request) { { url: 'https://example.com/api/data', headers: {} } }
    
    it 'applies authentication to a request' do
      authenticated_request = described_class.authenticate_request(
        request,
        scheme: api_key_scheme,
        credential: api_key_credential
      )
      
      expect(authenticated_request[:headers]).to include('X-API-Key' => 'test-api-key')
    end
    
    it 'accepts token_store and token_manager options' do
      authenticated_request = described_class.authenticate_request(
        request,
        scheme: api_key_scheme,
        credential: api_key_credential,
        token_store: token_store
      )
      
      expect(authenticated_request[:headers]).to include('X-API-Key' => 'test-api-key')
    end
  end
  
  describe '.extract_middleware_options' do
    it 'extracts middleware options from a combined options hash' do
      options = {
        token_store: token_store,
        auto_retry: false,
        max_retries: 2,
        backoff_strategy: :exponential,
        backoff_factor: 0.5,
        connect_timeout: 10,
        read_timeout: 20
      }
      
      middleware_options = described_class.send(:extract_middleware_options, options)
      
      expect(middleware_options).to include(
        token_store: token_store,
        auto_retry: false,
        max_retries: 2,
        backoff_strategy: :exponential,
        backoff_factor: 0.5
      )
      
      expect(middleware_options).not_to include(
        connect_timeout: 10,
        read_timeout: 20
      )
    end
  end
end 