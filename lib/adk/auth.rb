# File: lib/adk/auth.rb
# frozen_string_literal: true

require_relative 'auth/error'
require_relative 'auth/scheme'
require_relative 'auth/credential'
require_relative 'auth/config'
require_relative 'auth/exchanged_credential'
require_relative 'auth/encryption'
require_relative 'auth/token_store'
require_relative 'auth/schemes'

module ADK
  # The Auth module provides authentication capabilities for ADK tools.
  # It supports various authentication schemes such as API Key, Bearer Token,
  # OAuth2, OpenID Connect, and Service Accounts.
  #
  # @example Configure a tool with OAuth2 authentication
  #   scheme = ADK::Auth::Schemes::OAuth2.new(
  #     authorization_url: 'https://example.com/oauth2/auth',
  #     token_url: 'https://example.com/oauth2/token',
  #     scopes: ['read', 'write']
  #   )
  #
  #   credential = ADK::Auth::Credential.new(
  #     auth_type: :oauth2,
  #     client_id: 'my-client-id',
  #     client_secret: 'ENV:MY_CLIENT_SECRET'
  #   )
  #
  #   tool = MyTool.new(auth_scheme: scheme, auth_credential: credential)
  #
  module Auth
    # Version of the authentication module
    VERSION = '0.1.0'

    class << self
      # Returns a unique identifier for a request
      # @return [String] A unique ID in UUID format
      def generate_request_id
        require 'securerandom'
        SecureRandom.uuid
      end
    end
  end
end 