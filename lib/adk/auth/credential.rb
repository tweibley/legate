# File: lib/adk/auth/credential.rb
# frozen_string_literal: true

module ADK
  module Auth
    # Represents authentication credentials required by different schemes.
    # Handles different types of credentials such as API keys, OAuth2 client credentials,
    # service account keys, and more.
    #
    # @example API Key credential
    #   credential = ADK::Auth::Credential.new(
    #     auth_type: :api_key,
    #     api_key: 'my-api-key'
    #   )
    #
    # @example OAuth2 credential with environment variable
    #   credential = ADK::Auth::Credential.new(
    #     auth_type: :oauth2,
    #     client_id: 'my-client-id',
    #     client_secret: 'ENV:MY_CLIENT_SECRET'
    #   )
    class Credential
      # Valid credential types
      VALID_TYPES = %i[api_key oauth2 oidc service_account http_bearer].freeze

      # Prefix for environment variable references
      ENV_PREFIX = 'ENV:'.freeze

      # @return [Symbol] The type of authentication
      attr_reader :auth_type

      # Initialize a new credential
      # @param auth_type [Symbol] The type of authentication (:api_key, :oauth2, :oidc, :service_account, :http_bearer)
      # @param kwargs [Hash] Additional attributes for the specific auth type
      # @raise [ADK::Auth::CredentialError] If the credential is invalid
      def initialize(auth_type:, **kwargs)
        @auth_type = auth_type.to_sym
        @attributes = kwargs

        validate_auth_type!
        validate_required_attributes!
      end

      # Get an attribute value
      # @param name [Symbol, String] The attribute name
      # @param resolve_env [Boolean] Whether to resolve environment variables
      # @return [Object, nil] The attribute value, or nil if not present
      # @raise [ADK::Auth::EnvironmentVariableNotFoundError] If an environment variable is not found
      def [](name, resolve_env: true)
        attr_name = name.to_sym
        value = @attributes[attr_name]
        
        if resolve_env && value.is_a?(String) && value.start_with?(ENV_PREFIX)
          resolve_environment_variable(value)
        else
          value
        end
      end

      # Set an attribute value
      # @param name [Symbol, String] The attribute name
      # @param value [Object] The attribute value
      def []=(name, value)
        @attributes[name.to_sym] = value
      end

      # Convert to a hash
      # @param resolve_env [Boolean] Whether to resolve environment variables
      # @return [Hash] A hash representation of the credential
      def to_h(resolve_env: false)
        result = { auth_type: @auth_type }
        
        @attributes.each do |key, value|
          if resolve_env && value.is_a?(String) && value.start_with?(ENV_PREFIX)
            result[key] = resolve_environment_variable(value)
          else
            result[key] = value
          end
        end
        
        result
      end

      # Check if the credential has an attribute
      # @param name [Symbol, String] The attribute name
      # @return [Boolean] True if the attribute exists
      def has_attribute?(name)
        @attributes.key?(name.to_sym)
      end

      private

      # Validate the authentication type
      # @raise [ADK::Auth::CredentialError] If the authentication type is invalid
      def validate_auth_type!
        unless VALID_TYPES.include?(@auth_type)
          raise ADK::Auth::CredentialError, 
                "Invalid auth_type: #{@auth_type}. Must be one of: #{VALID_TYPES.join(', ')}"
        end
      end

      # Validate required attributes based on the authentication type
      # @raise [ADK::Auth::CredentialError] If required attributes are missing
      def validate_required_attributes!
        required_attrs = required_attributes_for_type
        missing_attrs = required_attrs.reject { |attr| @attributes.key?(attr) }

        unless missing_attrs.empty?
          raise ADK::Auth::CredentialError, 
                "Missing required attributes for #{@auth_type}: #{missing_attrs.join(', ')}"
        end
      end

      # Required attributes based on the authentication type
      # @return [Array<Symbol>] The required attributes
      def required_attributes_for_type
        case @auth_type
        when :api_key
          [:api_key]
        when :oauth2
          [:client_id]
        when :oidc
          [:client_id]
        when :service_account
          [:service_account_json]
        when :http_bearer
          [:bearer_token]
        else
          []
        end
      end

      # Resolve an environment variable reference
      # @param value [String] The environment variable reference (e.g., "ENV:VARIABLE_NAME")
      # @return [String] The resolved value
      # @raise [ADK::Auth::EnvironmentVariableNotFoundError] If the environment variable is not found
      def resolve_environment_variable(value)
        env_name = value[ENV_PREFIX.length..-1]
        env_value = ENV[env_name]

        if env_value.nil? || env_value.empty?
          raise ADK::Auth::EnvironmentVariableNotFoundError, env_name
        end

        env_value
      end
    end
  end
end 