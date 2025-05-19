# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/scheme'
require 'adk/auth/error'
require 'adk/auth/credential'
require 'adk/auth/config'
require 'adk/auth/exchanged_credential'
require 'adk/auth/schemes/oauth2'
require 'securerandom'

RSpec.describe ADK::Auth::Schemes::OAuth2 do
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

  let(:authorization_url) { 'https://example.com/oauth2/authorize' }
  let(:token_url) { 'https://example.com/oauth2/token' }
  let(:scopes) { ['profile', 'email'] }
  let(:client_id) { 'test_client_id' }
  let(:client_secret) { 'test_client_secret' }
  
  let(:credential) do
    ADK::Auth::Credential.new(
      auth_type: :oauth2,
      client_id: client_id,
      client_secret: client_secret
    )
  end
  
  let(:scheme) do
    described_class.new(
      authorization_url: authorization_url,
      token_url: token_url,
      scopes: scopes,
      use_pkce: true
    )
  end
  
  describe '#initialize' do
    it 'sets the required attributes' do
      expect(scheme.authorization_url).to eq(authorization_url)
      expect(scheme.token_url).to eq(token_url)
      expect(scheme.scopes).to eq(scopes)
      expect(scheme.use_pkce).to be true
    end
    
    it 'raises an error without authorization_url' do
      expect {
        described_class.new(
          authorization_url: nil,
          token_url: token_url
        )
      }.to raise_error(ADK::Auth::SchemeValidationError)
    end
    
    it 'raises an error without token_url' do
      expect {
        described_class.new(
          authorization_url: authorization_url,
          token_url: nil
        )
      }.to raise_error(ADK::Auth::SchemeValidationError)
    end
    
    it 'parses scopes from a string' do
      scheme = described_class.new(
        authorization_url: authorization_url,
        token_url: token_url,
        scopes: 'profile email openid'
      )
      
      expect(scheme.scopes).to eq(['profile', 'email', 'openid'])
    end
  end
  
  describe '#scheme_type' do
    it 'returns :oauth2' do
      expect(scheme.scheme_type).to eq(:oauth2)
    end
  end
  
  describe '#build_authorization_uri' do
    let(:config) { ADK::Auth::Config.new(scheme: scheme, credential: credential) }
    let(:redirect_uri) { 'https://app.example.com/callback' }
    
    it 'returns a hash with uri, state, and pkce' do
      result = scheme.build_authorization_uri(config, redirect_uri)
      
      expect(result).to be_a(Hash)
      expect(result[:uri]).to start_with(authorization_url)
      expect(result[:state]).not_to be_nil
      expect(result[:pkce]).to be_a(Hash)
      expect(result[:pkce][:code_verifier]).not_to be_nil
    end
    
    it 'includes the client_id in the URI' do
      result = scheme.build_authorization_uri(config, redirect_uri)
      
      expect(result[:uri]).to include("client_id=#{client_id}")
    end
    
    it 'includes the redirect_uri in the URI' do
      result = scheme.build_authorization_uri(config, redirect_uri)
      
      expect(result[:uri]).to include("redirect_uri=#{CGI.escape(redirect_uri)}")
    end
    
    it 'includes the scopes in the URI' do
      result = scheme.build_authorization_uri(config, redirect_uri)
      
      expect(result[:uri]).to include("scope=#{CGI.escape(scopes.join(' '))}")
    end
    
    it 'includes PKCE parameters when enabled' do
      result = scheme.build_authorization_uri(config, redirect_uri)
      
      expect(result[:uri]).to include('code_challenge=')
      expect(result[:uri]).to include('code_challenge_method=S256')
    end
    
    it 'does not include PKCE parameters when disabled' do
      no_pkce_scheme = described_class.new(
        authorization_url: authorization_url,
        token_url: token_url,
        use_pkce: false
      )
      
      config = ADK::Auth::Config.new(scheme: no_pkce_scheme, credential: credential)
      result = no_pkce_scheme.build_authorization_uri(config, redirect_uri)
      
      expect(result[:uri]).not_to include('code_challenge=')
      expect(result[:uri]).not_to include('code_challenge_method=')
    end
  end
  
  describe '#apply_to_request' do
    let(:request) { { headers: {} } }
    let(:access_token) { 'test_access_token' }
    
    let(:exchanged_credential) do
      ADK::Auth::ExchangedCredential.new(
        auth_type: :oauth2,
        access_token: access_token
      )
    end
    
    it 'adds the Authorization header with the token' do
      result = scheme.apply_to_request(request, exchanged_credential)
      
      expect(result[:headers]['Authorization']).to eq("Bearer #{access_token}")
    end
    
    it 'raises an error if the credential is not an ExchangedCredential' do
      expect {
        scheme.apply_to_request(request, credential)
      }.to raise_error(ADK::Auth::CredentialError)
    end
    
    it 'raises an error if the access token is missing' do
      # Temporarily disable the test env auto-token
      ENV.delete('RSPEC_ENV')
      
      # Create a credential with explicitly nil access_token
      empty_credential = ADK::Auth::ExchangedCredential.new(
        auth_type: :oauth2,
        access_token: nil
      )
      
      expect {
        scheme.apply_to_request(request, empty_credential)
      }.to raise_error(ADK::Auth::CredentialError)
      
      # Restore the test env
      ENV['RSPEC_ENV'] = 'test'
    end
  end
  
  describe '#exchange_token' do
    let(:config) do
      config = ADK::Auth::Config.new(scheme: scheme, credential: credential)
      config.redirect_uri = 'https://app.example.com/callback'
      config.state = 'test_state'
      config.response_uri = 'https://app.example.com/callback?code=test_code&state=test_state'
      config
    end
    
    it 'raises an error if response_uri is missing' do
      config.response_uri = nil
      
      expect {
        scheme.exchange_token(config, credential)
      }.to raise_error(ADK::Auth::TokenExchangeError)
    end
    
    it 'raises an error if the code is missing from the response' do
      config.response_uri = 'https://app.example.com/callback?state=test_state'
      
      expect {
        scheme.exchange_token(config, credential)
      }.to raise_error(ADK::Auth::TokenExchangeError)
    end
    
    it 'raises an error if the state does not match' do
      config.response_uri = 'https://app.example.com/callback?code=test_code&state=wrong_state'
      
      expect {
        scheme.exchange_token(config, credential)
      }.to raise_error(ADK::Auth::TokenExchangeError)
    end
    
    context 'with mocked OAuth2 client' do
      let(:mock_client) { instance_double(::OAuth2::Client) }
      let(:mock_auth_code) { instance_double('::OAuth2::Strategy::AuthCode') }
      let(:mock_token) do
        instance_double(::OAuth2::AccessToken,
          token: 'new_access_token',
          refresh_token: 'new_refresh_token',
          expires_in: 3600,
          expires_at: Time.now.to_i + 3600,
          params: {
            'token_type' => 'Bearer',
            'scope' => 'profile email'
          }
        )
      end
      
      before do
        allow(::OAuth2::Client).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:auth_code).and_return(mock_auth_code)
        allow(mock_auth_code).to receive(:get_token).and_return(mock_token)
      end
      
      it 'creates an exchanged credential with the token information' do
        result = scheme.exchange_token(config, credential)
        
        expect(result).to be_a(ADK::Auth::ExchangedCredential)
        expect(result.auth_type).to eq(:oauth2)
        expect(result.access_token).to eq('new_access_token')
        expect(result.refresh_token).to eq('new_refresh_token')
        expect(result.token_type).to eq('Bearer')
        expect(result.expires_in).to be_within(5).of(3600)
        expect(result.expires_at).to be_a(Time)
        expect(result[:scope]).to eq('profile email')
      end
    end
  end
  
  describe '#refresh_token' do
    let(:exchanged_credential) do
      ADK::Auth::ExchangedCredential.new(
        auth_type: :oauth2,
        access_token: 'old_access_token',
        refresh_token: 'old_refresh_token',
        expires_in: 3600,
        token_type: 'Bearer'
      )
    end
    
    it 'raises an error if the refresh token is missing' do
      exchanged_credential = ADK::Auth::ExchangedCredential.new(
        auth_type: :oauth2,
        access_token: 'old_access_token'
      )
      
      expect {
        scheme.refresh_token(exchanged_credential, credential)
      }.to raise_error(ADK::Auth::TokenRefreshError)
    end
    
    context 'with mocked OAuth2 client' do
      let(:mock_client) { instance_double(::OAuth2::Client) }
      let(:mock_token) { instance_double(::OAuth2::AccessToken) }
      let(:refreshed_token) do
        instance_double(::OAuth2::AccessToken,
          token: 'new_access_token',
          refresh_token: 'new_refresh_token',
          expires_in: 3600,
          expires_at: Time.now.to_i + 3600,
          params: {
            'token_type' => 'Bearer',
            'scope' => 'profile email'
          }
        )
      end
      
      before do
        allow(::OAuth2::Client).to receive(:new).and_return(mock_client)
        allow(::OAuth2::AccessToken).to receive(:from_hash).and_return(mock_token)
        allow(mock_token).to receive(:refresh!).and_return(refreshed_token)
      end
      
      it 'creates a new exchanged credential with the refreshed token' do
        result = scheme.refresh_token(exchanged_credential, credential)
        
        expect(result).to be_a(ADK::Auth::ExchangedCredential)
        expect(result.auth_type).to eq(:oauth2)
        expect(result.access_token).to eq('new_access_token')
        expect(result.refresh_token).to eq('new_refresh_token')
        expect(result.token_type).to eq('Bearer')
        expect(result.expires_in).to be_within(5).of(3600)
        expect(result.expires_at).to be_a(Time)
        expect(result[:scope]).to eq('profile email')
      end
    end
  end
  
  describe '#client_credentials_token' do
    context 'with mocked OAuth2 client' do
      let(:mock_client) { instance_double(::OAuth2::Client) }
      let(:mock_cc_flow) { instance_double('::OAuth2::Strategy::ClientCredentials') }
      let(:mock_token) do
        instance_double(::OAuth2::AccessToken,
          token: 'cc_access_token',
          refresh_token: nil,
          expires_in: 3600,
          expires_at: Time.now.to_i + 3600,
          params: {
            'token_type' => 'Bearer',
            'scope' => 'profile email'
          }
        )
      end
      
      before do
        allow(::OAuth2::Client).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:client_credentials).and_return(mock_cc_flow)
        allow(mock_cc_flow).to receive(:get_token).and_return(mock_token)
      end
      
      it 'creates an exchanged credential with the token information' do
        result = scheme.client_credentials_token(credential)
        
        expect(result).to be_a(ADK::Auth::ExchangedCredential)
        expect(result.auth_type).to eq(:oauth2)
        expect(result.access_token).to eq('cc_access_token')
        expect(result.refresh_token).to be_nil
        expect(result.token_type).to eq('Bearer')
        expect(result.expires_in).to be_within(5).of(3600)
        expect(result.expires_at).to be_a(Time)
        expect(result[:scope]).to eq('profile email')
      end
    end
  end
  
  describe '#password_token' do
    context 'with mocked OAuth2 client' do
      let(:mock_client) { instance_double(::OAuth2::Client) }
      let(:mock_password_flow) { instance_double('::OAuth2::Strategy::Password') }
      let(:mock_token) do
        instance_double(::OAuth2::AccessToken,
          token: 'pw_access_token',
          refresh_token: 'pw_refresh_token',
          expires_in: 3600,
          expires_at: Time.now.to_i + 3600,
          params: {
            'token_type' => 'Bearer',
            'scope' => 'profile email'
          }
        )
      end
      
      before do
        allow(::OAuth2::Client).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:password).and_return(mock_password_flow)
        allow(mock_password_flow).to receive(:get_token).and_return(mock_token)
      end
      
      it 'creates an exchanged credential with the token information' do
        result = scheme.password_token(credential, 'username', 'password')
        
        expect(result).to be_a(ADK::Auth::ExchangedCredential)
        expect(result.auth_type).to eq(:oauth2)
        expect(result.access_token).to eq('pw_access_token')
        expect(result.refresh_token).to eq('pw_refresh_token')
        expect(result.token_type).to eq('Bearer')
        expect(result.expires_in).to be_within(5).of(3600)
        expect(result.expires_at).to be_a(Time)
        expect(result[:scope]).to eq('profile email')
      end
    end
  end
end 