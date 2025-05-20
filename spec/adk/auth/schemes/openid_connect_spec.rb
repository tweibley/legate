# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/scheme'
require 'adk/auth/error'
require 'adk/auth/credential'
require 'adk/auth/config'
require 'adk/auth/exchanged_credential'
require 'adk/auth/schemes/oauth2'
require 'adk/auth/schemes/openid_connect'
require 'securerandom'
require 'webmock/rspec'
require 'jwt'

RSpec.describe ADK::Auth::Schemes::OpenIDConnect do
  # Stub the generate_request_id method in ADK::Auth
  before(:all) do
    # Add the generate_request_id method to the ADK::Auth module if it doesn't exist
    unless ADK::Auth.respond_to?(:generate_request_id) 
      ADK::Auth.define_singleton_method(:generate_request_id) do
        SecureRandom.uuid
      end
    end
  end
  
  before(:each) do
    # Stub the verify_jwt method to return a valid payload
    allow_any_instance_of(ADK::Auth::Schemes::OpenIDConnect).to receive(:verify_id_token) do |_scheme, id_token, nonce, client_id|
      {
        iss: 'https://example.com',
        sub: '1234567890',
        aud: client_id || 'test_client_id',
        exp: 9999999999,
        iat: 1516239022,
        nonce: nonce || 'test_nonce',
        email: 'test@example.com',
        name: 'Test User'
      }
    end

    # Set test environment
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

  describe '#initialize' do
    context 'with explicit endpoints' do
      let(:authorization_url) { 'https://example.com/oidc/authorize' }
      let(:token_url) { 'https://example.com/oidc/token' }
      let(:userinfo_url) { 'https://example.com/oidc/userinfo' }
      
      # Mock discovery to avoid real HTTP requests during tests
      before do
        allow_any_instance_of(described_class).to receive(:fetch_discovery_document).and_return({})
        
        # Force validation for tests that need to test validation
        ENV['RSPEC_ENV'] = 'test'
      end
      
      after do
        ENV.delete('FORCE_VALIDATE')
      end
      
      it 'sets the required attributes' do
        scheme = described_class.new(
          authorization_url: authorization_url,
          token_url: token_url,
          userinfo_url: userinfo_url
        )
        
        actual_auth_url = scheme.authorization_url.split('?').first
        expect(actual_auth_url).to eq(authorization_url)
        expect(scheme.token_url).to eq(token_url)
        expect(scheme.userinfo_url).to eq(userinfo_url)
        expect(scheme.scopes).to include('openid')
      end
      
      it 'adds the openid scope if not present' do
        scheme = described_class.new(
          authorization_url: authorization_url,
          token_url: token_url,
          scopes: ['profile', 'email']
        )
        
        expect(scheme.scopes).to include('profile')
        expect(scheme.scopes).to include('email')
        expect(scheme.scopes).to include('openid')
      end
      
      it 'raises an error without authorization_url' do
        # Temporarily force validation in test environment
        ENV['FORCE_VALIDATE'] = 'true'
        expect {
          described_class.new(token_url: 'https://example.com/oidc/token')
        }.to raise_error(ADK::Auth::SchemeValidationError, /Authorization URL is required/)
        ENV.delete('FORCE_VALIDATE')
      end

      it 'raises an error without token_url' do
        # Temporarily force validation in test environment
        ENV['FORCE_VALIDATE'] = 'true'
        expect {
          described_class.new(authorization_url: 'https://example.com/oidc/authorize')
        }.to raise_error(ADK::Auth::SchemeValidationError, /Token URL is required/)
        ENV.delete('FORCE_VALIDATE')
      end
    end

    context 'with discovery URL' do
      before do
        # Mock the discovery document fetch
        discovery_json = {
          authorization_endpoint: 'https://discovered.example.com/auth',
          token_endpoint: 'https://discovered.example.com/token',
          jwks_uri: 'https://discovered.example.com/jwks',
          userinfo_endpoint: 'https://discovered.example.com/userinfo',
          issuer: 'https://discovered.example.com'
        }

        allow_any_instance_of(described_class).to receive(:fetch_discovery_document).and_return(discovery_json)
        allow_any_instance_of(described_class).to receive(:discover_endpoints).and_return(discovery_json)
      end

      it 'uses the endpoints from discovery' do
        scheme = described_class.new(discovery_url: 'https://example.com/.well-known/openid-configuration')
        
        expect(scheme.authorization_url).to eq('https://discovered.example.com/auth')
        expect(scheme.token_url).to eq('https://discovered.example.com/token')
        expect(scheme.jwks_url).to eq('https://discovered.example.com/jwks')
        expect(scheme.userinfo_url).to eq('https://discovered.example.com/userinfo')
        expect(scheme.scopes).to include('openid')
      end
    end
  end

  describe '#scheme_type' do
    it 'returns :openid_connect' do
      scheme = described_class.new(
        authorization_url: 'https://example.com/oidc/authorize',
        token_url: 'https://example.com/oidc/token'
      )
      expect(scheme.scheme_type).to eq(:openid_connect)
    end
  end

  describe '#build_authorization_uri' do
    let(:scheme) do
      described_class.new(
        authorization_url: 'https://example.com/oidc/authorize',
        token_url: 'https://example.com/oidc/token'
      )
    end
    
    let(:config) do
      credential = ADK::Auth::Credential.new(
        auth_type: :oauth2,
        client_id: 'test_client_id'
      )
      config = ADK::Auth::Config.new(
        scheme: scheme,
        credential: credential
      )
      config.options = {}
      config
    end

    before do
      allow(SecureRandom).to receive(:uuid).and_return('test-state')
      allow(SecureRandom).to receive(:hex).and_return('test-nonce')
    end

    it 'adds a nonce parameter' do
      result = scheme.build_authorization_uri(config, 'https://app.example.com/callback')
      url = URI.parse(result[:uri])
      params = CGI.parse(url.query)
      expect(params).to have_key('nonce')
    end

    it 'stores the nonce in the state hash' do
      result = scheme.build_authorization_uri(config, 'https://app.example.com/callback')
      expect(config.options).to have_key(:nonce)
    end

    it 'includes the openid scope' do
      result = scheme.build_authorization_uri(config, 'https://app.example.com/callback')
      url = URI.parse(result[:uri])
      params = CGI.parse(url.query)
      expect(params['scope'].first).to include('openid')
    end
  end

  describe '#exchange_token' do
    let(:scheme) do
      described_class.new(
        authorization_url: 'https://example.com/oidc/authorize',
        token_url: 'https://example.com/oidc/token'
      )
    end

    let(:credential) do
      ADK::Auth::Credential.new(
        auth_type: :oauth2,
        client_id: 'test_client',
        client_secret: 'test_secret'
      )
    end

    let(:config) do
      config = ADK::Auth::Config.new(
        scheme: scheme,
        credential: credential
      )
      config.response_uri = 'https://app.example.com/callback?code=test_code&state=test_state'
      config.redirect_uri = 'https://app.example.com/callback'
      config.options = { nonce: 'test_nonce' }
      config
    end

    before do
      # Mock OAuth2 token exchange
      stub_request(:post, 'https://example.com/oidc/token')
        .to_return(
          status: 200,
          body: {
            access_token: 'test_access_token',
            token_type: 'Bearer',
            expires_in: 3600,
            refresh_token: 'test_refresh_token',
            id_token: 'test.id.token'
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    context 'with a valid ID token' do
      it 'creates an exchanged credential with the token and ID token' do
        # Mock the parent exchange_token method
        allow_any_instance_of(ADK::Auth::Schemes::OAuth2).to receive(:exchange_token)
          .and_return(create_test_credential(
            auth_type: :oauth2,
            access_token: 'test_access_token',
            token_type: 'Bearer',
            refresh_token: 'test_refresh_token',
            expires_in: 3600,
            id_token: 'test.id.token'
          ))

        # Make sure JWT.decode is properly mocked
        string_keys_payload = {
          'sub' => '1234567890',
          'email' => 'test@example.com',
          'name' => 'Test User'
        }
        
        allow(JWT).to receive(:decode).with('test.id.token', nil, false)
          .and_return([string_keys_payload, { 'alg' => 'RS256' }])

        # Also mock verify_id_token to return string keys payload instead of symbol keys
        allow_any_instance_of(ADK::Auth::Schemes::OpenIDConnect).to receive(:verify_id_token)
          .with('test.id.token', anything, anything)
          .and_return(string_keys_payload)

        result = scheme.exchange_token(config, credential)

        expect(result).to be_a(ADK::Auth::ExchangedCredential)
        expect(result.auth_type).to eq(:openid_connect)
        expect(result.access_token).to eq('test_access_token')
        expect(result.id_token).to eq('test.id.token')
        expect(result.id_token_claims).to include('sub' => '1234567890')
        expect(result.id_token_claims).to include('email' => 'test@example.com')
      end
    end
  end

  describe '#to_h' do
    before do
      # Mock the discovery document fetch for all tests in this context
      discovery_json = {
        authorization_endpoint: 'https://example.com/oidc/authorize',
        token_endpoint: 'https://example.com/oidc/token',
        jwks_uri: 'https://example.com/oidc/jwks',
        issuer: 'https://example.com'
      }.to_json

      stub_request(:get, 'https://example.com/.well-known/openid-configuration')
        .to_return(status: 200, body: discovery_json, headers: { 'Content-Type' => 'application/json' })
    end

    context 'with discovery URL' do
      it 'includes discovery URL if provided' do
        scheme = described_class.new(
          discovery_url: 'https://example.com/.well-known/openid-configuration',
          authorization_url: 'https://example.com/oidc/authorize',
          token_url: 'https://example.com/oidc/token'
        )
        hash = scheme.to_h
        expect(hash).to include(discovery_url: 'https://example.com/.well-known/openid-configuration')
      end
    end

    context 'with JWKS URL' do
      it 'includes JWKS URL if provided' do
        scheme = described_class.new(
          authorization_url: 'https://example.com/oidc/authorize',
          token_url: 'https://example.com/oidc/token',
          jwks_url: 'https://example.com/oidc/jwks'
        )
        hash = scheme.to_h
        expect(hash).to include(jwks_url: 'https://example.com/oidc/jwks')
      end
    end
  end
end 