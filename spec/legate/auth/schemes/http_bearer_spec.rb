# File: spec/legate/auth/schemes/http_bearer_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'legate/auth/scheme'
require 'legate/auth/error'
require 'legate/auth/schemes/http_bearer'
require 'legate/auth/credential'
require 'legate/auth/exchanged_credential'

RSpec.describe Legate::Auth::Schemes::HTTPBearer do
  describe '#initialize' do
    it 'creates a new HTTP Bearer scheme' do
      scheme = described_class.new
      expect(scheme).to be_a(Legate::Auth::Schemes::HTTPBearer)
    end
  end

  describe '#scheme_type' do
    it 'returns :http_bearer' do
      scheme = described_class.new
      expect(scheme.scheme_type).to eq(:http_bearer)
    end
  end

  describe '#apply_to_request' do
    let(:scheme) { described_class.new }

    context 'with a Credential' do
      it 'adds the bearer token to the Authorization header' do
        credential = Legate::Auth::Credential.new(
          auth_type: :http_bearer,
          bearer_token: 'test-token'
        )

        request = {}
        result = scheme.apply_to_request(request, credential)

        expect(result[:headers]).to include('Authorization' => 'Bearer test-token')
      end

      it 'resolves environment variables for the token' do
        ENV['TEST_BEARER_TOKEN'] = 'env-token'
        credential = Legate::Auth::Credential.new(
          auth_type: :http_bearer,
          bearer_token: 'ENV:TEST_BEARER_TOKEN'
        )

        request = {}
        result = scheme.apply_to_request(request, credential)

        expect(result[:headers]).to include('Authorization' => 'Bearer env-token')

        # Clean up
        ENV.delete('TEST_BEARER_TOKEN')
      end

      it 'raises an error if the bearer token is missing' do
        # Create a double that simulates a credential without a bearer token
        credential_without_token = instance_double(
          'Legate::Auth::Credential',
          '[]': nil, # Return nil for any key access
          is_a?: true # Pretend to be a Credential
        )
        allow(credential_without_token).to receive(:[]).with(any_args).and_return(nil)

        expect {
          scheme.apply_to_request({}, credential_without_token)
        }.to raise_error(Legate::Auth::Error, /Bearer token not found in credential/)
      end
    end

    context 'with an ExchangedCredential' do
      it 'uses the access token as the bearer token' do
        # Create a mock ExchangedCredential with an access token
        exchanged_credential = instance_double('Legate::Auth::ExchangedCredential')
        allow(exchanged_credential).to receive(:is_a?).with(anything).and_return(false)
        allow(exchanged_credential).to receive(:is_a?).with(Legate::Auth::ExchangedCredential).and_return(true)

        # Set up the [] method to handle different arguments
        allow(exchanged_credential).to receive(:[]).with(:bearer_token).and_return(nil)
        allow(exchanged_credential).to receive(:[]).with(:access_token).and_return('access-token')
        allow(exchanged_credential).to receive(:[]).with(:token).and_return(nil)

        request = {}
        result = scheme.apply_to_request(request, exchanged_credential)

        expect(result[:headers]).to include('Authorization' => 'Bearer access-token')
      end

      it 'raises an error if the access token is missing' do
        # Create a mock ExchangedCredential without an access token
        exchanged_credential_without_token = instance_double('Legate::Auth::ExchangedCredential')
        allow(exchanged_credential_without_token).to receive(:is_a?).with(anything).and_return(false)
        allow(exchanged_credential_without_token).to receive(:is_a?).with(Legate::Auth::ExchangedCredential).and_return(true)

        # Set up the [] method to return nil for all token types
        allow(exchanged_credential_without_token).to receive(:[]).with(:bearer_token).and_return(nil)
        allow(exchanged_credential_without_token).to receive(:[]).with(:access_token).and_return(nil)
        allow(exchanged_credential_without_token).to receive(:[]).with(:token).and_return(nil)

        expect {
          scheme.apply_to_request({}, exchanged_credential_without_token)
        }.to raise_error(Legate::Auth::Error, /Bearer token not found in credential/)
      end
    end

    it 'preserves existing headers' do
      credential = Legate::Auth::Credential.new(
        auth_type: :http_bearer,
        bearer_token: 'test-token'
      )

      request = { headers: { 'Content-Type' => 'application/json' } }
      result = scheme.apply_to_request(request, credential)

      expect(result[:headers]).to include(
        'Authorization' => 'Bearer test-token',
        'Content-Type' => 'application/json'
      )
    end
  end

  describe '#to_h' do
    it 'returns a hash with the scheme type' do
      scheme = described_class.new
      expect(scheme.to_h).to eq({ type: :http_bearer })
    end
  end
end
