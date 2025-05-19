# File: spec/adk/auth/token_store_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/token_store'
require 'adk/auth/exchanged_credential'

RSpec.describe ADK::Auth::TokenStore do
  let(:session_service) { instance_double('ADK::SessionService::Base') }
  let(:token_store) { described_class.new(session_service) }
  let(:token) do
    ADK::Auth::ExchangedCredential.new(
      auth_type: :oauth2,
      access_token: 'test-access-token',
      refresh_token: 'test-refresh-token',
      expires_in: 3600
    )
  end
  let(:cache_key) { 'auth_test_key' }

  describe '#store' do
    it 'serializes and stores the token' do
      allow(session_service).to receive(:save_scoped_state)
      
      result = token_store.store(cache_key, token)
      
      expect(session_service).to have_received(:save_scoped_state).with('auth', cache_key, token.to_h)
      expect(result).to be true
    end
    
    it 'returns false for invalid token types' do
      result = token_store.store(cache_key, 'not-a-token')
      
      expect(result).to be false
    end
    
    it 'handles exceptions' do
      allow(session_service).to receive(:save_scoped_state).and_raise('Storage error')
      allow(ADK).to receive_message_chain(:logger, :error)
      
      result = token_store.store(cache_key, token)
      
      expect(result).to be false
    end
  end
  
  describe '#get' do
    it 'retrieves and deserializes stored tokens' do
      allow(session_service).to receive(:load_scoped_state).and_return(token.to_h)
      
      result = token_store.get(cache_key)
      
      expect(result).to be_a(ADK::Auth::ExchangedCredential)
      expect(result.access_token).to eq(token.access_token)
    end
    
    it 'returns nil if no token is found' do
      allow(session_service).to receive(:load_scoped_state).and_return(nil)
      
      result = token_store.get(cache_key)
      
      expect(result).to be_nil
    end
    
    it 'clears and returns nil for expired tokens' do
      expired_token = token.dup
      expired_token.instance_variable_set(:@expires_at, Time.now - 60) # Set expiration to 1 minute ago
      
      allow(session_service).to receive(:load_scoped_state).and_return(expired_token.to_h)
      allow(ADK::Auth::ExchangedCredential).to receive(:from_h).and_return(expired_token)
      allow(token_store).to receive(:clear)
      allow(ADK).to receive_message_chain(:logger, :debug)
      
      result = token_store.get(cache_key)
      
      expect(token_store).to have_received(:clear).with(cache_key)
      expect(result).to be_nil
    end
    
    it 'handles exceptions' do
      allow(session_service).to receive(:load_scoped_state).and_raise('Retrieval error')
      allow(ADK).to receive_message_chain(:logger, :error)
      
      result = token_store.get(cache_key)
      
      expect(result).to be_nil
    end
  end
  
  describe '#clear' do
    it 'clears the token at the given key' do
      allow(session_service).to receive(:clear_scoped_state)
      
      result = token_store.clear(cache_key)
      
      expect(session_service).to have_received(:clear_scoped_state).with('auth', cache_key)
      expect(result).to be true
    end
    
    it 'handles exceptions' do
      allow(session_service).to receive(:clear_scoped_state).and_raise('Clearing error')
      allow(ADK).to receive_message_chain(:logger, :error)
      
      result = token_store.clear(cache_key)
      
      expect(result).to be false
    end
  end
  
  describe '#clear_all' do
    it 'clears all tokens in the auth scope' do
      allow(session_service).to receive(:clear_scoped_state)
      
      result = token_store.clear_all
      
      expect(session_service).to have_received(:clear_scoped_state).with('auth', '*')
      expect(result).to be true
    end
    
    it 'handles exceptions' do
      allow(session_service).to receive(:clear_scoped_state).and_raise('Clearing error')
      allow(ADK).to receive_message_chain(:logger, :error)
      
      result = token_store.clear_all
      
      expect(result).to be false
    end
  end
end 