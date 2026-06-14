# File: lib/legate/auth/schemes.rb
# frozen_string_literal: true

require_relative 'schemes/api_key'
require_relative 'schemes/http_bearer'
require_relative 'schemes/oauth2'
require_relative 'schemes/openid_connect'
require_relative 'schemes/service_account'
require_relative 'schemes/google_service_account'

module Legate
  module Auth
    # Namespace module for authentication schemes
    module Schemes
      # Create a scheme instance based on type
      # @param type [Symbol] The scheme type
      # @param options [Hash] Options for the scheme
      # @return [Legate::Auth::Scheme] The created scheme
      # @raise [Legate::Auth::ConfigurationError] If the scheme type is invalid
      def self.create(type, **options)
        case type.to_sym
        when :api_key
          ApiKey.new(**options)
        when :http_bearer
          HTTPBearer.new(**options)
        when :oauth2
          OAuth2.new(**options)
        when :oidc, :openid_connect
          OpenIDConnect.new(**options)
        when :service_account
          ServiceAccount.new(**options)
        when :google_service_account
          GoogleServiceAccount.new(**options)
        else
          raise Legate::Auth::ConfigurationError, "Unknown scheme type: #{type}"
        end
      end
    end
  end
end
