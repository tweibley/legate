# frozen_string_literal: true

require 'spec_helper'
require 'legate/auth/coordinators/service_account_coordinator'
require 'legate/auth/schemes/service_account'
require 'legate/auth/credential'
require 'legate/auth/token_store'
require 'securerandom'

RSpec.describe Legate::Auth::Coordinators::ServiceAccountCoordinator do
  # Add a generate_request_id method to Legate::Auth module if it doesn't exist
  before(:all) do
    Legate::Auth.define_singleton_method(:generate_request_id) { SecureRandom.uuid } unless Legate::Auth.respond_to?(:generate_request_id)
  end

  # Create mock implementations for testing
  let(:service_account_scheme) do
    instance_double(
      Legate::Auth::Schemes::ServiceAccount,
      scheme_type: :service_account,
      audience: 'https://test-audience.example.com',
      scopes: %w[email profile],
      token_url: 'https://test-token-url.example.com',
      exchange_token: nil,
      refresh_token: nil
    )
  end

  let(:session_service) do
    instance_double('Legate::SessionService::Base')
  end

  let(:token_store) do
    instance_double(Legate::Auth::TokenStore)
  end

  let(:credential) do
    instance_double(
      Legate::Auth::Credential,
      auth_type: :service_account,
      '[]' => nil
    )
  end

  let(:exchanged_credential) do
    instance_double(
      Legate::Auth::ExchangedCredential,
      auth_type: :service_account,
      access_token: 'test-access-token',
      token_type: 'Bearer'
    )
  end

  before do
    ENV['RSPEC_ENV'] = 'test'

    # Allow the service_account_scheme double to receive is_a?
    allow(service_account_scheme).to receive(:is_a?).with(Legate::Auth::Schemes::ServiceAccount).and_return(true)

    # Stub credential to allow auth_type check
    allow(credential).to receive(:auth_type).and_return(:service_account)

    # Stub the exchange_token method to return a test token
    allow(service_account_scheme).to receive(:exchange_token)
      .with(credential)
      .and_return(exchanged_credential)

    # Stub the refresh_token method to return a test token
    allow(service_account_scheme).to receive(:refresh_token)
      .with(any_args)
      .and_return(exchanged_credential)

    # Ensure token_store can receive store
    allow(token_store).to receive(:store).and_return(true)
  end

  after do
    ENV.delete('RSPEC_ENV')
  end

  describe '#initialize' do
    it 'initializes with valid parameters' do
      coordinator = described_class.new(
        scheme: service_account_scheme,
        credential: credential,
        session_service: session_service
      )

      expect(coordinator).to be_a(described_class)
    end

    it 'raises an error with invalid scheme type' do
      invalid_scheme = instance_double('Legate::Auth::Scheme')
      allow(invalid_scheme).to receive(:is_a?).with(Legate::Auth::Schemes::ServiceAccount).and_return(false)

      expect {
        described_class.new(
          scheme: invalid_scheme,
          credential: credential,
          session_service: session_service
        )
      }.to raise_error(ArgumentError, /Expected a ServiceAccount scheme/)
    end

    it 'raises an error with invalid credential type' do
      invalid_credential = instance_double(Legate::Auth::Credential)
      allow(invalid_credential).to receive(:auth_type).and_return(:oauth2)

      expect {
        described_class.new(
          scheme: service_account_scheme,
          credential: invalid_credential,
          session_service: session_service
        )
      }.to raise_error(ArgumentError, /Credential must have auth_type :service_account/)
    end
  end

  describe '#authenticate' do
    let(:coordinator) do
      # Override instance_eval to expose authenticate method
      coordinator = described_class.new(
        scheme: service_account_scheme,
        credential: credential,
        session_service: session_service
      )
      # Make the protected method public for testing
      coordinator.define_singleton_method(:authenticate_test) { authenticate }
      coordinator
    end

    it 'exchanges tokens non-interactively' do
      result = coordinator.authenticate_test

      expect(result).to eq(exchanged_credential)
      expect(service_account_scheme).to have_received(:exchange_token).with(credential)
    end

    it 'stores tokens when token_store is provided' do
      # Create a new coordinator with token store
      coordinator_with_store = described_class.new(
        scheme: service_account_scheme,
        credential: credential,
        session_service: session_service,
        token_store: token_store
      )
      coordinator_with_store.define_singleton_method(:authenticate_test) { authenticate }

      # Expect token_store to receive store with a key and the token
      allow(token_store).to receive(:store).with(String, exchanged_credential).and_return(true)

      result = coordinator_with_store.authenticate_test

      expect(result).to eq(exchanged_credential)
      expect(token_store).to have_received(:store).with(String, exchanged_credential)
    end
  end

  describe '#refresh' do
    let(:coordinator) do
      # Override instance_eval to expose refresh method
      coordinator = described_class.new(
        scheme: service_account_scheme,
        credential: credential,
        session_service: session_service
      )
      # Make the protected method public for testing
      coordinator.define_singleton_method(:refresh_test) { |token| refresh(token) }
      coordinator
    end

    it 'refreshes tokens non-interactively' do
      result = coordinator.refresh_test(exchanged_credential)

      expect(result).to eq(exchanged_credential)
      expect(service_account_scheme).to have_received(:refresh_token).with(exchanged_credential, credential)
    end

    it 'stores refreshed tokens when token_store is provided' do
      # Create a new coordinator with token store
      coordinator_with_store = described_class.new(
        scheme: service_account_scheme,
        credential: credential,
        session_service: session_service,
        token_store: token_store
      )
      coordinator_with_store.define_singleton_method(:refresh_test) { |token| refresh(token) }

      # Expect token_store to receive store with a key and the token
      allow(token_store).to receive(:store).with(String, exchanged_credential).and_return(true)

      result = coordinator_with_store.refresh_test(exchanged_credential)

      expect(result).to eq(exchanged_credential)
      expect(token_store).to have_received(:store).with(String, exchanged_credential)
    end
  end

  describe '#generate_token_key' do
    let(:coordinator) do
      # Override instance_eval to expose generate_token_key method
      coordinator = described_class.new(
        scheme: service_account_scheme,
        credential: credential,
        session_service: session_service
      )
      # Make the private method public for testing
      coordinator.define_singleton_method(:generate_token_key_test) { generate_token_key }
      coordinator
    end

    it 'generates a unique key based on scheme and credential' do
      # Prepare the credential to respond to [] method for client_email
      allow(credential).to receive(:[]).with(:client_email).and_return('service-account@example.com')

      key = coordinator.generate_token_key_test

      # The key should contain the scheme type and scopes
      expect(key).to include('service_account')
      expect(key).to include('service-account@example.com')
      expect(key).to include('email,profile')
    end
  end
end
