# File: spec/adk/auth/schemes/http_bearer_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/scheme'
require 'adk/auth/error'
require 'adk/auth/schemes/http_bearer'
require 'adk/auth/credential'
require 'adk/auth/exchanged_credential'

RSpec.describe ADK::Auth::Schemes::HTTPBearer do
  describe '#initialize' do
    it 'creates a new HTTP Bearer scheme with default values' do
      scheme = described_class.new
      expect(scheme.instance_variable_get(:@bearer_format)).to be_nil
    end
    
    it 'accepts a custom bearer format' do
      scheme = described_class.new(bearer_format: 'JWT')
      expect(scheme.instance_variable_get(:@bearer_format)).to eq('JWT')
    end
  end
  
  describe '#scheme_type' do
    it 'returns :http_bearer' do
      scheme = described_class.new
      expect(scheme.scheme_type).to eq(:http_bearer)
    end
  end
  
  describe '#validate!' do
    it 'does not raise an error' do
      scheme = described_class.new
      expect { scheme.validate! }.not_to raise_error
    end
  end
  
  describe '#apply_to_request' do
    let(:scheme) { described_class.new }
    
    context 'with a Credential' do
      it 'adds the bearer token to the Authorization header' do
        credential = ADK::Auth::Credential.new(
          auth_type: :http_bearer,
          bearer_token: 'test-token'
        )
        
        request = {}
        result = scheme.apply_to_request(request, credential)
        
        expect(result[:headers]).to include('Authorization' => 'Bearer test-token')
      end
      
      it 'resolves environment variables for the token' do
        ENV['TEST_BEARER_TOKEN'] = 'env-token'
        credential = ADK::Auth::Credential.new(
          auth_type: :http_bearer,
          bearer_token: 'ENV:TEST_BEARER_TOKEN'
        )
        
        request = {}
        result = scheme.apply_to_request(request, credential)
        
        expect(result[:headers]).to include('Authorization' => 'Bearer env-token')
        
        # Clean up
        ENV.delete('TEST_BEARER_TOKEN')
      end
      
      it 'raises an error if the bearer token is missing' do
        # Create a double that simulates a credential without a bearer token
        credential_without_token = instance_double(
          'ADK::Auth::Credential',
          '[]': nil, # Return nil for any key access
          is_a?: true # Pretend to be a Credential
        )
        allow(credential_without_token).to receive(:[]).with(any_args).and_return(nil)
        
        expect {
          scheme.apply_to_request({}, credential_without_token)
        }.to raise_error(ADK::Auth::CredentialError)
      end
    end
    
    context 'with an ExchangedCredential' do
      it 'uses the access token as the bearer token' do
        # Create a double that behaves like an ExchangedCredential
        exchanged_credential = instance_double(
          'ADK::Auth::ExchangedCredential',
          access_token: 'access-token',
          is_a?: false # Not a Credential
        )
        # Make is_a? work correctly
        allow(exchanged_credential).to receive(:is_a?).with(ADK::Auth::Credential).and_return(false)
        allow(exchanged_credential).to receive(:is_a?).with(ADK::Auth::ExchangedCredential).and_return(true)
        
        request = {}
        result = scheme.apply_to_request(request, exchanged_credential)
        
        expect(result[:headers]).to include('Authorization' => 'Bearer access-token')
      end
      
      it 'raises an error if the access token is missing' do
        # Create a double that behaves like an ExchangedCredential without an access token
        exchanged_credential_without_token = instance_double(
          'ADK::Auth::ExchangedCredential',
          access_token: nil,
          is_a?: false # Not a Credential
        )
        # Make is_a? work correctly
        allow(exchanged_credential_without_token).to receive(:is_a?).with(ADK::Auth::Credential).and_return(false)
        allow(exchanged_credential_without_token).to receive(:is_a?).with(ADK::Auth::ExchangedCredential).and_return(true)
        
        expect {
          scheme.apply_to_request({}, exchanged_credential_without_token)
        }.to raise_error(ADK::Auth::CredentialError)
      end
    end
    
    it 'preserves existing headers' do
      credential = ADK::Auth::Credential.new(
        auth_type: :http_bearer,
        bearer_token: 'test-token'
      )
      
      request = { headers: { 'Content-Type' => 'application/json' } }
      result = scheme.apply_to_request(request, credential)
      
      expect(result[:headers]).to include(
        'Authorization' => 'Bearer test-token',
        'Content-Type' => 'application/json'
      )
    end
  end
  
  describe '#to_h' do
    it 'returns a hash with the scheme type' do
      scheme = described_class.new
      expect(scheme.to_h).to eq({ type: :http_bearer })
    end
    
    it 'includes bearer format if specified' do
      scheme = described_class.new(bearer_format: 'JWT')
      expect(scheme.to_h).to eq({ type: :http_bearer, bearer_format: 'JWT' })
    end
  end
end 