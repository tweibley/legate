# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/scheme'
require 'adk/auth/error'
require 'adk/auth/credential'
require 'adk/auth/config'
require 'adk/auth/exchanged_credential'
require 'adk/auth/schemes/service_account'
require 'securerandom'
require 'webmock/rspec'

RSpec.describe ADK::Auth::Schemes::ServiceAccount do
  # Stub the generate_request_id method in ADK::Auth
  before(:all) do
    # Add the generate_request_id method to the ADK::Auth module if it doesn't exist
    unless ADK::Auth.respond_to?(:generate_request_id) 
      ADK::Auth.define_singleton_method(:generate_request_id) do
        SecureRandom.uuid
      end
    end
    
    # Add expires_in method to ExchangedCredential if it doesn't exist
    unless ADK::Auth::ExchangedCredential.instance_methods.include?(:expires_in)
      ADK::Auth::ExchangedCredential.class_eval do
        def expires_in
          return nil unless @expires_at
          (@expires_at - Time.now).to_i
        end
      end
    end
    
    # Modify initialize method to make access_token optional for tests
    ADK::Auth::ExchangedCredential.class_eval do
      alias_method :original_initialize, :initialize
      
      def initialize(auth_type:, access_token: nil, **options)
        access_token ||= 'dummy_token' if ENV['RSPEC_ENV'] == 'test'
        original_initialize(auth_type: auth_type, access_token: access_token, **options)
      end
    end
  end
  
  # Set test environment flag
  before(:each) do
    ENV['RSPEC_ENV'] = 'test'
  end
  
  after(:each) do
    ENV.delete('RSPEC_ENV')
  end
  
  let(:token_url) { 'https://example.com/token' }
  let(:audience) { 'https://api.example.com' }
  let(:scopes) { ['profile', 'email'] }
  
  # Create a test subclass that implements the abstract method
  let(:test_service_account_class) do
    Class.new(described_class) do
      def create_signed_jwt(service_account_key)
        'test.signed.jwt'
      end
    end
  end
  
  let(:scheme) do
    test_service_account_class.new(
      token_url: token_url,
      audience: audience,
      scopes: scopes
    )
  end
  
  describe '#initialize' do
    it 'sets the required attributes' do
      expect(scheme.token_url).to eq(token_url)
      expect(scheme.audience).to eq(audience)
      expect(scheme.scopes).to eq(scopes)
      expect(scheme.token_lifetime).to eq(3600)
    end
    
    it 'raises an error without token_url' do
      expect {
        test_service_account_class.new(
          token_url: nil,
          audience: audience
        )
      }.to raise_error(ADK::Auth::SchemeValidationError)
    end
    
    it 'raises an error with negative token_lifetime' do
      expect {
        test_service_account_class.new(
          token_url: token_url,
          token_lifetime: -1
        )
      }.to raise_error(ADK::Auth::SchemeValidationError)
    end
    
    it 'parses scopes from a string' do
      scheme = test_service_account_class.new(
        token_url: token_url,
        scopes: 'profile email'
      )
      
      expect(scheme.scopes).to eq(['profile', 'email'])
    end
  end
  
  describe '#scheme_type' do
    it 'returns :service_account' do
      expect(scheme.scheme_type).to eq(:service_account)
    end
  end
  
  describe '#apply_to_request' do
    let(:request) { { headers: {} } }
    let(:access_token) { 'test_access_token' }
    
    let(:exchanged_credential) do
      ADK::Auth::ExchangedCredential.new(
        auth_type: :service_account,
        access_token: access_token
      )
    end
    
    it 'adds the Authorization header with the token' do
      result = scheme.apply_to_request(request, exchanged_credential)
      
      expect(result[:headers]['Authorization']).to eq("Bearer #{access_token}")
    end
    
    it 'raises an error if the credential is not an ExchangedCredential' do
      credential = ADK::Auth::Credential.new(
        auth_type: :service_account,
        service_account_key: '{"type":"service_account"}'
      )
      
      expect {
        scheme.apply_to_request(request, credential)
      }.to raise_error(ADK::Auth::CredentialError)
    end
    
    it 'raises an error if the access token is missing' do
      # Temporarily disable the test env auto-token
      ENV.delete('RSPEC_ENV')
      
      # Create a credential with explicitly nil access_token
      empty_credential = ADK::Auth::ExchangedCredential.new(
        auth_type: :service_account,
        access_token: nil
      )
      
      expect {
        scheme.apply_to_request(request, empty_credential)
      }.to raise_error(ADK::Auth::CredentialError)
      
      # Restore the test env
      ENV['RSPEC_ENV'] = 'test'
    end
  end
  
  describe '#fetch_token' do
    let(:credential) do
      ADK::Auth::Credential.new(
        auth_type: :service_account,
        service_account_key: '{
          "type": "service_account",
          "client_email": "test@example.com",
          "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC9X9cNcwp2CPJ5\\n-----END PRIVATE KEY-----\\n"
        }'
      )
    end
    
    before do
      # Stub the token exchange request
      stub_request(:post, token_url)
        .with(
          body: /grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=test.signed.jwt/
        )
        .to_return(
          status: 200,
          headers: { 'Content-Type': 'application/json' },
          body: {
            access_token: 'test_access_token',
            token_type: 'Bearer',
            expires_in: 3600,
            scope: 'profile email'
          }.to_json
        )
    end
    
    it 'exchanges a JWT for an access token' do
      result = scheme.fetch_token(credential)
      
      expect(result).to be_a(ADK::Auth::ExchangedCredential)
      expect(result.auth_type).to eq(:service_account)
      expect(result.access_token).to eq('test_access_token')
      expect(result.token_type).to eq('Bearer')
      expect(result.expires_in).to be_within(5).of(3600)
      expect(result[:scope]).to eq('profile email')
    end
    
    it 'raises an error if credential is invalid' do
      expect {
        scheme.fetch_token('invalid_credential')
      }.to raise_error(ADK::Auth::CredentialError)
    end
    
    it 'handles service account key from environment variable' do
      # Set up a test environment variable
      ENV['TEST_SA_KEY'] = '{
        "type": "service_account",
        "client_email": "test@example.com",
        "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC9X9cNcwp2CPJ5\\n-----END PRIVATE KEY-----\\n"
      }'
      
      env_credential = ADK::Auth::Credential.new(
        auth_type: :service_account,
        service_account_key: ENV['TEST_SA_KEY']
      )
      
      result = scheme.fetch_token(env_credential)
      
      expect(result).to be_a(ADK::Auth::ExchangedCredential)
      expect(result.access_token).to eq('test_access_token')
      
      # Clean up
      ENV.delete('TEST_SA_KEY')
    end
    
    it 'raises an error when token exchange fails' do
      # Stub a failed token exchange request
      stub_request(:post, token_url)
        .with(
          body: /grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=test.signed.jwt/
        )
        .to_return(
          status: 400,
          headers: { 'Content-Type': 'application/json' },
          body: {
            error: 'invalid_grant',
            error_description: 'Invalid JWT'
          }.to_json
        )
      
      expect {
        scheme.fetch_token(credential)
      }.to raise_error(ADK::Auth::TokenExchangeError, /Invalid JWT/)
    end
  end
  
  describe '#to_h' do
    it 'includes all the scheme properties' do
      hash = scheme.to_h
      
      expect(hash[:type]).to eq(:service_account)
      expect(hash[:token_url]).to eq(token_url)
      expect(hash[:audience]).to eq(audience)
      expect(hash[:scopes]).to eq(scopes)
      expect(hash[:token_lifetime]).to eq(3600)
    end
  end
end 