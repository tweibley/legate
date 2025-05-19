# File: lib/adk/auth/exchanged_credential.rb
# frozen_string_literal: true

require 'time'

module ADK
  module Auth
    # Represents credentials that have been exchanged for tokens.
    # Stores tokens obtained from authentication providers, along with
    # metadata such as expiration times and refresh tokens.
    class ExchangedCredential
      # @return [Symbol] The type of authentication
      attr_reader :auth_type

      # @return [String] The access token
      attr_reader :access_token

      # @return [String, nil] The refresh token, if available
      attr_reader :refresh_token

      # @return [String, nil] The token type (e.g., "Bearer")
      attr_reader :token_type

      # @return [Time, nil] The expiration time
      attr_reader :expires_at

      # @return [String, nil] ID token for OIDC
      attr_reader :id_token
      
      # @return [String, nil] The provider ID for this credential
      attr_accessor :provider_id

      # @return [Hash] Additional attributes specific to the auth type
      attr_reader :attributes

      # Initialize a new ExchangedCredential
      # @param auth_type [Symbol] The type of authentication
      # @param access_token [String] The access token
      # @param refresh_token [String, nil] The refresh token
      # @param token_type [String, nil] The token type
      # @param expires_in [Integer, nil] Seconds until the token expires
      # @param id_token [String, nil] ID token for OIDC
      # @param provider_id [String, nil] The provider ID for this credential
      # @param attributes [Hash] Additional attributes
      def initialize(auth_type:, access_token:, refresh_token: nil, token_type: 'Bearer',
                    expires_in: nil, id_token: nil, provider_id: nil, **attributes)
        @auth_type = auth_type.to_sym
        @access_token = access_token
        @refresh_token = refresh_token
        @token_type = token_type || 'Bearer'
        @id_token = id_token
        @provider_id = provider_id
        @attributes = attributes || {}
        
        # Calculate expiration time if expires_in is provided
        @expires_at = if expires_in && expires_in.to_i > 0
                        Time.now + expires_in.to_i
                      elsif attributes[:expires_at]
                        Time.parse(attributes[:expires_at].to_s)
                      else
                        nil
                      end
      end

      # Check if the token is expired
      # @param buffer_seconds [Integer] Buffer time in seconds to consider token as expired
      # @return [Boolean] True if the token is expired, false otherwise
      def expired?(buffer_seconds = 30)
        return false unless @expires_at
        @expires_at - buffer_seconds <= Time.now
      end

      # Check if the credential can be refreshed
      # @return [Boolean] True if a refresh token is available
      def refreshable?
        !@refresh_token.nil? && !@refresh_token.empty?
      end

      # Convert to a hash for serialization
      # @return [Hash] A hash representation of the credential
      def to_h
        {
          auth_type: @auth_type,
          access_token: @access_token,
          refresh_token: @refresh_token,
          token_type: @token_type,
          expires_at: @expires_at&.iso8601,
          id_token: @id_token,
          provider_id: @provider_id
        }.merge(@attributes).compact
      end

      # Create an ExchangedCredential from a hash
      # @param hash [Hash] A hash representation of the credential
      # @return [ADK::Auth::ExchangedCredential] A new ExchangedCredential
      def self.from_h(hash)
        attrs = hash.dup
        auth_type = attrs.delete(:auth_type) || attrs.delete('auth_type')
        access_token = attrs.delete(:access_token) || attrs.delete('access_token')
        refresh_token = attrs.delete(:refresh_token) || attrs.delete('refresh_token')
        token_type = attrs.delete(:token_type) || attrs.delete('token_type')
        expires_at = attrs.delete(:expires_at) || attrs.delete('expires_at')
        id_token = attrs.delete(:id_token) || attrs.delete('id_token')
        provider_id = attrs.delete(:provider_id) || attrs.delete('provider_id')
        
        # Convert string keys to symbols
        attributes = {}
        attrs.each do |key, value|
          attributes[key.to_sym] = value
        end
        
        # Set expires_at as an attribute so it gets passed to the initializer
        attributes[:expires_at] = expires_at if expires_at
        
        new(
          auth_type: auth_type,
          access_token: access_token,
          refresh_token: refresh_token,
          token_type: token_type,
          id_token: id_token,
          provider_id: provider_id,
          **attributes
        )
      end

      # Get an attribute value
      # @param name [Symbol, String] The attribute name
      # @return [Object, nil] The attribute value, or nil if not present
      def [](name)
        case name.to_sym
        when :access_token
          @access_token
        when :refresh_token
          @refresh_token
        when :token_type
          @token_type
        when :expires_at
          @expires_at
        when :id_token
          @id_token
        when :auth_type
          @auth_type
        when :provider_id
          @provider_id
        else
          @attributes[name.to_sym]
        end
      end
      
      # Return a new ExchangedCredential with updated values
      # @param attrs [Hash] The attributes to update
      # @return [ADK::Auth::ExchangedCredential] A new ExchangedCredential with updated values
      def with(attrs)
        self.class.new(
          auth_type: attrs[:auth_type] || @auth_type,
          access_token: attrs[:access_token] || @access_token,
          refresh_token: attrs[:refresh_token] || @refresh_token,
          token_type: attrs[:token_type] || @token_type,
          id_token: attrs[:id_token] || @id_token,
          provider_id: attrs[:provider_id] || @provider_id,
          **@attributes.merge(attrs.reject { |k, _| 
            [:auth_type, :access_token, :refresh_token, :token_type, :id_token, :provider_id].include?(k) 
          })
        )
      end
    end
  end
end 