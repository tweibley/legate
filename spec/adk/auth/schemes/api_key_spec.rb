# File: spec/adk/auth/schemes/api_key_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/scheme'
require 'adk/auth/error'
require 'adk/auth/schemes/api_key'
require 'adk/auth/credential'

RSpec.describe ADK::Auth::Schemes::ApiKey do
  describe '#initialize' do
    it 'creates a new API key scheme' do
      scheme = described_class.new
      expect(scheme).to be_a(ADK::Auth::Schemes::ApiKey)
    end
  end
  
  describe '#scheme_type' do
    it 'returns :api_key' do
      scheme = described_class.new
      expect(scheme.scheme_type).to eq(:api_key)
    end
  end
  
  describe '#apply_to_request' do
    let(:scheme) { described_class.new }
    let(:credential) { ADK::Auth::Credential.new(auth_type: :api_key, api_key: 'test-api-key') }
    
    context 'with header location' do
      let(:credential_with_header) { 
        ADK::Auth::Credential.new(
          auth_type: :api_key, 
          api_key: 'test-api-key',
          location: 'header',
          name: 'API-Key'
        )
      }
      
      it 'adds the API key to the request headers' do
        request = {}
        
        result = scheme.apply_to_request(request, credential_with_header)
        
        expect(result[:headers]).to include('API-Key' => 'test-api-key')
      end
      
      it 'preserves existing headers' do
        request = { headers: { 'Content-Type' => 'application/json' } }
        
        result = scheme.apply_to_request(request, credential_with_header)
        
        expect(result[:headers]).to include(
          'API-Key' => 'test-api-key',
          'Content-Type' => 'application/json'
        )
      end
    end
    
    context 'with query location' do
      let(:credential_with_query) { 
        ADK::Auth::Credential.new(
          auth_type: :api_key, 
          api_key: 'test-api-key',
          location: 'query',
          name: 'api_key'
        )
      }
      
      it 'adds the API key to the query parameters' do
        request = { url: 'https://example.com/api' }
        
        result = scheme.apply_to_request(request, credential_with_query)
        
        expect(result[:url]).to include('api_key=test-api-key')
      end
      
      it 'preserves existing query parameters' do
        request = { url: 'https://example.com/api?version=1.0' }
        
        result = scheme.apply_to_request(request, credential_with_query)
        
        expect(result[:url]).to include('version=1.0')
        expect(result[:url]).to include('api_key=test-api-key')
      end
    end
    
    context 'with cookie location' do
      let(:credential_with_cookie) { 
        ADK::Auth::Credential.new(
          auth_type: :api_key, 
          api_key: 'test-api-key',
          location: 'cookie',
          name: 'api_key'
        )
      }
      
      it 'adds the API key to the cookie header' do
        request = {}
        
        result = scheme.apply_to_request(request, credential_with_cookie)
        
        expect(result[:headers]['Cookie']).to eq('api_key=test-api-key')
      end
      
      it 'appends to existing cookies' do
        request = { headers: { 'Cookie' => 'session=abc123' } }
        
        result = scheme.apply_to_request(request, credential_with_cookie)
        
        expect(result[:headers]['Cookie']).to eq('session=abc123; api_key=test-api-key')
      end
    end
    
    it 'raises an error if the credential is missing the API key' do
      # Create a credential with the required auth_type but with nil api_key
      credential_without_key = instance_double(
        'ADK::Auth::Credential',
        '[]': nil, # Return nil for any key access
        is_a?: true # Pretend to be a Credential
      )
      allow(credential_without_key).to receive(:[]).with(any_args).and_return(nil)
      
      expect {
        scheme.apply_to_request({}, credential_without_key)
      }.to raise_error(ADK::Auth::Error, /API key not found in credential/)
    end
    
    it 'works with environment variable resolution' do
      scheme = described_class.new
      
      # Set up environment variable
      ENV['TEST_API_KEY'] = 'env-api-key'
      credential_with_env = ADK::Auth::Credential.new(
        auth_type: :api_key,
        api_key: 'ENV:TEST_API_KEY'
      )
      
      result = scheme.apply_to_request({ url: 'https://example.com/api' }, credential_with_env)
      
      expect(result[:headers]['X-API-Key']).to eq('env-api-key')
      
      # Clean up
      ENV.delete('TEST_API_KEY')
    end
  end
  
  describe '#to_h' do
    it 'returns a hash representation with the scheme type' do
      scheme = described_class.new
      
      hash = scheme.to_h
      
      expect(hash).to include(type: :api_key)
    end
  end
end 