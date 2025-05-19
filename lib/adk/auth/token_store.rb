# File: lib/adk/auth/token_store.rb
# frozen_string_literal: true

module ADK
  module Auth
    # Provides secure storage and retrieval of authentication tokens.
    # Manages token encryption, caching, and lookup by cache key.
    module TokenStore
      # Default namespace for auth token cache in session state
      DEFAULT_NAMESPACE = :auth_token_cache

      class << self
        # Store a token in the session state
        # @param session [ADK::Session] The session to store the token in
        # @param cache_key [String, Symbol] A unique key for the token
        # @param token [ADK::Auth::ExchangedCredential] The token to store
        # @param namespace [Symbol] The namespace in the session state
        # @return [Boolean] True if the token was stored successfully
        def store(session, cache_key, token, namespace: DEFAULT_NAMESPACE)
          raise ArgumentError, 'Session cannot be nil' unless session
          raise ArgumentError, 'Cache key cannot be nil' unless cache_key
          raise ArgumentError, 'Token cannot be nil' unless token

          # Ensure the namespace exists in the session state
          session.state[namespace] ||= {}
          
          # Serialize and encrypt the token
          serialized = serialize_token(token)
          encrypted = encrypt_token(serialized)
          
          # Store in session state
          session.state[namespace][cache_key.to_sym] = encrypted
          true
        end
        
        # Retrieve a token from the session state
        # @param session [ADK::Session] The session to retrieve the token from
        # @param cache_key [String, Symbol] The unique key for the token
        # @param namespace [Symbol] The namespace in the session state
        # @return [ADK::Auth::ExchangedCredential, nil] The token if found and valid, nil otherwise
        def retrieve(session, cache_key, namespace: DEFAULT_NAMESPACE)
          raise ArgumentError, 'Session cannot be nil' unless session
          raise ArgumentError, 'Cache key cannot be nil' unless cache_key
          
          # Check if the namespace and key exist
          return nil unless session.state[namespace]
          encrypted = session.state[namespace][cache_key.to_sym]
          return nil unless encrypted
          
          # Decrypt and deserialize the token
          begin
            serialized = decrypt_token(encrypted)
            deserialize_token(serialized)
          rescue => e
            ADK.logger.error("Failed to retrieve token: #{e.message}")
            nil
          end
        end
        
        # Delete a token from the session state
        # @param session [ADK::Session] The session to delete the token from
        # @param cache_key [String, Symbol] The unique key for the token
        # @param namespace [Symbol] The namespace in the session state
        # @return [Boolean] True if the token was deleted, false if it wasn't found
        def delete(session, cache_key, namespace: DEFAULT_NAMESPACE)
          raise ArgumentError, 'Session cannot be nil' unless session
          raise ArgumentError, 'Cache key cannot be nil' unless cache_key
          
          # Check if the namespace and key exist
          return false unless session.state[namespace]
          return false unless session.state[namespace].key?(cache_key.to_sym)
          
          # Delete the token
          session.state[namespace].delete(cache_key.to_sym)
          true
        end
        
        # Generate a cache key for a credential and scheme
        # @param credential [ADK::Auth::Credential] The credential
        # @param scheme [ADK::Auth::Scheme] The authentication scheme
        # @return [Symbol] A unique cache key
        def generate_key(credential, scheme)
          # Create a unique key based on the credential type and relevant attributes
          key_parts = [credential.auth_type, scheme.scheme_type]
          
          case credential.auth_type
          when :oauth2, :oidc
            key_parts << credential[:client_id]
          when :service_account
            key_parts << credential[:project_id] if credential[:project_id]
          when :api_key
            # Use a hash of the API key to avoid storing it directly in the key
            require 'digest'
            key_parts << Digest::SHA256.hexdigest(credential[:api_key])[0..8]
          end
          
          # Join parts and convert to symbol
          key_parts.compact.join('_').to_sym
        end
        
        private
        
        # Serialize a token for storage
        # @param token [ADK::Auth::ExchangedCredential] The token to serialize
        # @return [String] The serialized token
        def serialize_token(token)
          require 'json'
          JSON.generate(token.to_h)
        end
        
        # Deserialize a token from storage
        # @param serialized [String] The serialized token
        # @return [ADK::Auth::ExchangedCredential] The deserialized token
        def deserialize_token(serialized)
          require 'json'
          ExchangedCredential.from_h(JSON.parse(serialized, symbolize_names: true))
        end
        
        # Encrypt a token for secure storage
        # @param serialized [String] The serialized token
        # @return [String] The encrypted token
        def encrypt_token(serialized)
          ADK::Auth::Encryption.encrypt(serialized)
        end
        
        # Decrypt a token from secure storage
        # @param encrypted [String] The encrypted token
        # @return [String] The decrypted serialized token
        def decrypt_token(encrypted)
          ADK::Auth::Encryption.decrypt(encrypted)
        end
      end
    end
  end
end 