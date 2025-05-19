# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/token_manager'
require 'adk/auth/token_store'
require 'adk/auth/schemes/oauth2'
require 'adk/auth/schemes/api_key'
require 'adk/auth/credential'
require 'adk/auth/exchanged_credential'
require 'webmock/rspec'

RSpec.describe ADK::Auth::TokenManager do
  let(:session_service) { instance_double(ADK::SessionService::Redis) }
  let(:token_store) { ADK::Auth::TokenStore.new(session_service) }
  let(:manager) { ADK::Auth::TokenManager.new(token_store) }
  
  let(:api_key_scheme) { ADK::Auth::Schemes::APIKey.new(name: 'api_key', location: 'header') }
  let(:api_key_credential) { ADK::Auth::Credential.new(auth_type: :api_key, api_key: 'test123') }
  
  let(:oauth_scheme) { 
    ADK::Auth::Schemes::OAuth2.new(
      authorization_url: 'https://example.com/auth',
      token_url: 'https://example.com/token',
      revocation_url: 'https://example.com/revoke'
    )
  }
  
  let(:oauth_credential) {
    ADK::Auth::Credential.new(
      auth_type: :oauth2,
      client_id: 'client123',
      client_secret: 'secret123'
    )
  }
  
  let(:exchanged_credential) {
    ADK::Auth::ExchangedCredential.new(
      auth_type: :oauth2,
      access_token: 'access123',
      refresh_token: 'refresh123',
      expires_in: 3600
    )
  }
  
  let(:expired_credential) {
    credential = ADK::Auth::ExchangedCredential.new(
      auth_type: :oauth2,
      access_token: 'access123',
      refresh_token: 'refresh123',
      expires_in: -100 # Already expired
    )
    # Ensure expired? returns true to simulate an expired token
    allow(credential).to receive(:expired?).and_return(true)
    credential
  }
  
  before do
    allow(session_service).to receive(:save_scoped_state).and_return(true)
    allow(session_service).to receive(:load_scoped_state).and_return(nil)
    allow(session_service).to receive(:clear_scoped_state).and_return(true)
    
    # Stub the token refresh HTTP request
    stub_request(:post, "https://example.com/token")
      .with(
        body: {"grant_type" => "refresh_token", "refresh_token" => "refresh123"},
        headers: {
          'Authorization'=>/Basic .+/,
          'Content-Type'=>'application/x-www-form-urlencoded'
        }
      )
      .to_return(
        status: 200,
        body: {
          "access_token" => "new_token",
          "refresh_token" => "new_refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end
  
  describe '#get_token' do
    context 'with no existing token' do
      it 'returns nil for OAuth2 schemes requiring full auth flow' do
        expect(manager.get_token(oauth_scheme, oauth_credential)).to be_nil
      end
      
      it 'creates a new token for APIKey schemes' do
        token = manager.get_token(api_key_scheme, api_key_credential)
        expect(token).to be_a(ADK::Auth::ExchangedCredential)
        expect(token.access_token).to eq('test123')
      end
    end
    
    context 'with an existing non-expired token' do
      before do
        # Setup token store to return our non-expired credential
        allow(token_store).to receive(:get).and_return(exchanged_credential)
        # Ensure expired? returns false
        allow(exchanged_credential).to receive(:expired?).and_return(false)
      end
      
      it 'returns the existing token' do
        token = manager.get_token(oauth_scheme, oauth_credential)
        expect(token).to eq(exchanged_credential)
      end
      
      it 'forces a refresh when force_refresh is true' do
        # Mock the refresh_token method on the scheme directly instead of relying on HTTP
        refreshed_token = exchanged_credential.with(access_token: 'refreshed_token')
        allow(oauth_scheme).to receive(:refresh_token).and_return(refreshed_token)
        
        result = manager.get_token(oauth_scheme, oauth_credential, force_refresh: true)
        expect(result.access_token).to eq('refreshed_token')
      end
    end
    
    context 'with an existing expired token' do
      before do
        # Setup token store to return our expired credential
        allow(token_store).to receive(:get).and_return(expired_credential)
      end
      
      it 'attempts to refresh the token' do
        # Mock the refresh_token method instead of relying on HTTP
        refreshed = exchanged_credential.with(access_token: 'new_token')
        allow(oauth_scheme).to receive(:refresh_token).and_return(refreshed)
        allow(expired_credential).to receive(:refreshable?).and_return(true)
        
        token = manager.get_token(oauth_scheme, oauth_credential)
        expect(token.access_token).to eq('new_token')
      end
      
      it 'handles refresh failure' do
        # Mock refresh_token to throw an error
        allow(oauth_scheme).to receive(:refresh_token).and_raise(ADK::Auth::TokenRefreshError, 'Refresh failed')
        allow(expired_credential).to receive(:refreshable?).and_return(true)
        allow(ADK).to receive(:logger).and_return(double(error: nil))
        
        # Should return nil in case of refresh failure for OAuth
        expect(manager.get_token(oauth_scheme, oauth_credential)).to be_nil
      end
      
      it 'invalidates expired tokens that cannot be refreshed' do
        # Make the token not refreshable (no refresh token)
        allow(expired_credential).to receive(:refreshable?).and_return(false)
        
        # Expect the token to be invalidated
        expect(token_store).to receive(:clear).and_return(true)
        
        # Should return nil for expired tokens that can't be refreshed
        expect(manager.get_token(oauth_scheme, oauth_credential)).to be_nil
      end
    end
  end
  
  describe '#refresh_token' do
    it 'attempts to refresh a token' do
      refreshed = exchanged_credential.with(access_token: 'refreshed_token')
      allow(oauth_scheme).to receive(:refresh_token).and_return(refreshed)
      allow(exchanged_credential).to receive(:refreshable?).and_return(true)
      
      token = manager.refresh_token(oauth_scheme, oauth_credential, exchanged_credential)
      expect(token.access_token).to eq('refreshed_token')
    end
    
    it 'returns nil if the token cannot be refreshed' do
      allow(oauth_scheme).to receive(:refresh_token).and_raise(ADK::Auth::TokenRefreshError, 'Refresh failed')
      allow(exchanged_credential).to receive(:refreshable?).and_return(true)
      allow(ADK).to receive(:logger).and_return(double(error: nil))
      
      token = manager.refresh_token(oauth_scheme, oauth_credential, exchanged_credential)
      expect(token).to be_nil
    end
  end
  
  describe '#invalidate_token' do
    it 'removes the token from the store' do
      expect(token_store).to receive(:clear).with('some_key').and_return(true)
      expect(manager.invalidate_token('some_key')).to eq(true)
    end
  end
  
  describe '#revoke_token' do
    it 'revokes a token if the scheme supports it' do
      expect(oauth_scheme).to receive(:revoke_token).and_return(true)
      expect(manager.revoke_token(oauth_scheme, oauth_credential, exchanged_credential)).to eq(true)
    end
    
    it 'returns false if the scheme does not support revocation' do
      # API key scheme doesn't support revocation
      allow(ADK).to receive(:logger).and_return(double(warn: nil))
      expect(manager.revoke_token(api_key_scheme, api_key_credential, exchanged_credential)).to eq(false)
    end
  end
  
  describe 'event callbacks' do
    it 'registers and triggers callbacks' do
      callback_executed = false
      event_data = nil
      
      manager.on(:refresh_success) do |data|
        callback_executed = true
        event_data = data
      end
      
      # Trigger a refresh success
      refreshed = exchanged_credential.with(access_token: 'new_token')
      allow(oauth_scheme).to receive(:refresh_token).and_return(refreshed)
      allow(exchanged_credential).to receive(:refreshable?).and_return(true)
      
      manager.refresh_token(oauth_scheme, oauth_credential, exchanged_credential)
      
      expect(callback_executed).to be true
      expect(event_data[:event]).to eq(:refresh_success)
      expect(event_data[:token]).to eq(refreshed)
    end
    
    it 'handles exceptions in callbacks' do
      # Register a callback that throws an exception
      manager.on(:refresh_success) { |_| raise 'Callback error' }
      
      # Setup logger mock
      allow(ADK).to receive(:logger).and_return(double(error: nil))
      
      # Trigger a refresh success
      refreshed = exchanged_credential.with(access_token: 'new_token')
      allow(oauth_scheme).to receive(:refresh_token).and_return(refreshed)
      allow(exchanged_credential).to receive(:refreshable?).and_return(true)
      
      # Should not propagate the exception
      expect {
        manager.refresh_token(oauth_scheme, oauth_credential, exchanged_credential)
      }.not_to raise_error
      
      # Should log the error
      expect(ADK.logger).to have_received(:error).with(/Error in refresh_success callback/)
    end
  end
end 