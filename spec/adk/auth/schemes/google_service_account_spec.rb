# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/scheme'
require 'adk/auth/error'
require 'adk/auth/credential'
require 'adk/auth/config'
require 'adk/auth/exchanged_credential'
require 'adk/auth/schemes/service_account'
require 'adk/auth/schemes/google_service_account'
require 'securerandom'
require 'webmock/rspec'
require 'base64'
require 'jwt'

RSpec.describe ADK::Auth::Schemes::GoogleServiceAccount do
  # Stub the generate_request_id method in ADK::Auth
  before(:all) do
    # Add the generate_request_id method to the ADK::Auth module if it doesn't exist
    unless ADK::Auth.respond_to?(:generate_request_id) 
      ADK::Auth.define_singleton_method(:generate_request_id) do
        SecureRandom.uuid
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
  
  # Helper method for creating test credentials
  def create_test_credential(auth_type:, access_token: nil, **options)
    access_token ||= 'dummy_token' if ENV['RSPEC_ENV'] == 'test'
    ADK::Auth::ExchangedCredential.new(auth_type: auth_type, access_token: access_token, **options)
  end
  
  # Helper method for calculating expires_in
  def calculate_expires_in(expires_at)
    return nil unless expires_at
    (expires_at - Time.now).to_i
  end
  
  let(:token_url) { 'https://oauth2.googleapis.com/token' } 
  let(:audience) { 'https://pubsub.googleapis.com/' }
  let(:scopes) { ['https://www.googleapis.com/auth/pubsub'] }
  
  let(:scheme) do
    described_class.new(
      audience: audience,
      scopes: scopes
    )
  end
  
  let(:service_account_key) do
    {
      type: 'service_account',
      project_id: 'test-project',
      private_key_id: 'abcdef1234567890',
      private_key: "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC9X9cNcwp2CPJ5\n-----END PRIVATE KEY-----\n",
      client_email: 'test-service-account@test-project.iam.gserviceaccount.com',
      client_id: '123456789012345678901',
      auth_uri: 'https://accounts.google.com/o/oauth2/auth',
      token_uri: 'https://oauth2.googleapis.com/token',
      auth_provider_x509_cert_url: 'https://www.googleapis.com/oauth2/v1/certs',
      client_x509_cert_url: 'https://www.googleapis.com/robot/v1/metadata/x509/test-service-account%40test-project.iam.gserviceaccount.com'
    }
  end
  
  let(:credential) do
    ADK::Auth::Credential.new(
      auth_type: :google_service_account,
      service_account_key: service_account_key.to_json
    )
  end
  
  describe '#initialize' do
    it 'sets the default token URL for Google' do
      expect(scheme.token_url).to eq('https://oauth2.googleapis.com/token')
    end
    
    it 'uses token URL as audience if none is provided' do
      scheme = described_class.new(scopes: scopes)
      
      expect(scheme.audience).to eq(scheme.token_url)
    end
    
    it 'allows custom token URL' do
      custom_url = 'https://custom-token-endpoint.example.com'
      scheme = described_class.new(
        token_url: custom_url,
        audience: audience,
        scopes: scopes
      )
      
      expect(scheme.token_url).to eq(custom_url)
    end
  end
  
  describe '#scheme_type' do
    it 'returns :google_service_account' do
      expect(scheme.scheme_type).to eq(:google_service_account)
    end
  end
  
  describe '#fetch_token' do
    before do
      # Create a proper RSA key instance for testing
      rsa_key = instance_double(OpenSSL::PKey::RSA)
      allow(OpenSSL::PKey::RSA).to receive(:new).and_return(rsa_key)
      
      # Mock private key operations (avoid actual crypto)
      allow(rsa_key).to receive(:sign).and_return('test_signature')
      
      # Mock JWT encoding to return a testable token
      allow(JWT).to receive(:encode).and_return('test.google.jwt')
      
      # Stub the token exchange request
      stub_request(:post, token_url)
        .with(
          body: /grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=test.google.jwt/
        )
        .to_return(
          status: 200,
          headers: { 'Content-Type': 'application/json' },
          body: {
            access_token: 'google_access_token',
            token_type: 'Bearer',
            expires_in: 3600,
            scope: scopes.join(' ')
          }.to_json
        )
    end
    
    it 'creates a JWT with Google-specific claims' do
      # Call fetch_token which will use our stubbed JWT.encode
      scheme.fetch_token(credential)
      
      # Verify that encode was called with the right arguments
      expect(JWT).to have_received(:encode) do |payload, _, alg, header|
        # Verify payload
        expect(payload[:iss]).to eq(service_account_key[:client_email])
        expect(payload[:aud]).to eq(audience)
        expect(payload[:scope]).to eq(scopes.join(' '))
        expect(payload[:exp]).to be > Time.now.to_i
        expect(payload[:iat]).to be <= Time.now.to_i
        
        # Verify algorithm and headers
        expect(alg).to eq('RS256')
        expect(header[:typ]).to eq('JWT')
        
        true # Return true to satisfy the expectation
      end
    end
    
    it 'exchanges the JWT for a token' do
      result = scheme.fetch_token(credential)
      
      expect(result).to be_a(ADK::Auth::ExchangedCredential)
      expect(result.auth_type).to eq(:google_service_account)
      expect(result.access_token).to eq('google_access_token')
      expect(result.token_type).to eq('Bearer')
      expect(calculate_expires_in(result.expires_at)).to be_within(5).of(3600)
      expect(result[:scope]).to eq(scopes.join(' '))
    end
    
    it 'validates required fields in service account key' do
      # Create credential with missing field
      invalid_key = service_account_key.dup
      invalid_key.delete(:client_email)
      
      invalid_credential = ADK::Auth::Credential.new(
        auth_type: :google_service_account,
        service_account_key: invalid_key.to_json
      )
      
      expect {
        scheme.fetch_token(invalid_credential)
      }.to raise_error(ADK::Auth::CredentialError, /missing required fields/)
    end
    
    it 'validates the type field in service account key' do
      # Create credential with wrong type
      invalid_key = service_account_key.dup
      invalid_key[:type] = 'not_a_service_account'
      
      invalid_credential = ADK::Auth::Credential.new(
        auth_type: :google_service_account,
        service_account_key: invalid_key.to_json
      )
      
      expect {
        scheme.fetch_token(invalid_credential)
      }.to raise_error(ADK::Auth::CredentialError, /Invalid key type/)
    end
    
    it 'includes subject if provided in service account key' do
      # Create credential with subject
      key_with_sub = service_account_key.dup
      key_with_sub[:sub] = 'user@example.com'
      
      credential_with_sub = ADK::Auth::Credential.new(
        auth_type: :google_service_account,
        service_account_key: key_with_sub.to_json
      )
      
      # Call fetch_token which will use our stubbed JWT.encode
      scheme.fetch_token(credential_with_sub)
      
      # Verify that the sub claim was included
      expect(JWT).to have_received(:encode) do |payload, _, _, _|
        expect(payload[:sub]).to eq('user@example.com')
        true
      end
    end
  end
end 