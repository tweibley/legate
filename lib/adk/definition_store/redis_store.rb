# File: lib/adk/definition_store/redis_store.rb
# frozen_string_literal: true

require 'redis'
require 'json'
require 'adk/version' # Access ADK logger

module ADK
  module DefinitionStore
    # Redis-backed implementation for storing and retrieving agent definitions.
    class RedisStore
      # Define Redis keys
      AGENT_HASH_PREFIX = "adk:agent:"
      AGENTS_SET_KEY = "adk:agents:all_names"

      # Expected field names in the Redis hash
      AGENT_DEFINITION_FIELDS = %w[name description tools model fallback_mode mcp_servers_json].freeze

      def initialize(redis_client)
        @redis = redis_client
        @logger = ADK.logger
        @logger.info("ADK::DefinitionStore::RedisStore initialized.")
      rescue => e
        # Log initialization error but allow potential recovery if client is provided later or fixed
        ADK.logger&.error("Failed to initialize RedisStore: #{e.message}")
        @redis = nil # Ensure redis is nil if connection failed
      end

      # --- Implementation Methods (To be filled in) ---

      # Saves a new agent definition to Redis.
      # @param name [String] The unique name for the agent.
      # @param description [String] A description of the agent.
      # @param tools [Array<String>] An array of tool names (strings).
      # @param model [String] The language model name.
      # @param fallback_mode [Symbol] The fallback behavior (:error or :echo).
      # @param mcp_servers_json [String] A JSON string representing the MCP server configurations array.
      # @return [Boolean] true if successful, false otherwise.
      # @raise [ArgumentError] if required fields (name) are missing or invalid.
      # @raise [ConfigurationError] if Redis client is not available.
      # @raise [StoreError] for Redis errors during save.
      def save_definition(name:, description:, tools:, model:, fallback_mode:, mcp_servers_json:)
        raise ConfigurationError, "Redis client not available." unless @redis
        raise ArgumentError, "Agent name cannot be empty." if name.nil? || name.strip.empty?

        # Optional: Add more validation for other fields if needed

        agent_key = agent_redis_key(name)
        fallback_str = fallback_mode.to_s # Store as string
        mcp_json_to_save = (mcp_servers_json.nil? || mcp_servers_json.strip.empty?) ? '[]' : mcp_servers_json.strip

        begin
          # Validate MCP JSON before saving
          unless mcp_json_to_save == '[]'
            parsed_mcp = JSON.parse(mcp_json_to_save)
            raise ArgumentError, "MCP configuration must be a JSON array." unless parsed_mcp.is_a?(Array)
          end

          tools_json = tools.is_a?(Array) ? tools.to_json : '[]'

          # Use MULTI/EXEC to ensure atomicity
          result = @redis.multi do |multi|
            multi.hset(agent_key, 'name', name) # Store name in hash too for easier retrieval
            multi.hset(agent_key, 'description', description || "")
            multi.hset(agent_key, 'tools', tools_json)
            multi.hset(agent_key, 'model', model || ADK::Agent::DEFAULT_MODEL) # Use default if nil
            multi.hset(agent_key, 'fallback_mode', fallback_str)
            multi.hset(agent_key, 'mcp_servers_json', mcp_json_to_save)
            multi.sadd(AGENTS_SET_KEY, name)
          end

          # Check results - Redis MULTI returns an array of results for each command
          # For HSET, it returns integer (1 if new field, 0 if updated). For SADD, integer (1 if added, 0 if exists).
          # We mainly care if the transaction succeeded without error. Redis errors within MULTI abort it.
          if result.nil?
            # This happens if the transaction was aborted (e.g., due to WATCH)
            @logger.error("Redis transaction for saving agent '#{name}' failed (aborted).")
            raise StoreError, "Redis transaction aborted while saving agent '#{name}'."
          elsif result.any? { |r| r.is_a?(Redis::CommandError) }
            # Check if any individual command resulted in an error object (shouldn't typically happen with these commands unless connection issue)
            @logger.error("Redis command error during multi for saving agent '#{name}': #{result.inspect}")
            raise StoreError, "Redis command error while saving agent '#{name}'."
          else
            @logger.info("Agent definition '#{name}' saved successfully.")
            true
          end
        rescue JSON::ParserError => e
          @logger.error("Invalid MCP JSON provided for agent '#{name}': #{e.message}")
          raise ArgumentError, "Invalid format for MCP Server Configurations: #{e.message}"
        rescue JSON::GeneratorError => e
          @logger.error("Failed to serialize tools array to JSON for agent '#{name}': #{e.message}")
          raise StoreError, "Internal error serializing tool data for agent '#{name}'."
        rescue Redis::BaseError => e
          @logger.error("Redis error saving agent '#{name}': #{e.class} - #{e.message}")
          raise StoreError, "Redis error saving agent definition: #{e.message}"
        rescue ArgumentError => e # Re-raise specific argument errors
          raise e
        rescue => e # Catch other unexpected errors
          @logger.error("Unexpected error saving agent '#{name}': #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
          raise StoreError, "Unexpected error saving agent definition: #{e.message}"
        end
      end

      # Retrieves a single agent definition from Redis.
      # @param agent_name [String] The name of the agent to retrieve.
      # @return [Hash, nil] A hash representing the agent definition, or nil if not found.
      #   The hash includes keys: :name, :description, :tools (Array), :model, :fallback_mode (Symbol), :mcp_servers_json (String)
      # @raise [ConfigurationError] if Redis client is not available.
      # @raise [StoreError] for Redis errors during retrieval or JSON parsing errors.
      def get_definition(agent_name)
        raise ConfigurationError, "Redis client not available." unless @redis
        return nil if agent_name.nil? || agent_name.strip.empty?

        agent_key = agent_redis_key(agent_name)

        begin
          # Fetch all fields defined in AGENT_DEFINITION_FIELDS
          # Note: hmget returns an array of values in the order fields were requested.
          # If a field doesn't exist, it returns nil in that position.
          # If the key doesn't exist at all, it returns an array of nils.
          values = @redis.hmget(agent_key, *AGENT_DEFINITION_FIELDS)

          # Check if the key existed (e.g., by checking if the name field, which we always set, is present)
          # Or more reliably, check if all values are nil, which indicates the key itself is likely missing.
          return nil if values.all?(&:nil?)

          # Create a hash from fields and values
          definition_hash = Hash[AGENT_DEFINITION_FIELDS.zip(values)]

          # --- Process and Type Convert ---
          # Ensure name consistency (though fetched from hash)
          definition_hash['name'] = agent_name
          # Deserialize tools JSON
          tools_json = definition_hash['tools']
          definition_hash['tools'] = (tools_json && !tools_json.empty?) ? JSON.parse(tools_json) : []
          # Set default model if missing
          definition_hash['model'] ||= ADK::Agent::DEFAULT_MODEL
          # Convert fallback_mode to symbol
          fallback_str = definition_hash['fallback_mode']
          definition_hash['fallback_mode'] = (fallback_str == 'echo') ? :echo : :error
          # Ensure MCP JSON is present (defaults to '[]' if nil)
          definition_hash['mcp_servers_json'] ||= '[]'
          # --- Return symbol-keyed hash for consistency? ---
          # Let's convert keys to symbols for internal consistency, matching save_definition inputs.
          symbolized_hash = definition_hash.transform_keys(&:to_sym)

          @logger.debug("Retrieved definition for agent '#{agent_name}'.")
          symbolized_hash
        rescue JSON::ParserError => e
          @logger.error("Failed to parse JSON fields for agent '#{agent_name}': #{e.message}. Data: #{definition_hash.inspect}")
          raise StoreError, "Error parsing stored JSON data for agent '#{agent_name}'."
        rescue Redis::BaseError => e
          @logger.error("Redis error getting agent '#{agent_name}': #{e.class} - #{e.message}")
          raise StoreError, "Redis error getting agent definition: #{e.message}"
        rescue => e # Catch other unexpected errors
          @logger.error("Unexpected error getting agent '#{agent_name}': #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
          raise StoreError, "Unexpected error getting agent definition: #{e.message}"
        end
      end

      # Updates specific fields of an existing agent definition in Redis.
      # @param agent_name [String] The name of the agent to update.
      # @param updates_hash [Hash] A hash where keys are field names (Symbol or String)
      #   and values are the new values. e.g., { description: "New Desc", tools: ["tool1"] }
      # @return [Boolean] true if successful, false if agent not found or no updates applied.
      # @raise [ArgumentError] if input is invalid (e.g., empty updates, invalid MCP JSON).
      # @raise [ConfigurationError] if Redis client is not available.
      # @raise [StoreError] for Redis errors or other issues.
      def update_definition(agent_name, updates_hash)
        raise ConfigurationError, "Redis client not available." unless @redis
        raise ArgumentError, "Agent name cannot be empty." if agent_name.nil? || agent_name.strip.empty?
        raise ArgumentError, "Updates hash cannot be empty." if updates_hash.nil? || updates_hash.empty?

        agent_key = agent_redis_key(agent_name)

        # First, check if the agent actually exists using the set key for efficiency
        unless definition_exists?(agent_name)
          @logger.warn("Attempted to update non-existent agent: '#{agent_name}'")
          return false # Or raise NotFoundError? Returning false might align better with web app PUT logic.
        end

        # Prepare updates for Redis HSET (expects field-value pairs)
        redis_updates = {}
        updates_hash.each do |key, value|
          field_str = key.to_s # Ensure string keys for Redis fields

          # Handle specific serializations
          case field_str
          when 'tools'
            redis_updates[field_str] = value.is_a?(Array) ? value.to_json : '[]'
          when 'mcp_servers_json'
            mcp_json_to_save = (value.nil? || value.strip.empty?) ? '[]' : value.strip
            # Validate MCP JSON before adding to updates
            begin
              unless mcp_json_to_save == '[]'
                parsed_mcp = JSON.parse(mcp_json_to_save)
                raise ArgumentError, "MCP configuration must be a JSON array." unless parsed_mcp.is_a?(Array)
              end
              redis_updates[field_str] = mcp_json_to_save
            rescue JSON::ParserError => e
              @logger.error("Invalid MCP JSON provided for updating agent '#{agent_name}': #{e.message}")
              raise ArgumentError, "Invalid format for MCP Server Configurations: #{e.message}"
            end
          when 'fallback_mode' # Store as string
            redis_updates[field_str] = value.to_s
          when 'name' # Disallow changing the name via update, it's the primary key
            @logger.warn("Attempted to update agent name for '#{agent_name}', which is not allowed.")
            next # Skip this update
          else
            # Assume other fields can be stored directly (description, model)
            # Ensure we only try to update valid fields?
            if AGENT_DEFINITION_FIELDS.include?(field_str)
              redis_updates[field_str] = value
            else
              @logger.warn("Attempted to update unknown field '#{field_str}' for agent '#{agent_name}'. Ignoring.")
            end
          end
        end

        return false if redis_updates.empty? # No valid updates to apply

        begin
          # HSET returns the number of fields that were added (not updated).
          # Can use HSET with multiple field/value pairs directly.
          result = @redis.hset(agent_key, redis_updates)

          # We could check if result > 0 if we only wanted to return true on actual additions,
          # but for an update, success means the command executed without error.
          @logger.info("Agent definition '#{agent_name}' updated successfully with fields: #{redis_updates.keys.join(', ')}.")
          true # Indicate command succeeded
        rescue JSON::GeneratorError => e # Should only happen for tools serialization
          @logger.error("Failed to serialize tools array to JSON for updating agent '#{agent_name}': #{e.message}")
          raise StoreError, "Internal error serializing tool data for agent update."
        rescue Redis::BaseError => e
          @logger.error("Redis error updating agent '#{agent_name}': #{e.class} - #{e.message}")
          raise StoreError, "Redis error updating agent definition: #{e.message}"
        rescue ArgumentError => e # Re-raise specific argument errors from validation
          raise e
        rescue => e # Catch other unexpected errors
          @logger.error("Unexpected error updating agent '#{agent_name}': #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
          raise StoreError, "Unexpected error updating agent definition: #{e.message}"
        end
      end

      # Deletes an agent definition from Redis.
      # @param agent_name [String] The name of the agent to delete.
      # @return [Boolean] true if deletion was successful (or agent didn't exist), false otherwise.
      # @raise [ConfigurationError] if Redis client is not available.
      # @raise [StoreError] for Redis errors.
      def delete_definition(agent_name)
        raise ConfigurationError, "Redis client not available." unless @redis
        return true if agent_name.nil? || agent_name.strip.empty? # No name, nothing to delete

        agent_key = agent_redis_key(agent_name)

        begin
          # Use MULTI/EXEC for atomicity
          result = @redis.multi do |multi|
            multi.del(agent_key) # Delete the agent's hash
            multi.srem(AGENTS_SET_KEY, agent_name) # Remove name from the set
          end

          # MULTI returns an array of results. DEL returns num keys deleted (0 or 1).
          # SREM returns num members removed (0 or 1).
          if result.nil?
            @logger.error("Redis transaction for deleting agent '#{agent_name}' failed (aborted).")
            raise StoreError, "Redis transaction aborted while deleting agent '#{agent_name}'."
            # Optional: Check specific results if needed, e.g., if result == [0, 0] it means agent didn't exist.
            # else
            # num_deleted = result[0]
            # num_removed = result[1]
            # @logger.info("Agent definition '#{agent_name}' deleted. Hash deleted: #{num_deleted}, Name removed from set: #{num_removed}")
          end

          # Consider success if transaction completes without Redis error
          @logger.info("Agent definition '#{agent_name}' deleted successfully (or did not exist).")
          true
        rescue Redis::BaseError => e
          @logger.error("Redis error deleting agent '#{agent_name}': #{e.class} - #{e.message}")
          raise StoreError, "Redis error deleting agent definition: #{e.message}"
        rescue => e # Catch other unexpected errors
          @logger.error("Unexpected error deleting agent '#{agent_name}': #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
          raise StoreError, "Unexpected error deleting agent definition: #{e.message}"
        end
      end

      # Lists summary information for all defined agents.
      # @return [Array<Hash>] An array of hashes, each containing summary data
      #   (e.g., :name, :description, :model). Returns empty array if none found.
      # @raise [ConfigurationError] if Redis client is not available.
      # @raise [StoreError] for Redis errors.
      def list_definitions
        raise ConfigurationError, "Redis client not available." unless @redis

        definitions = []
        begin
          agent_names = @redis.smembers(AGENTS_SET_KEY)
          return [] if agent_names.empty?

          # Fields to fetch for the summary list
          summary_fields = %w[name description model]

          # Use pipelined HMGET for efficiency
          pipeline_results = @redis.pipelined do |pipe|
            agent_names.each do |name|
              pipe.hmget(agent_redis_key(name), *summary_fields)
            end
          end

          agent_names.zip(pipeline_results).each do |name, values|
            if values.is_a?(Array) && !values.all?(&:nil?)
              summary_hash = Hash[summary_fields.zip(values)]
              # Ensure name is present (should be from the list)
              summary_hash['name'] ||= name
              # Provide default model if missing
              summary_hash['model'] ||= ADK::Agent::DEFAULT_MODEL
              # Convert to symbol keys
              definitions << summary_hash.transform_keys(&:to_sym)
            else
              # This might happen if a name is in the set but the hash is missing (inconsistent state)
              @logger.warn("Inconsistency: Agent name '#{name}' found in set but hash key missing or empty.")
            end
          end

          @logger.debug("Listed #{definitions.count} agent definitions.")
          definitions.sort_by { |d| d[:name] } # Sort by name for predictable order
        rescue Redis::BaseError => e
          @logger.error("Redis error listing agents: #{e.class} - #{e.message}")
          raise StoreError, "Redis error listing agent definitions: #{e.message}"
        rescue => e # Catch other unexpected errors
          @logger.error("Unexpected error listing agents: #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
          raise StoreError, "Unexpected error listing agent definitions: #{e.message}"
        end
      end

      # Checks if an agent definition with the given name exists.
      # @param agent_name [String] The name of the agent to check.
      # @return [Boolean] true if the agent name exists in the set, false otherwise.
      # @raise [ConfigurationError] if Redis client is not available.
      # @raise [StoreError] for Redis errors.
      def definition_exists?(agent_name)
        raise ConfigurationError, "Redis client not available." unless @redis
        return false if agent_name.nil? || agent_name.strip.empty?

        begin
          exists = @redis.sismember(AGENTS_SET_KEY, agent_name)
          @logger.debug("Checked existence for agent '#{agent_name}': #{exists}")
          exists
        rescue Redis::BaseError => e
          @logger.error("Redis error checking agent existence for '#{agent_name}': #{e.class} - #{e.message}")
          raise StoreError, "Redis error checking agent existence: #{e.message}"
        rescue => e # Catch other unexpected errors
          @logger.error("Unexpected error checking agent existence for '#{agent_name}': #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
          raise StoreError, "Unexpected error checking agent existence: #{e.message}"
        end
      end

      # Checks the connection to the Redis server.
      # @return [Boolean] true if the connection is active (ping successful), false otherwise.
      # @raise [ConfigurationError] if Redis client has not been initialized.
      def check_connection
        raise ConfigurationError, "Redis client not available." unless @redis

        begin
          result = @redis.ping
          is_ok = (result == "PONG")
          # Silence because it's too noisy
          # @logger.debug("Redis connection check (PING): #{is_ok ? 'OK' : 'Failed'}")
          is_ok
        rescue Redis::BaseError => e
          @logger.error("Redis connection check failed: #{e.class} - #{e.message}")
          false
        rescue => e # Catch other unexpected errors
          @logger.error("Unexpected error during Redis connection check: #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
          false
        end
      end

      private

      def agent_redis_key(name)
        "#{AGENT_HASH_PREFIX}#{name}"
      end

      # Add other private helpers for serialization/deserialization etc.
    end
  end
end
