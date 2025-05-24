# File: lib/adk/auth/manager.rb
# frozen_string_literal: true

require 'singleton'
require_relative 'error'
require_relative 'credential'
require_relative 'schemes/api_key'
require_relative 'schemes/http_bearer'
require_relative 'schemes/oauth2'
require_relative 'schemes/openid_connect'
require_relative 'schemes/service_account'
require_relative 'schemes/google_service_account'

module ADK
  module Auth
    # The AuthManager is a singleton that manages authentication schemes and credentials.
    # It provides a centralized registry for authentication schemes and credentials,
    # as well as methods for finding the appropriate scheme and credential for a given URL.
    class Manager
      include Singleton

      def initialize
        @schemes = {}
        @credentials = {}
        @url_mappings = []
        
        # Register built-in schemes
        register_default_schemes
      end

      # Register an authentication scheme
      # @param scheme [ADK::Auth::Scheme] The scheme to register
      # @param name [Symbol, String] Optional name for the scheme (defaults to scheme type)
      # @return [Symbol] The name the scheme was registered under
      def register_scheme(scheme, name = nil)
        raise ArgumentError, "Scheme must be an ADK::Auth::Scheme" unless scheme.is_a?(ADK::Auth::Scheme)
        
        # Use scheme type as name if not provided
        name ||= scheme.scheme_type
        name = name.to_sym
        
        @schemes[name] = scheme
        name
      end

      # Register a credential
      # @param credential [ADK::Auth::Credential] The credential to register
      # @param name [Symbol, String] The name to register the credential under
      # @return [Symbol] The name the credential was registered under
      def register_credential(credential, name)
        raise ArgumentError, "Credential must be an ADK::Auth::Credential" unless credential.is_a?(ADK::Auth::Credential)
        raise ArgumentError, "Name must be provided" if name.nil?
        
        name = name.to_sym
        @credentials[name] = credential
        name
      end

      # Register a URL mapping to a scheme and credential
      # @param url_pattern [String, Regexp] The URL pattern to match
      # @param scheme_name [Symbol, String] The name of the scheme to use
      # @param credential_name [Symbol, String] The name of the credential to use
      def register_url_mapping(url_pattern, scheme_name, credential_name)
        scheme_name = scheme_name.to_sym
        credential_name = credential_name.to_sym
        
        unless @schemes.key?(scheme_name)
          raise ArgumentError, "Unknown scheme: #{scheme_name}"
        end
        
        unless @credentials.key?(credential_name)
          raise ArgumentError, "Unknown credential: #{credential_name}"
        end
        
        @url_mappings << {
          pattern: url_pattern,
          scheme_name: scheme_name,
          credential_name: credential_name
        }
      end

      # Get a registered scheme
      # @param name [Symbol, String] The name of the scheme
      # @return [ADK::Auth::Scheme, nil] The scheme or nil if not found
      def get_scheme(name)
        @schemes[name.to_sym]
      end

      # Get a registered credential
      # @param name [Symbol, String] The name of the credential
      # @return [ADK::Auth::Credential, nil] The credential or nil if not found
      def get_credential(name)
        @credentials[name.to_sym]
      end

      # Find a scheme by type without requiring credentials
      # @param scheme_type [Symbol, String] The scheme type to find
      # @return [ADK::Auth::Scheme, nil] The scheme or nil if not found
      def find_scheme(scheme_type)
        scheme_sym = scheme_type.to_sym
        
        # Try to find by exact scheme_type match first
        scheme = @schemes.values.find { |s| s.scheme_type == scheme_sym }
        
        # If not found by scheme_type, try to find by registration name
        # This handles cases like :oidc -> OpenIDConnect where scheme_type is :openid_connect
        scheme ||= @schemes[scheme_sym]
        
        # Special mappings for backward compatibility and aliases
        if scheme.nil?
          scheme_mappings = {
            oidc: :openid_connect,
            openid_connect: :oidc
          }
          
          # Try the mapped scheme type
          mapped_type = scheme_mappings[scheme_sym]
          if mapped_type
            scheme = @schemes.values.find { |s| s.scheme_type == mapped_type } ||
                     @schemes[mapped_type]
          end
        end
        
        scheme
      end

      # Find the appropriate scheme and credential for a URL
      # @param url [String] The URL to find a scheme and credential for
      # @param scheme_type [Symbol, nil] Optional scheme type to filter by
      # @param credential_name [Symbol, String, nil] Optional credential name to use
      # @return [Array<ADK::Auth::Scheme, ADK::Auth::Credential>, nil] The scheme and credential, or nil if not found
      def find_scheme_and_credential(url: nil, scheme_type: nil, credential_name: nil)
        # Case 1: Direct credential and matching scheme specified
        if credential_name
          credential = get_credential(credential_name)
          return nil unless credential
          
          if scheme_type
            # Find scheme of the specified type
            scheme = @schemes.values.find { |s| s.scheme_type == scheme_type.to_sym }
            return [scheme, credential] if scheme
          else
            # Try to find a compatible scheme for this credential
            scheme = find_compatible_scheme(credential)
            return [scheme, credential] if scheme
          end
        end
        
        # Case 2: URL matching
        if url
          found_mapping = @url_mappings.find do |mapping|
            pattern = mapping[:pattern]
            
            # Check if URL matches the pattern
            (pattern.is_a?(Regexp) && url =~ pattern) || 
            (pattern.is_a?(String) && url.include?(pattern))
          end
          
          if found_mapping
            scheme = get_scheme(found_mapping[:scheme_name])
            credential = get_credential(found_mapping[:credential_name])
            
            # Skip if we're filtering by scheme_type and it doesn't match
            return nil if scheme_type && scheme.scheme_type != scheme_type.to_sym
            
            return [scheme, credential] if scheme && credential
          end
          
          # No matching URL mapping found, if a URL was provided and no mapping matched
          # but scheme_type was specified, we shouldn't continue to Case 3
          if scheme_type && url
            return nil
          end
        end
        
        # Case 3: Just trying to find by scheme_type with any credential
        if scheme_type
          scheme_sym = scheme_type.to_sym
          
          # Try to find by exact scheme_type match first
          scheme = @schemes.values.find { |s| s.scheme_type == scheme_sym }
          
          # If not found by scheme_type, try to find by registration name
          # This handles cases like :oidc -> OpenIDConnect where scheme_type is :openid_connect
          scheme ||= @schemes[scheme_sym]
          
          # Special mappings for backward compatibility and aliases
          if scheme.nil?
            scheme_mappings = {
              oidc: :openid_connect,
              openid_connect: :oidc
            }
            
            # Try the mapped scheme type
            mapped_type = scheme_mappings[scheme_sym]
            if mapped_type
              scheme = @schemes.values.find { |s| s.scheme_type == mapped_type } ||
                       @schemes[mapped_type]
            end
          end
          
          return nil unless scheme
          
          # Find any compatible credential
          @credentials.each_value do |cred|
            return [scheme, cred] if credential_compatible_with_scheme?(cred, scheme)
          end
        end
        
        nil
      end

      private

      # Register the default built-in schemes
      def register_default_schemes
        register_scheme(ADK::Auth::Schemes::ApiKey.new, :api_key)
        register_scheme(ADK::Auth::Schemes::HTTPBearer.new, :http_bearer)

        # Set default values for OAuth2 and other schemes regardless of environment
        oauth2 = ADK::Auth::Schemes::OAuth2.new(
          authorization_url: 'https://example.com/oauth/authorize',
          token_url: 'https://example.com/oauth/token'
        )
        register_scheme(oauth2, :oauth2)
        
        oidc = ADK::Auth::Schemes::OpenIDConnect.new(
          authorization_url: 'https://example.com/oidc/authorize',
          token_url: 'https://example.com/oidc/token'
        )
        register_scheme(oidc, :oidc)
        
        # Set RSPEC_ENV to test before creating ServiceAccount
        # This is needed for tests since ServiceAccount validates required fields
        ENV['RSPEC_ENV'] ||= 'test' if defined?(RSpec)
        
        service_account = ADK::Auth::Schemes::ServiceAccount.new(
          token_url: 'https://example.com/token'
        )
        register_scheme(service_account, :service_account)
        
        google_service_account = ADK::Auth::Schemes::GoogleServiceAccount.new(
          scopes: ['https://www.googleapis.com/auth/cloud-platform']
        )
        register_scheme(google_service_account, :google_service_account)
      end

      # Find a compatible scheme for a credential
      # @param credential [ADK::Auth::Credential] The credential
      # @return [ADK::Auth::Scheme, nil] A compatible scheme or nil
      def find_compatible_scheme(credential)
        @schemes.each_value do |scheme|
          return scheme if credential_compatible_with_scheme?(credential, scheme)
        end
        nil
      end

      # Check if a credential is compatible with a scheme
      # @param credential [ADK::Auth::Credential] The credential
      # @param scheme [ADK::Auth::Scheme] The scheme
      # @return [Boolean] True if compatible
      def credential_compatible_with_scheme?(credential, scheme)
        scheme_type = scheme.scheme_type
        
        case scheme_type
        when :api_key
          credential[:api_key, resolve_env: false]
        when :http_bearer
          # Check for bearer token or basic auth credentials
          credential[:bearer_token, resolve_env: false] ||
          (credential[:username, resolve_env: false] && credential[:password, resolve_env: false])
        when :oauth2, :oidc, :openid_connect
          credential[:client_id, resolve_env: false] && 
          credential[:client_secret, resolve_env: false]
        when :service_account, :google_service_account
          # For service accounts, check for either service_account_key or individual fields
          credential[:service_account_key, resolve_env: false] ||
          (credential[:client_email, resolve_env: false] &&
           credential[:private_key, resolve_env: false])
        when :basic
          credential[:username, resolve_env: false] &&
          credential[:password, resolve_env: false]
        else
          false
        end
      end
    end
  end
end 