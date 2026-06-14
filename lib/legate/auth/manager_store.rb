# File: lib/legate/auth/manager_store.rb
# frozen_string_literal: true

require 'json'

module Legate
  module Auth
    # Module for persisting authentication configuration (schemes, credentials, URL mappings)
    module ManagerStore
      # Redis-backed implementation for storing authentication configuration
      class RedisStore
        # Redis key prefixes
        SCHEMES_HASH_KEY = 'legate:auth:schemes'
        CREDENTIALS_HASH_KEY = 'legate:auth:credentials'
        URL_MAPPINGS_KEY = 'legate:auth:url_mappings'

        # @param redis_client [Redis] An instance of the Redis client
        def initialize(redis_client:)
          @redis = redis_client
          @logger = Legate.logger
          @logger&.info('Legate::Auth::ManagerStore::RedisStore initialized.')
        rescue StandardError => e
          Legate.logger&.error("Failed to initialize Auth ManagerStore: #{e.message}")
          @redis = nil
        end

        # Check if Redis is available
        # @return [Boolean]
        def available?
          !@redis.nil?
        end

        # ========== Scheme Operations ==========

        # Save a scheme configuration
        # @param name [String, Symbol] The scheme name
        # @param scheme [Legate::Auth::Scheme] The scheme to save
        # @return [Boolean] true if successful
        def save_scheme(name, scheme)
          return false unless available?

          name = name.to_s

          scheme_data = serialize_scheme(scheme)
          @redis.hset(SCHEMES_HASH_KEY, name, scheme_data.to_json)
          @logger&.debug("Saved auth scheme '#{name}' to Redis")
          true
        rescue StandardError => e
          @logger&.error("Failed to save scheme '#{name}': #{e.message}")
          false
        end

        # Load a single scheme
        # @param name [String, Symbol] The scheme name
        # @return [Hash, nil] The scheme data or nil if not found
        def load_scheme(name)
          return nil unless available?

          name = name.to_s
          data = @redis.hget(SCHEMES_HASH_KEY, name)
          return nil unless data

          JSON.parse(data, symbolize_names: true)
        rescue StandardError => e
          @logger&.error("Failed to load scheme '#{name}': #{e.message}")
          nil
        end

        # Load all schemes
        # @return [Hash] Hash of scheme_name => scheme_data
        def load_all_schemes
          return {} unless available?

          result = {}
          @redis.hgetall(SCHEMES_HASH_KEY).each do |name, data|
            result[name.to_sym] = JSON.parse(data, symbolize_names: true)
          rescue JSON::ParserError => e
            @logger&.warn("Failed to parse scheme '#{name}': #{e.message}")
          end
          result
        rescue StandardError => e
          @logger&.error("Failed to load schemes: #{e.message}")
          {}
        end

        # Delete a scheme
        # @param name [String, Symbol] The scheme name
        # @return [Boolean] true if successful
        def delete_scheme(name)
          return false unless available?

          @redis.hdel(SCHEMES_HASH_KEY, name.to_s)
          @logger&.debug("Deleted auth scheme '#{name}' from Redis")
          true
        rescue StandardError => e
          @logger&.error("Failed to delete scheme '#{name}': #{e.message}")
          false
        end

        # ========== Credential Operations ==========

        # Save a credential
        # @param name [String, Symbol] The credential name
        # @param credential [Legate::Auth::Credential] The credential to save
        # @return [Boolean] true if successful
        def save_credential(name, credential)
          return false unless available?

          name = name.to_s

          credential_data = serialize_credential(credential)
          @redis.hset(CREDENTIALS_HASH_KEY, name, credential_data.to_json)
          @logger&.debug("Saved auth credential '#{name}' to Redis")
          true
        rescue StandardError => e
          @logger&.error("Failed to save credential '#{name}': #{e.message}")
          false
        end

        # Load a single credential
        # @param name [String, Symbol] The credential name
        # @return [Hash, nil] The credential data or nil if not found
        def load_credential(name)
          return nil unless available?

          name = name.to_s
          data = @redis.hget(CREDENTIALS_HASH_KEY, name)
          return nil unless data

          JSON.parse(data, symbolize_names: true)
        rescue StandardError => e
          @logger&.error("Failed to load credential '#{name}': #{e.message}")
          nil
        end

        # Load all credentials
        # @return [Hash] Hash of credential_name => credential_data
        def load_all_credentials
          return {} unless available?

          result = {}
          @redis.hgetall(CREDENTIALS_HASH_KEY).each do |name, data|
            result[name.to_sym] = JSON.parse(data, symbolize_names: true)
          rescue JSON::ParserError => e
            @logger&.warn("Failed to parse credential '#{name}': #{e.message}")
          end
          result
        rescue StandardError => e
          @logger&.error("Failed to load credentials: #{e.message}")
          {}
        end

        # Delete a credential
        # @param name [String, Symbol] The credential name
        # @return [Boolean] true if successful
        def delete_credential(name)
          return false unless available?

          @redis.hdel(CREDENTIALS_HASH_KEY, name.to_s)
          @logger&.debug("Deleted auth credential '#{name}' from Redis")
          true
        rescue StandardError => e
          @logger&.error("Failed to delete credential '#{name}': #{e.message}")
          false
        end

        # ========== URL Mapping Operations ==========

        # Save URL mappings (replaces all)
        # @param mappings [Array<Hash>] Array of URL mapping hashes
        # @return [Boolean] true if successful
        def save_url_mappings(mappings)
          return false unless available?

          serialized = mappings.map do |mapping|
            {
              pattern: mapping[:pattern].is_a?(Regexp) ? { regexp: mapping[:pattern].source } : mapping[:pattern],
              scheme_name: mapping[:scheme_name].to_s,
              credential_name: mapping[:credential_name].to_s
            }
          end

          @redis.set(URL_MAPPINGS_KEY, serialized.to_json)
          @logger&.debug("Saved #{mappings.size} URL mappings to Redis")
          true
        rescue StandardError => e
          @logger&.error("Failed to save URL mappings: #{e.message}")
          false
        end

        # Load URL mappings
        # @return [Array<Hash>] Array of URL mapping hashes
        def load_url_mappings
          return [] unless available?

          data = @redis.get(URL_MAPPINGS_KEY)
          return [] unless data

          mappings = JSON.parse(data, symbolize_names: true)

          # Reconstruct Regexp patterns
          mappings.map do |mapping|
            pattern = mapping[:pattern]
            pattern = Regexp.new(pattern[:regexp]) if pattern.is_a?(Hash) && pattern[:regexp]

            {
              pattern: pattern,
              scheme_name: mapping[:scheme_name].to_sym,
              credential_name: mapping[:credential_name].to_sym
            }
          end
        rescue StandardError => e
          @logger&.error("Failed to load URL mappings: #{e.message}")
          []
        end

        # Add a single URL mapping
        # @param mapping [Hash] The URL mapping to add
        # @return [Boolean] true if successful
        def add_url_mapping(mapping)
          return false unless available?

          current = load_url_mappings
          current << mapping
          save_url_mappings(current)
        end

        # Remove a URL mapping
        # @param index [Integer] The index of the mapping to remove
        # @return [Boolean] true if successful
        def remove_url_mapping(index)
          return false unless available?

          current = load_url_mappings
          return false if index < 0 || index >= current.size

          current.delete_at(index)
          save_url_mappings(current)
        end

        # Clear all URL mappings
        # @return [Boolean] true if successful
        def clear_url_mappings
          return false unless available?

          @redis.del(URL_MAPPINGS_KEY)
          true
        rescue StandardError => e
          @logger&.error("Failed to clear URL mappings: #{e.message}")
          false
        end

        private

        # Serialize a scheme to a storable hash
        # @param scheme [Legate::Auth::Scheme] The scheme
        # @return [Hash] Serialized scheme data
        def serialize_scheme(scheme)
          data = {
            scheme_type: scheme.scheme_type.to_s,
            class_name: scheme.class.name
          }

          # Add scheme-specific configuration
          case scheme
          when Legate::Auth::Schemes::OAuth2, Legate::Auth::Schemes::OpenIDConnect
            data[:authorization_url] = scheme.authorization_url if scheme.respond_to?(:authorization_url)
            data[:token_url] = scheme.token_url if scheme.respond_to?(:token_url)
            data[:scopes] = scheme.scopes if scheme.respond_to?(:scopes)
            data[:use_pkce] = scheme.use_pkce if scheme.respond_to?(:use_pkce)
            data[:revocation_url] = scheme.revocation_url if scheme.respond_to?(:revocation_url)
          when Legate::Auth::Schemes::ApiKey
            data[:header_name] = scheme.header_name if scheme.respond_to?(:header_name)
            data[:query_param_name] = scheme.query_param_name if scheme.respond_to?(:query_param_name)
            data[:location] = scheme.location if scheme.respond_to?(:location)
          when Legate::Auth::Schemes::ServiceAccount
            data[:token_url] = scheme.token_url if scheme.respond_to?(:token_url)
          when Legate::Auth::Schemes::GoogleServiceAccount
            data[:scopes] = scheme.scopes if scheme.respond_to?(:scopes)
          end

          data
        end

        # Serialize a credential to a storable hash
        # @param credential [Legate::Auth::Credential] The credential
        # @return [Hash] Serialized credential data
        def serialize_credential(credential)
          data = {
            auth_type: credential.auth_type.to_s
          }

          # Copy all attributes (they may contain ENV: references which should be preserved as-is)
          attributes = credential.instance_variable_get(:@attributes) || {}
          attributes.each do |key, value|
            data[key] = value
          end

          data
        end
      end

      # In-memory fallback store (for when Redis is unavailable)
      class InMemoryStore
        def initialize
          @schemes = {}
          @credentials = {}
          @url_mappings = []
          @logger = Legate.logger
          @logger&.info('Legate::Auth::ManagerStore::InMemoryStore initialized (no persistence).')
        end

        def available?
          true
        end

        def save_scheme(name, scheme)
          @schemes[name.to_sym] = serialize_scheme(scheme)
          true
        end

        def load_scheme(name)
          @schemes[name.to_sym]
        end

        def load_all_schemes
          @schemes.dup
        end

        def delete_scheme(name)
          @schemes.delete(name.to_sym)
          true
        end

        def save_credential(name, credential)
          @credentials[name.to_sym] = serialize_credential(credential)
          true
        end

        def load_credential(name)
          @credentials[name.to_sym]
        end

        def load_all_credentials
          @credentials.dup
        end

        def delete_credential(name)
          @credentials.delete(name.to_sym)
          true
        end

        def save_url_mappings(mappings)
          @url_mappings = mappings.dup
          true
        end

        def load_url_mappings
          @url_mappings.dup
        end

        def add_url_mapping(mapping)
          @url_mappings << mapping
          true
        end

        def remove_url_mapping(index)
          return false if index < 0 || index >= @url_mappings.size

          @url_mappings.delete_at(index)
          true
        end

        def clear_url_mappings
          @url_mappings = []
          true
        end

        private

        def serialize_scheme(scheme)
          { scheme_type: scheme.scheme_type.to_s, class_name: scheme.class.name }
        end

        def serialize_credential(credential)
          data = { auth_type: credential.auth_type.to_s }
          attributes = credential.instance_variable_get(:@attributes) || {}
          attributes.each { |k, v| data[k] = v }
          data
        end
      end
    end
  end
end
