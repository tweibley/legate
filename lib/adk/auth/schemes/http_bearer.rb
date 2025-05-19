# File: lib/adk/auth/schemes/http_bearer.rb
# frozen_string_literal: true

require_relative '../scheme'
require_relative '../error'
require_relative '../credential'
require_relative '../exchanged_credential'

module ADK
  module Auth
    module Schemes
      # Implements HTTP Bearer token authentication
      # Sends authentication using the standard Authorization header with Bearer scheme
      class HTTPBearer < ADK::Auth::Scheme
        # Initialize a new HTTP Bearer scheme
        # @param bearer_format [String, nil] Optional format for the bearer token (e.g., 'JWT')
        def initialize(bearer_format: nil)
          @bearer_format = bearer_format
        end
        
        # @return [Symbol] The scheme type
        def scheme_type
          :http_bearer
        end
        
        # Validates the scheme configuration
        # @raise [ADK::Auth::SchemeValidationError] If the configuration is invalid
        def validate!
          # Nothing to validate for the basic configuration
        end
        
        # Applies the Bearer token to a request
        # @param request [Hash] The request to apply the token to
        # @param credential [ADK::Auth::Credential, ADK::Auth::ExchangedCredential] The credential with the token
        # @return [Hash] The updated request
        # @raise [ADK::Auth::CredentialError] If the credential is missing the token
        def apply_to_request(request, credential)
          token = get_token(credential)
          request = request.dup
          
          request[:headers] ||= {}
          request[:headers]['Authorization'] = "Bearer #{token}"
          
          request
        end
        
        # Convert to a hash
        # @return [Hash] A hash representation of the scheme
        def to_h
          super.merge(
            bearer_format: @bearer_format
          ).compact
        end
        
        private
        
        # Extract the token from a credential
        # @param credential [ADK::Auth::Credential, ADK::Auth::ExchangedCredential] The credential
        # @return [String] The token
        # @raise [ADK::Auth::CredentialError] If the credential is missing the token
        def get_token(credential)
          if credential.is_a?(ADK::Auth::Credential)
            # For initial credentials
            token = credential[:bearer_token, resolve_env: true]
          elsif credential.is_a?(ADK::Auth::ExchangedCredential)
            # For exchanged credentials
            token = credential.access_token
          else
            token = nil
          end
          
          unless token && !token.empty?
            raise ADK::Auth::CredentialError, 'Bearer token is missing from credential'
          end
          
          token
        end
      end
    end
  end
end 