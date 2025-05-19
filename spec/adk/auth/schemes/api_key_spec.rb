# File: spec/adk/auth/schemes/api_key_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/schemes/api_key'
require 'adk/auth/credential'

RSpec.describe ADK::Auth::Schemes::APIKey do
  describe '#initialize' do
    it 'creates a new API key scheme with default values' do
      scheme = described_class.new
      
      expect(scheme.location).to eq(:header)
      expect(scheme.name).to eq('X-Api-Key')
    end
    
    it 'accepts custom location and name' do
      scheme = described_class.new(location: :query, name: 'api_key')
      
      expect(scheme.location).to eq(:query)
      expect(scheme.name).to eq('api_key')
    end
    
    it 'raises an error for invalid location' do
      expect {
        described_class.new(location: :invalid)
      }.to raise_error(ADK::Auth::SchemeValidationError)
    end
  end
  
  describe '#scheme_type' do
    it 'returns :api_key' do
      scheme = described_class.new
      expect(scheme.scheme_type).to eq(:api_key)
    end
  end
  
  describe '#apply_to_request' do
    let(:credential) { ADK::Auth::Credential.new(auth_type: :api_key, api_key: 'test-api-key') }
    
    context 'with header location' do
      let(:scheme) { described_class.new(location: :header, name: 'API-Key') }
      
      it 'adds the API key to the request headers' do
        request = {}
        
        result = scheme.apply_to_request(request, credential)
        
        expect(result[:headers]).to include('API-Key' => 'test-api-key')
      end
      
      it 'preserves existing headers' do
        request = { headers: { 'Content-Type' => 'application/json' } }
        
        result = scheme.apply_to_request(request, credential)
        
        expect(result[:headers]).to include(
          'API-Key' => 'test-api-key',
          'Content-Type' => 'application/json'
        )
      end
      
      it 'applies a prefix if configured' do
        scheme_with_prefix = described_class.new(location: :header, name: 'API-Key', prefix: 'Key ')
        
        request = {}
        result = scheme_with_prefix.apply_to_request(request, credential)
        
        expect(result[:headers]).to include('API-Key' => 'Key test-api-key')
      end
    end
    
    context 'with query location' do
      let(:scheme) { described_class.new(location: :query, name: 'api_key') }
      
      it 'adds the API key to the query parameters' do
        request = {}
        
        result = scheme.apply_to_request(request, credential)
        
        expect(result[:query]).to include('api_key' => 'test-api-key')
      end
      
      it 'preserves existing query parameters' do
        request = { query: { 'version' => '1.0' } }
        
        result = scheme.apply_to_request(request, credential)
        
        expect(result[:query]).to include(
          'api_key' => 'test-api-key',
          'version' => '1.0'
        )
      end
    end
    
    context 'with cookie location' do
      let(:scheme) { described_class.new(location: :cookie, name: 'api_key') }
      
      it 'adds the API key to the cookie header' do
        request = {}
        
        result = scheme.apply_to_request(request, credential)
        
        expect(result[:headers]['Cookie']).to eq('api_key=test-api-key')
      end
      
      it 'appends to existing cookies' do
        request = { headers: { 'Cookie' => 'session=abc123' } }
        
        result = scheme.apply_to_request(request, credential)
        
        expect(result[:headers]['Cookie']).to eq('session=abc123; api_key=test-api-key')
      end
    end
    
    it 'raises an error if the credential is missing the API key' do
      scheme = described_class.new
      credential_without_key = ADK::Auth::Credential.new(auth_type: :api_key)
      
      expect {
        scheme.apply_to_request({}, credential_without_key)
      }.to raise_error(ADK::Auth::CredentialError)
    end
    
    it 'works with environment variable resolution' do
      scheme = described_class.new
      
      # Set up environment variable
      ENV['TEST_API_KEY'] = 'env-api-key'
      credential_with_env = ADK::Auth::Credential.new(
        auth_type: :api_key,
        api_key: 'ENV:TEST_API_KEY'
      )
      
      result = scheme.apply_to_request({}, credential_with_env)
      
      expect(result[:headers]['X-Api-Key']).to eq('env-api-key')
      
      # Clean up
      ENV.delete('TEST_API_KEY')
    end
  end
  
  describe '#to_h' do
    it 'returns a hash representation with all properties' do
      scheme = described_class.new(
        location: :query,
        name: 'apikey',
        prefix: 'Key-'
      )
      
      hash = scheme.to_h
      
      expect(hash).to include(
        type: :api_key,
        location: :query,
        name: 'apikey',
        prefix: 'Key-'
      )
    end
  end
end 