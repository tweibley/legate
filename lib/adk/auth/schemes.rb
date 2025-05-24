# File: lib/adk/auth/schemes.rb
# frozen_string_literal: true

require_relative 'schemes/api_key'
require_relative 'schemes/http_bearer'
require_relative 'schemes/oauth2'
require_relative 'schemes/openid_connect'

module ADK
  module Auth
    # Namespace module for authentication schemes
    module Schemes
      # Create a scheme instance based on type
      # @param type [Symbol] The scheme type
      # @param options [Hash] Options for the scheme
      # @return [ADK::Auth::Scheme] The created scheme
      # @raise [ADK::Auth::ConfigurationError] If the scheme type is invalid
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
        else
          raise ADK::Auth::ConfigurationError, "Unknown scheme type: #{type}"
        end
      end
    end
  end
end 