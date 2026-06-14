# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/mock_auth_providers'
require_relative '../support/auth_test_stubs'

RSpec.describe 'Fiber-based authentication flow' do
  let(:mock_provider) { Legate::Test::Support::MockAuthProviders::MockOAuth2Provider.new }
  let(:client_id) { mock_provider.config.client_id }
  let(:client_secret) { mock_provider.config.client_secret }
  let(:redirect_uri) { mock_provider.config.redirect_uri }
  let(:provider_uri) { mock_provider.config.issuer }

  before do
    # Setup mock endpoints
    mock_provider.setup_stubs
  end

  describe 'OAuth2 interactive authentication' do
    let(:oauth2_config) do
      {
        provider_uri: provider_uri,
        client_id: client_id,
        client_secret: client_secret,
        redirect_uri: redirect_uri,
        scope: 'read write'
      }
    end

    let(:auth_scheme) { Legate::Auth::TestStubs::OAuth2.new(oauth2_config) }

    it 'completes a full authentication flow with fiber suspension and resumption' do
      # The fiber that will run our authentication flow
      fiber = Fiber.new do
        # Start OAuth2 flow
        auth_url = auth_scheme.authorization_url(state: 'test_state')

        # Yield control back to the test with the authorization URL
        authorization_code = Fiber.yield(auth_url)

        # Exchange the code for token
        token_response = auth_scheme.exchange_authorization_code(authorization_code)

        # Return the token response
        token_response
      end

      # Start the fiber, it will return the authorization URL and pause
      auth_url = fiber.resume

      # Verify the authorization URL
      expect(auth_url).to include(mock_provider.config.authorization_endpoint)
      expect(auth_url).to include("client_id=#{client_id}")

      # Simulate user completing authorization and getting a code
      # In a real flow, this would happen in a browser
      auth_code = 'simulated_auth_code_from_callback'

      # Resume the fiber with the authorization code
      token_response = fiber.resume(auth_code)

      # Verify we got our token
      expect(token_response).to be_a(Hash)
      expect(token_response[:access_token]).to be_a(String)
      expect(token_response[:token_type]).to eq('Bearer')
      expect(token_response[:refresh_token]).to be_a(String)
    end
  end

  describe 'Fiber-based OAuth2 coordinators' do
    let(:oauth2_config) do
      {
        scheme: 'oauth2',
        provider_uri: provider_uri,
        client_id: client_id,
        client_secret: client_secret,
        redirect_uri: redirect_uri,
        scope: 'read write'
      }
    end

    let(:coordinator) { Legate::Auth::Coordinators::FiberCoordinator.new(oauth2_config) }

    it 'authenticates using the coordinator' do
      # Start authentication in a fiber
      fiber = Fiber.new do
        coordinator.authenticate
      end

      # First resume will start the process and return the auth URL
      result = fiber.resume

      # The result should be a suspension with an auth URL
      expect(result).to be_a(Legate::Auth::Coordinators::FiberSuspension)
      expect(result.url).to include(mock_provider.config.authorization_endpoint)

      # Simulate the callback with a code
      callback_data = { code: 'test_auth_code', state: result.state }

      # Resume with the code
      credentials = fiber.resume(callback_data)

      # Verify credentials
      expect(credentials).to be_a(Legate::Auth::Credentials)
      expect(credentials.access_token).to be_a(String)
      expect(credentials.token_type).to eq('Bearer')
      expect(credentials.refresh_token).to be_a(String)
    end

    it 'handles token refresh' do
      # Setup: Get initial credentials
      initial_credentials = nil

      fiber = Fiber.new do
        coordinator.authenticate
      end

      result = fiber.resume
      callback_data = { code: 'test_auth_code', state: result.state }
      initial_credentials = fiber.resume(callback_data)

      # Now test refreshing
      refreshed_credentials = coordinator.refresh(initial_credentials)

      # Verify refreshed credentials
      expect(refreshed_credentials).to be_a(Legate::Auth::Credentials)
      expect(refreshed_credentials.access_token).to be_a(String)
      expect(refreshed_credentials.access_token).not_to eq(initial_credentials.access_token)
      expect(refreshed_credentials.refresh_token).to be_a(String)
      expect(refreshed_credentials.refresh_token).not_to eq(initial_credentials.refresh_token)
    end

    it 'raises error when authentication fails' do
      # Simulate a failed token exchange by creating a bad configuration
      bad_config = oauth2_config.merge(client_secret: 'wrong_secret')
      bad_coordinator = Legate::Auth::Coordinators::FiberCoordinator.new(bad_config)

      # Mock error response for wrong client secret
      WebMock.stub_request(:post, "#{provider_uri}/oauth/token")
             .with(body: hash_including('client_secret' => 'wrong_secret'))
             .to_return(
               status: 401,
               headers: { 'Content-Type' => 'application/json' },
               body: { error: 'invalid_client' }.to_json
             )

      # Start authentication in a fiber
      fiber = Fiber.new do
        bad_coordinator.authenticate
      end

      # First resume will start the process and return the auth URL
      result = fiber.resume

      # Simulate the callback with a code
      callback_data = { code: 'test_auth_code', state: result.state }

      # The token exchange should fail
      expect {
        fiber.resume(callback_data)
      }.to raise_error(Legate::Auth::Errors::AuthenticationError)
    end
  end
end
