# File: lib/adk/auth/config.rb
# frozen_string_literal: true

module ADK
  module Auth
    # Configuration container used during the authentication flow.
    # Holds the authentication scheme, credential, and request/response details
    # needed for interactive authentication flows.
    class Config
      # @return [ADK::Auth::Scheme] The authentication scheme
      attr_reader :scheme

      # @return [ADK::Auth::Credential] The credential information
      attr_reader :credential

      # @return [String, nil] The unique ID for this authentication request
      attr_reader :auth_request_id

      # @return [String, nil] The authorization URI for interactive flows
      attr_accessor :auth_uri

      # @return [String, nil] The redirect URI for OAuth2/OIDC flows
      attr_accessor :redirect_uri

      # @return [String, nil] The state parameter for CSRF protection
      attr_accessor :state

      # @return [String, nil] The authorization response URI from the provider
      attr_accessor :auth_response_uri

      # @return [Hash, nil] Additional options for the authentication process
      attr_accessor :options

      # Initialize a new authentication configuration
      # @param scheme [ADK::Auth::Scheme] The authentication scheme
      # @param credential [ADK::Auth::Credential] The credential information
      # @param auth_request_id [String, nil] The unique ID for this authentication request
      # @param options [Hash, nil] Additional options for the authentication process
      def initialize(scheme:, credential:, auth_request_id: nil, options: {})
        @scheme = scheme
        @credential = credential
        @auth_request_id = auth_request_id || ADK::Auth.generate_request_id
        @options = options || {}
        @auth_uri = nil
        @redirect_uri = nil
        @state = nil
        @auth_response_uri = nil
      end

      # Build the authorization URI for interactive flows
      # @param redirect_uri [String, nil] The redirect URI for the authorization request
      # @param state [String, nil] A state parameter for CSRF protection
      # @return [String, nil] The authorization URI, or nil if not applicable
      def build_authorization_uri(redirect_uri = nil, state = nil)
        @redirect_uri = redirect_uri
        @state = state || @options[:state] || SecureRandom.hex(16)
        @auth_uri = @scheme.build_authorization_uri(self, @redirect_uri, @state)
      end

      # Convert to a hash for serialization
      # @param include_credentials [Boolean] Whether to include credential details (use carefully)
      # @return [Hash] A hash representation of the config
      def to_h(include_credentials: false)
        {
          auth_request_id: @auth_request_id,
          scheme_type: @scheme.scheme_type,
          auth_uri: @auth_uri,
          redirect_uri: @redirect_uri,
          state: @state,
          auth_response_uri: @auth_response_uri,
          options: @options
        }.tap do |h|
          h[:credential] = @credential.to_h if include_credentials
        end
      end

      # Creates a Config from a hash representation
      # @param hash [Hash] The hash representation
      # @param scheme [ADK::Auth::Scheme] The authentication scheme (required if not recreating from complete data)
      # @param credential [ADK::Auth::Credential] The credential information (required if not recreating from complete data)
      # @return [ADK::Auth::Config] A new Config instance
      # @raise [ADK::Auth::ConfigurationError] If required parameters are missing
      def self.from_h(hash, scheme: nil, credential: nil)
        scheme ||= hash[:scheme] 
        credential ||= hash[:credential]
        
        unless scheme && credential
          raise ADK::Auth::ConfigurationError, 'Scheme and credential must be provided'
        end
        
        config = new(
          scheme: scheme,
          credential: credential,
          auth_request_id: hash[:auth_request_id],
          options: hash[:options] || {}
        )
        
        config.auth_uri = hash[:auth_uri]
        config.redirect_uri = hash[:redirect_uri]
        config.state = hash[:state]
        config.auth_response_uri = hash[:auth_response_uri]
        
        config
      end
      
      # Validates a response against this configuration
      # @param response_config [ADK::Auth::Config] The response configuration
      # @return [Boolean] True if the response is valid for this request
      # @raise [ADK::Auth::ConfigurationError] If the response is invalid
      def validate_response!(response_config)
        # Check request ID
        unless response_config.auth_request_id == @auth_request_id
          raise ADK::Auth::ConfigurationError, 'Authentication response ID does not match request ID'
        end
        
        # Check that we have an auth response URI
        unless response_config.auth_response_uri
          raise ADK::Auth::ConfigurationError, 'Authentication response does not contain a response URI'
        end
        
        # Check state if we had one
        if @state && response_config.state && response_config.state != @state
          raise ADK::Auth::ConfigurationError, 'Authentication response state does not match request state'
        end
        
        true
      end
    end
  end
end 