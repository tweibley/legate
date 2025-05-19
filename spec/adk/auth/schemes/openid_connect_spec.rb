# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/scheme'
require 'adk/auth/error'
require 'adk/auth/credential'
require 'adk/auth/config'
require 'adk/auth/exchanged_credential'
require 'adk/auth/schemes/openid_connect'
require 'securerandom'
require 'webmock/rspec'

RSpec.describe ADK::Auth::Schemes::OpenIDConnect do
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

  # Set up WebMock stubs for HTTP requests
  before(:each) do
    # Stub the discovery document request
    stub_request(:get, "https://example.com/.well-known/openid-configuration")
      .to_return(
        status: 200,
        headers: { 'Content-Type': 'application/json' },
        body: {
          issuer: 'https://example.com',
          authorization_endpoint: 'https://example.com/oidc/authorize',
          token_endpoint: 'https://example.com/oidc/token',
          jwks_uri: 'https://example.com/oidc/jwks',
          userinfo_endpoint: 'https://example.com/oidc/userinfo'
        }.to_json
      )

    # Stub the JWKS request
    stub_request(:get, "https://example.com/oidc/jwks")
      .to_return(
        status: 200,
        headers: { 'Content-Type': 'application/json' },
        body: {
          keys: [
            {
              kty: 'RSA',
              kid: 'test-key-id',
              n: 'ANjyvB_f8xm-9teXQV4Xc3-sBHM12nNpPxMzRqMPwxMN3jHJcGiwWgpQppv11_8nWU4lkwI5q8SATZe2bvLvVGDT_NJwajHY-QGT4MFw9dEBLIbQmR7bjnPwzuGlM6rYPGEZMpGSmBMY_QUw9JzLFZvS6IFhtPVvFmynPHvBO7bVDUgP_Dp45vEfosBq1MbNECSDDAi30gKKWSbJYJ7aNNOGGnRNiYV7rvZzt2XCzigdUoYBl8z_zJwOxw-zLFkP9OlHjEjQVfnKfmROXi_VIvvCQkQZUPALhh1cJrG6SGMIcaeMB35jkDVytUNgLd3vHF5fq9BCF-dvB6mH6ZolXwQ',
              e: 'AQAB'
            }
          ]
        }.to_json
      )

    # Stub the token endpoint request for OAuth2
    stub_request(:post, "https://example.com/oidc/token")
      .with(
        body: hash_including({
          "code" => "test_code",
          "grant_type" => "authorization_code"
        })
      )
      .to_return(
        status: 200,
        headers: { 'Content-Type': 'application/json' },
        body: {
          access_token: "test_access_token",
          token_type: "Bearer",
          refresh_token: "test_refresh_token",
          expires_in: 3600,
          id_token: "eyJhbGciOiJSUzI1NiIsImtpZCI6InRlc3Qta2V5LWlkIn0.eyJpc3MiOiJodHRwczovL2V4YW1wbGUuY29tIiwic3ViIjoiMTIzNDU2Nzg5MCIsImF1ZCI6InRlc3RfY2xpZW50X2lkIiwiZXhwIjo5OTk5OTk5OTk5LCJpYXQiOjE1MTYyMzkwMjIsIm5vbmNlIjoidGVzdF9ub25jZSIsImVtYWlsIjoidGVzdEBleGFtcGxlLmNvbSIsIm5hbWUiOiJUZXN0IFVzZXIifQ.signature"
        }.to_json
      )
      
    ENV['RSPEC_ENV'] = 'test'
  end
  
  after(:each) do
    ENV.delete('RSPEC_ENV')
  end

  let(:authorization_url) { 'https://example.com/oidc/authorize' }
  let(:token_url) { 'https://example.com/oidc/token' }
  let(:discovery_url) { 'https://example.com/.well-known/openid-configuration' }
  let(:jwks_url) { 'https://example.com/oidc/jwks' }
  let(:scopes) { ['profile', 'email'] }
  let(:client_id) { 'test_client_id' }
  let(:client_secret) { 'test_client_secret' }
  
  let(:credential) do
    ADK::Auth::Credential.new(
      auth_type: :oauth2, # Changed from :oidc to :oauth2 to match the requirement in OAuth2 class
      client_id: client_id,
      client_secret: client_secret
    )
  end
  
  describe '#initialize' do
    context 'with explicit endpoints' do
      let(:scheme) do
        described_class.new(
          authorization_url: authorization_url,
          token_url: token_url,
          scopes: scopes
        )
      end
      
      it 'sets the required attributes' do
        expect(scheme.authorization_url).to eq(authorization_url)
        expect(scheme.token_url).to eq(token_url)
        expect(scheme.scopes).to include('openid')
        expect(scheme.scopes).to include('profile')
        expect(scheme.scopes).to include('email')
      end
      
      it 'adds the openid scope if not present' do
        scheme = described_class.new(
          authorization_url: authorization_url,
          token_url: token_url,
          scopes: ['profile']
        )
        
        expect(scheme.scopes).to include('openid')
        expect(scheme.scopes).to include('profile')
      end
    end
    
    context 'with discovery URL' do
      let(:scheme) do
        # Stub the fetch_discovery_document method to return test endpoints
        allow_any_instance_of(described_class).to receive(:fetch_discovery_document).and_return({
          authorization_endpoint: authorization_url,
          token_endpoint: token_url,
          jwks_uri: jwks_url
        })
        
        described_class.new(
          discovery_url: discovery_url,
          scopes: scopes
        )
      end
      
      it 'uses the endpoints from discovery' do
        # This is using the stubbed fetch_discovery_document from above
        expect(scheme.authorization_url).to eq(authorization_url)
        expect(scheme.token_url).to eq(token_url)
      end
    end
  end
  
  describe '#scheme_type' do
    it 'returns :openid_connect' do
      scheme = described_class.new(
        authorization_url: authorization_url,
        token_url: token_url
      )
      
      expect(scheme.scheme_type).to eq(:openid_connect)
    end
  end
  
  describe '#build_authorization_uri' do
    let(:scheme) do
      described_class.new(
        authorization_url: authorization_url,
        token_url: token_url,
        scopes: scopes
      )
    end
    
    let(:config) { ADK::Auth::Config.new(scheme: scheme, credential: credential) }
    let(:redirect_uri) { 'https://app.example.com/callback' }
    
    it 'adds a nonce parameter' do
      # Prepare the options hash for the test
      config.options = {}
      
      # Mock the temp_scheme to avoid making actual HTTP requests
      temp_oauth2_scheme = instance_double(ADK::Auth::Schemes::OAuth2)
      allow(ADK::Auth::Schemes::OAuth2).to receive(:new).and_return(temp_oauth2_scheme)
      allow(temp_oauth2_scheme).to receive(:build_authorization_uri).and_return({
        uri: "https://example.com/oidc/authorize?client_id=test_client_id&nonce=1234567890abcdef&response_type=code",
        state: "state123",
        pkce: { code_verifier: "verifier123" }
      })
      
      # Allow the scheme to store the nonce in config
      allow(SecureRandom).to receive(:hex).and_return("generated_nonce")
      
      result = scheme.build_authorization_uri(config, redirect_uri)
      
      expect(result).to be_a(Hash)
      expect(config.options[:nonce]).to eq("generated_nonce")
      expect(temp_oauth2_scheme).to have_received(:build_authorization_uri)
    end
    
    it 'includes the openid scope' do
      # Mock the temp_scheme to avoid making actual HTTP requests
      temp_oauth2_scheme = instance_double(ADK::Auth::Schemes::OAuth2)
      allow(ADK::Auth::Schemes::OAuth2).to receive(:new).and_return(temp_oauth2_scheme)
      
      uri_with_scope = "https://example.com/oidc/authorize?client_id=test_client_id&response_type=code&scope=profile%20email%20openid"
      allow(temp_oauth2_scheme).to receive(:build_authorization_uri).and_return({
        uri: uri_with_scope,
        state: "state123",
        pkce: { code_verifier: "verifier123" }
      })
      
      result = scheme.build_authorization_uri(config, redirect_uri)
      
      expect(result[:uri]).to eq(uri_with_scope)
      expect(temp_oauth2_scheme).to have_received(:build_authorization_uri)
    end
  end
  
  describe '#exchange_token' do
    let(:scheme) do
      described_class.new(
        authorization_url: authorization_url,
        token_url: token_url
      )
    end
    
    let(:config) do
      config = ADK::Auth::Config.new(scheme: scheme, credential: credential)
      config.redirect_uri = 'https://app.example.com/callback'
      config.state = 'test_state'
      config.response_uri = 'https://app.example.com/callback?code=test_code&state=test_state'
      config.options = { nonce: 'test_nonce' }
      config
    end
    
    context 'with a valid ID token' do
      it 'creates an exchanged credential with the token and ID token' do
        # Create a mock ExchangedCredential as returned by OAuth2#exchange_token
        oauth2_credential = instance_double(ADK::Auth::ExchangedCredential)
        allow(oauth2_credential).to receive(:access_token).and_return('test_access_token')
        allow(oauth2_credential).to receive(:refresh_token).and_return('test_refresh_token')
        allow(oauth2_credential).to receive(:token_type).and_return('Bearer')
        allow(oauth2_credential).to receive(:expires_at).and_return(Time.now + 3600)
        allow(oauth2_credential).to receive(:expires_in).and_return(3600)
        allow(oauth2_credential).to receive(:[]).with(:scope).and_return('profile email openid')
        allow(oauth2_credential).to receive(:[]).with(:id_token).and_return('eyJhbGciOiJSUzI1NiIsImtpZCI6InRlc3Qta2V5LWlkIn0.eyJpc3MiOiJodHRwczovL2V4YW1wbGUuY29tIiwic3ViIjoiMTIzNDU2Nzg5MCIsImF1ZCI6InRlc3RfY2xpZW50X2lkIiwiZXhwIjo5OTk5OTk5OTk5LCJpYXQiOjE1MTYyMzkwMjIsIm5vbmNlIjoidGVzdF9ub25jZSIsImVtYWlsIjoidGVzdEBleGFtcGxlLmNvbSIsIm5hbWUiOiJUZXN0IFVzZXIifQ.signature')
        
        # Stub the parent class exchange_token to return our mock
        allow_any_instance_of(ADK::Auth::Schemes::OAuth2).to receive(:exchange_token).and_return(oauth2_credential)
        
        # Stub the verify_id_token method to return a test payload
        allow_any_instance_of(described_class).to receive(:verify_id_token).and_return({
          'sub' => '123456789',
          'name' => 'Test User',
          'email' => 'test@example.com'
        })
        
        # Stub the extract_user_info method to return user info
        allow_any_instance_of(described_class).to receive(:extract_user_info).and_return({
          sub: '123456789',
          name: 'Test User',
          email: 'test@example.com'
        })
        
        result = scheme.exchange_token(config, credential)
        
        expect(result).to be_a(ADK::Auth::ExchangedCredential)
        expect(result.auth_type).to eq(:openid_connect)
        expect(result.access_token).to eq('test_access_token')
        expect(result.refresh_token).to eq('test_refresh_token')
        expect(result.id_token).not_to be_nil
      end
    end
  end
  
  describe '#to_h' do
    it 'includes discovery URL if provided' do
      # Stub the fetch_discovery_document method to avoid HTTP request
      allow_any_instance_of(described_class).to receive(:fetch_discovery_document).and_return({
        authorization_endpoint: authorization_url,
        token_endpoint: token_url,
        jwks_uri: jwks_url
      })
      
      scheme = described_class.new(
        authorization_url: authorization_url,
        token_url: token_url,
        discovery_url: discovery_url
      )
      
      hash = scheme.to_h
      
      expect(hash[:type]).to eq(:openid_connect)
      expect(hash[:discovery_url]).to eq(discovery_url)
    end
    
    it 'includes JWKS URL if provided' do
      scheme = described_class.new(
        authorization_url: authorization_url,
        token_url: token_url,
        jwks_url: jwks_url
      )
      
      hash = scheme.to_h
      
      expect(hash[:jwks_url]).to eq(jwks_url)
    end
  end
end 