# File: spec/adk/auth/tool_integration_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/scheme'
require 'adk/auth/error'
require 'adk/auth/tool_integration'
require 'adk/auth/credential'
require 'adk/auth/exchanged_credential'
require 'adk/auth/schemes/api_key'
require 'adk/auth/schemes/http_bearer'

RSpec.describe ADK::Auth::ToolIntegration do
  describe '.apply_authentication' do
    let(:request) { { url: 'https://api.example.com/data' } }
    let(:credential) { ADK::Auth::Credential.new(auth_type: :api_key, api_key: 'test-api-key') }
    let(:scheme) { ADK::Auth::Schemes::ApiKey.new }
    
    it 'applies the authentication to the request' do
      result = described_class.apply_authentication(request, scheme, credential)
      
      expect(result[:headers]).to include('X-API-Key' => 'test-api-key')
    end
    
    it 'raises an error for an invalid request' do
      expect {
        described_class.apply_authentication('not-a-hash', scheme, credential)
      }.to raise_error(ArgumentError)
    end
    
    it 'raises an error for an invalid scheme' do
      expect {
        described_class.apply_authentication(request, 'not-a-scheme', credential)
      }.to raise_error(ArgumentError)
    end
    
    context 'with a token store' do
      let(:token_store) { instance_double('ADK::Auth::TokenStore') }
      let(:exchanged_credential) { instance_double('ADK::Auth::ExchangedCredential', expired?: false) }
      
      it 'uses cached tokens if available' do
        allow(token_store).to receive(:get).and_return(exchanged_credential)
        allow(scheme).to receive(:apply_to_request).and_return({headers: {'X-Api-Key' => 'cached-key'}})
        
        result = described_class.apply_authentication(request, scheme, credential, token_store)
        
        expect(result).to eq({headers: {'X-Api-Key' => 'cached-key'}})
      end
      
      it 'refreshes expired tokens if supported' do
        expired_token = instance_double('ADK::Auth::ExchangedCredential', expired?: true)
        refreshed_token = instance_double('ADK::Auth::ExchangedCredential', expired?: false)
        
        allow(token_store).to receive(:get).and_return(expired_token)
        allow(token_store).to receive(:store)
        allow(scheme).to receive(:supports_refresh?).and_return(true)
        allow(scheme).to receive(:refresh_token).and_return(refreshed_token)
        allow(scheme).to receive(:apply_to_request).and_return({headers: {'X-Api-Key' => 'refreshed-key'}})
        
        result = described_class.apply_authentication(request, scheme, credential, token_store)
        
        expect(token_store).to have_received(:store)
        expect(result).to eq({headers: {'X-Api-Key' => 'refreshed-key'}})
      end
    end
  end
  
  describe '.authentication_error?' do
    it 'returns true for 401 status code' do
      response = { status: 401 }
      expect(described_class.authentication_error?(response)).to be true
    end
    
    it 'returns true for 403 status code' do
      response = { status: 403 }
      expect(described_class.authentication_error?(response)).to be true
    end
    
    it 'returns true for error messages in body text' do
      response = { body: 'Authentication failed: Invalid token' }
      expect(described_class.authentication_error?(response)).to be true
    end
    
    it 'returns true for error messages in JSON body' do
      response = { body: '{"error": "unauthorized"}' }
      expect(described_class.authentication_error?(response)).to be true
    end
    
    it 'returns false for successful responses' do
      response = { status: 200, body: 'Success' }
      expect(described_class.authentication_error?(response)).to be false
    end
    
    it 'returns false for non-authentication errors' do
      response = { status: 500, body: 'Internal server error' }
      expect(described_class.authentication_error?(response)).to be false
    end
  end
  
  describe '.generate_cache_key' do
    it 'generates a unique key for API key schemes' do
      scheme = ADK::Auth::Schemes::ApiKey.new
      credential = ADK::Auth::Credential.new(auth_type: :api_key, api_key: 'test-api-key')
      
      key = described_class.generate_cache_key(scheme, credential)
      
      expect(key).to be_a(String)
      expect(key).to start_with('auth_')
    end
    
    it 'generates a unique key for HTTP Bearer schemes' do
      scheme = ADK::Auth::Schemes::HTTPBearer.new
      credential = ADK::Auth::Credential.new(auth_type: :http_bearer, bearer_token: 'test-token')
      
      key = described_class.generate_cache_key(scheme, credential)
      
      expect(key).to be_a(String)
      expect(key).to start_with('auth_')
    end
    
    it 'generates different keys for different schemes' do
      api_key_scheme = ADK::Auth::Schemes::ApiKey.new
              bearer_scheme = ADK::Auth::Schemes::HTTPBearer.new
      api_key_credential = ADK::Auth::Credential.new(auth_type: :api_key, api_key: 'test-api-key')
      bearer_credential = ADK::Auth::Credential.new(auth_type: :http_bearer, bearer_token: 'test-token')
      
      key1 = described_class.generate_cache_key(api_key_scheme, api_key_credential)
      key2 = described_class.generate_cache_key(bearer_scheme, bearer_credential)
      
      expect(key1).not_to eq(key2)
    end
  end
  
  describe '.requires_authentication?' do
    it 'returns true for API paths' do
      request = { url: 'https://example.com/api/resource' }
      expect(described_class.requires_authentication?(request)).to be true
    end
    
    it 'returns true for versioned API paths' do
      request = { url: 'https://example.com/v1/resource' }
      expect(described_class.requires_authentication?(request)).to be true
    end
    
    it 'returns true for secure paths' do
      request = { url: 'https://example.com/secure/dashboard' }
      expect(described_class.requires_authentication?(request)).to be true
    end
    
    it 'returns true for JSON content types' do
      request = { headers: { 'Content-Type' => 'application/json' } }
      expect(described_class.requires_authentication?(request)).to be true
    end
    
    it 'returns true for non-GET methods' do
      request = { method: 'POST', url: 'https://example.com/resource' }
      expect(described_class.requires_authentication?(request)).to be true
    end
    
    it 'returns false for public paths with GET method' do
      request = { method: 'GET', url: 'https://example.com/public/resource' }
      expect(described_class.requires_authentication?(request)).to be false
    end
  end
end 