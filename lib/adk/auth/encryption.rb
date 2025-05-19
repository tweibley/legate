# File: lib/adk/auth/encryption.rb
# frozen_string_literal: true

module ADK
  module Auth
    # Provides encryption and decryption utilities for sensitive authentication data.
    # Uses the rbnacl gem for authenticated encryption.
    module Encryption
      # Environment variable name for the encryption key
      ENV_KEY_NAME = 'ADK_AUTH_ENCRYPTION_KEY'
      
      # Header added to encrypted data for identification
      ENCRYPTION_HEADER = 'ADKAUTH'
      
      class << self
        # Encrypts sensitive data
        # @param data [String] The data to encrypt
        # @param key [String, nil] The encryption key (defaults to the key from environment)
        # @return [String] The encrypted data in Base64 format with header
        # @raise [LoadError] If the rbnacl gem is not available
        # @raise [ArgumentError] If the encryption key is not available
        def encrypt(data, key = nil)
          require_rbnacl
          encryption_key = key || get_encryption_key
          
          require 'base64'
          box = create_box(encryption_key)
          encrypted = box.encrypt(data.to_s)
          "#{ENCRYPTION_HEADER}#{Base64.strict_encode64(encrypted)}"
        end
        
        # Decrypts sensitive data
        # @param encrypted_data [String] The encrypted data to decrypt
        # @param key [String, nil] The encryption key (defaults to the key from environment)
        # @return [String] The decrypted data
        # @raise [LoadError] If the rbnacl gem is not available
        # @raise [ArgumentError] If the data is not in the expected format or the key is invalid
        def decrypt(encrypted_data, key = nil)
          require_rbnacl
          encryption_key = key || get_encryption_key
          
          # Check format and remove header
          unless encrypted_data.to_s.start_with?(ENCRYPTION_HEADER)
            raise ArgumentError, 'Invalid encrypted data format'
          end
          
          encoded = encrypted_data.to_s[ENCRYPTION_HEADER.length..-1]
          require 'base64'
          encrypted = Base64.strict_decode64(encoded)
          
          box = create_box(encryption_key)
          box.decrypt(encrypted)
        rescue RbNaCl::CryptoError => e
          raise ArgumentError, "Decryption failed: #{e.message}"
        rescue ArgumentError => e
          raise ArgumentError, "Invalid Base64 encoding: #{e.message}"
        end
        
        # Generates a new random encryption key
        # @return [String] A new encryption key in Base64 format
        # @raise [LoadError] If the rbnacl gem is not available
        def generate_key
          require_rbnacl
          require 'base64'
          raw_key = RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes)
          Base64.strict_encode64(raw_key)
        end
        
        # Checks if the encrypted data is in the expected format
        # @param data [String] The data to check
        # @return [Boolean] True if the data appears to be encrypted
        def encrypted?(data)
          data.to_s.start_with?(ENCRYPTION_HEADER)
        end
        
        private
        
        # Gets the encryption key from the environment or configuration
        # @return [String] The encryption key in raw binary format
        # @raise [ArgumentError] If the encryption key is not available
        def get_encryption_key
          env_key = ENV[ENV_KEY_NAME]
          raise ArgumentError, "Encryption key not found. Set #{ENV_KEY_NAME} environment variable." unless env_key
          
          require 'base64'
          begin
            Base64.strict_decode64(env_key)
          rescue ArgumentError
            raise ArgumentError, "Invalid encryption key format. Must be Base64-encoded."
          end
        end
        
        # Creates a SimpleBox from the encryption key
        # @param key [String] The encryption key in raw binary format
        # @return [RbNaCl::SimpleBox] A box for encryption/decryption
        def create_box(key)
          RbNaCl::SimpleBox.from_secret_key(key)
        end
        
        # Ensures that the rbnacl gem is available
        # @raise [LoadError] If the rbnacl gem is not available
        def require_rbnacl
          begin
            require 'rbnacl'
          rescue LoadError
            raise LoadError, "rbnacl gem is required for encryption. Add it to your Gemfile: gem 'rbnacl'"
          end
        end
      end
    end
  end
end 