# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/mock_auth_providers'
require_relative '../../support/auth_test_stubs'

RSpec.describe ADK::Auth::TestStubs::OAuth2 do
  let(:mock_provider) { ADK::Test::Support::MockAuthProviders::MockOAuth2Provider.new }
  let(:client_id) { mock_provider.config.client_id }
  let(:client_secret) { mock_provider.config.client_secret }
  let(:redirect_uri) { mock_provider.config.redirect_uri }
  let(:provider_uri) { mock_provider.config.issuer }
  
  before do
    # Setup mock endpoints
    mock_provider.setup_stubs
  end
  
  describe 'with mock provider' do
    let(:oauth2_config) do
      {
        provider_uri: provider_uri,
        client_id: client_id,
        client_secret: client_secret,
        redirect_uri: redirect_uri,
        scope: 'read write'
      }
    end
    
    let(:scheme) { described_class.new(oauth2_config) }
    
    it 'successfully initializes with config' do
      expect(scheme).to be_a(described_class)
      expect(scheme.client_id).to eq(client_id)
      expect(scheme.provider_uri).to eq(provider_uri)
    end
    
    describe '#discover_endpoints' do
      it 'successfully discovers OAuth2 endpoints' do
        endpoints = scheme.discover_endpoints
        
        expect(endpoints[:authorization_endpoint]).to eq(mock_provider.config.authorization_endpoint)
        expect(endpoints[:token_endpoint]).to eq(mock_provider.config.token_endpoint)
        expect(endpoints[:jwks_uri]).to eq(mock_provider.config.jwks_uri)
      end
    end
    
    describe '#authorization_url' do
      let(:state) { 'random_state_value' }
      
      it 'generates a valid authorization URL' do
        auth_url = scheme.authorization_url(state: state)
        
        expect(auth_url).to include(mock_provider.config.authorization_endpoint)
        expect(auth_url).to include("client_id=#{client_id}")
        expect(auth_url).to include("redirect_uri=#{CGI.escape(redirect_uri)}")
        expect(auth_url).to include("state=#{state}")
        expect(auth_url).to include("scope=read+write")
        expect(auth_url).to include("response_type=code")
      end
    end
    
    describe '#exchange_authorization_code' do
      let(:authorization_code) { 'test_auth_code' }
      
      it 'successfully exchanges code for token' do
        result = scheme.exchange_authorization_code(authorization_code)
        
        expect(result).to be_a(Hash)
        expect(result[:access_token]).to be_a(String)
        expect(result[:token_type]).to eq('Bearer')
        expect(result[:expires_in]).to eq(mock_provider.config.token_expiry_seconds)
        expect(result[:refresh_token]).to be_a(String)
      end
    end
    
    describe '#refresh_access_token' do
      let(:refresh_token) { 'refresh_valid_token' }
      
      it 'successfully refreshes access token' do
        result = scheme.refresh_access_token(refresh_token)
        
        expect(result).to be_a(Hash)
        expect(result[:access_token]).to be_a(String)
        expect(result[:token_type]).to eq('Bearer')
        expect(result[:expires_in]).to eq(mock_provider.config.token_expiry_seconds)
        expect(result[:refresh_token]).to be_a(String)
        expect(result[:refresh_token]).not_to eq(refresh_token)
      end
      
      context 'with invalid refresh token' do
        let(:refresh_token) { 'invalid_token' }
        
        it 'handles error response' do
          expect {
            scheme.refresh_access_token(refresh_token)
          }.to raise_error(ADK::Auth::Errors::AuthenticationError)
        end
      end
    end
    
    describe '#client_credentials_flow' do
      it 'successfully obtains token using client credentials' do
        result = scheme.client_credentials_flow
        
        expect(result).to be_a(Hash)
        expect(result[:access_token]).to be_a(String)
        expect(result[:token_type]).to eq('Bearer')
        expect(result[:expires_in]).to eq(mock_provider.config.token_expiry_seconds)
        expect(result).not_to have_key(:refresh_token) # Client credentials doesn't use refresh tokens
      end
    end
  end
end 