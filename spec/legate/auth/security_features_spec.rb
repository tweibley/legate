# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/auth_test_stubs'

RSpec.describe 'Authentication Security Features' do
  describe 'Token Storage in Session Service' do
    let(:session_service) { Legate::SessionService::InMemory.new }
    let(:session_id) { SecureRandom.uuid }
    let(:sensitive_data) do
      {
        access_token: 'very_sensitive_access_token',
        refresh_token: 'very_sensitive_refresh_token',
        id_token: 'very_sensitive_id_token',
        client_secret: 'very_sensitive_client_secret'
      }
    end

    before do
      Legate.configure do |config|
        config.session_service = session_service
      end
    end

    it 'stores and retrieves auth data correctly' do
      # Store and retrieve the data
      session_service.set_auth_data(session_id, sensitive_data)
      retrieved_data = session_service.get_auth_data(session_id)

      # Verify the data matches
      expect(retrieved_data[:access_token]).to eq(sensitive_data[:access_token])
      expect(retrieved_data[:refresh_token]).to eq(sensitive_data[:refresh_token])
      expect(retrieved_data[:id_token]).to eq(sensitive_data[:id_token])
      expect(retrieved_data[:client_secret]).to eq(sensitive_data[:client_secret])
    end

    it 'handles non-sensitive data appropriately' do
      non_sensitive_data = {
        token_type: 'Bearer',
        expires_in: 3600,
        scope: 'read write'
      }

      # Store and retrieve the data
      session_service.set_auth_data(session_id, non_sensitive_data)
      retrieved_data = session_service.get_auth_data(session_id)

      # Verify the data matches
      expect(retrieved_data[:token_type]).to eq(non_sensitive_data[:token_type])
      expect(retrieved_data[:expires_in]).to eq(non_sensitive_data[:expires_in])
      expect(retrieved_data[:scope]).to eq(non_sensitive_data[:scope])
    end
  end

  describe 'Credential Security' do
    let(:credentials) do
      Legate::Auth::Credentials.new(
        access_token: 'test_access_token',
        refresh_token: 'test_refresh_token',
        token_type: 'Bearer',
        expires_in: 3600
      )
    end

    it 'masks sensitive data in string representation' do
      # Convert to string
      string_rep = credentials.to_s

      # Check that tokens are masked
      expect(string_rep).not_to include('test_access_token')
      expect(string_rep).not_to include('test_refresh_token')
      expect(string_rep).to include('***')
    end

    it 'masks sensitive data in debug output' do
      # Get debug output
      debug_rep = credentials.inspect

      # Check that tokens are masked
      expect(debug_rep).not_to include('test_access_token')
      expect(debug_rep).not_to include('test_refresh_token')
      expect(debug_rep).to include('***')
    end

    it 'does not expose sensitive data through standard methods' do
      # Convert to hash
      hash_rep = credentials.to_h

      # The hash should contain masked versions
      expect(hash_rep[:access_token]).not_to eq('test_access_token')
      expect(hash_rep[:refresh_token]).not_to eq('test_refresh_token')
      expect(hash_rep[:access_token]).to include('***')
    end

    it 'allows access to sensitive data through secure methods' do
      # Access directly using proper methods
      expect(credentials.access_token).to eq('test_access_token')
      expect(credentials.refresh_token).to eq('test_refresh_token')
    end
  end

  describe 'CSRF Protection' do
    let(:secure_random_original) { SecureRandom.method(:hex) }

    before do
      # Stub SecureRandom to return predictable values for testing
      allow(SecureRandom).to receive(:hex).and_return('test_csrf_token')
    end

    after do
      # Restore original SecureRandom
      allow(SecureRandom).to receive(:hex).and_call_original
    end

    it 'generates and verifies CSRF tokens' do
      # Generate token
      csrf_token = Legate::Auth::Security.generate_csrf_token

      # Verify it's the expected token (we stubbed SecureRandom)
      expect(csrf_token).to eq('test_csrf_token')

      # Verify with the token
      expect(Legate::Auth::Security.verify_csrf_token(csrf_token)).to be true

      # Verify with wrong token
      expect(Legate::Auth::Security.verify_csrf_token('wrong_token')).to be false
    end

    it 'includes and verifies CSRF tokens in OAuth2 flow' do
      # Create OAuth2 scheme
      oauth2_scheme = Legate::Auth::TestStubs::OAuth2.new({
                                                            provider_uri: 'https://example.com',
                                                            client_id: 'test_client',
                                                            redirect_uri: 'http://localhost/callback'
                                                          })

      # Get authorization URL
      auth_url = oauth2_scheme.authorization_url

      # Verify URL contains state parameter
      expect(auth_url).to include('state=test_csrf_token')

      # Simulate callback with correct state
      expect(oauth2_scheme.verify_callback_state('test_csrf_token')).to be true

      # Simulate callback with incorrect state
      expect(oauth2_scheme.verify_callback_state('wrong_state')).to be false
    end
  end
end
