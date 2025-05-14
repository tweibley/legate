# File: lib/adk/definition_store/redis_store.rb
# frozen_string_literal: true

require 'redis'
require 'json'
require_relative '../../adk/version' # Correct relative path
require_relative '../errors'

module ADK
  module DefinitionStore
    # Redis-backed implementation for storing and retrieving agent definitions.
    class RedisStore
      # Define Redis keys
      AGENT_HASH_PREFIX = 'adk:agent:'
      AGENTS_SET_KEY = 'adk:agents:all_names'

      # NOTE: Validator, Transformer, Extractor are Procs and cannot be directly serialized to Redis easily.
      # They are handled by the AgentDefinition object in memory, not persisted here by default.
      # Expected field names in the Redis hash
      AGENT_DEFINITION_FIELDS = %w[name description tools model fallback_mode mcp_servers_json instruction
                                   webhook_enabled webhook_secret persistent_status agent_type].freeze

      # Expects a keyword argument for the Redis client instance.
      # @param redis_client [Redis] An instance of the Redis client.
      def initialize(redis_client:)
        @redis = redis_client
        @logger = ADK.logger
        @logger.info('ADK::DefinitionStore::RedisStore initialized.')
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
      # @param instruction [String, nil] Optional instructions for the agent.
      # @param webhook_enabled [Boolean] Whether webhooks are enabled.
      # @param webhook_secret [String, nil] Secret for webhook validation.
      # @param agent_type [Symbol, String] The type of agent (:llm, :sequential, :parallel, :loop). Defaults to :llm.
      # @return [Boolean] true if successful, false otherwise.
      # @raise [ArgumentError] if required fields (name) are missing or invalid.
      # @raise [ConfigurationError] if Redis client is not available.
      # @raise [StoreError] for Redis errors during save.
      def save_definition(name:, description:, tools:, model:, fallback_mode:, mcp_servers_json:, instruction: nil,
                          webhook_enabled: false, webhook_secret: nil, agent_type: :llm)
        raise ConfigurationError, 'Redis client not available.' unless @redis
        raise ArgumentError, 'Agent name cannot be empty.' if name.nil? || name.strip.empty?

        # Optional: Add more validation for other fields if needed

        agent_key = agent_redis_key(name)
        fallback_str = fallback_mode.to_s # Store as string
        mcp_json_to_save = (mcp_servers_json.nil? || mcp_servers_json.strip.empty?) ? '[]' : mcp_servers_json.strip
        
        # Convert agent_type to string
        agent_type_str = agent_type.to_s

        begin
          # Validate MCP JSON before saving
          unless mcp_json_to_save == '[]'
            parsed_mcp = JSON.parse(mcp_json_to_save)
            raise ArgumentError, 'MCP configuration must be a JSON array.' unless parsed_mcp.is_a?(Array)
          end

          tools_json = tools.is_a?(Array) ? tools.to_json : '[]'

          # Use MULTI/EXEC to ensure atomicity
          result = @redis.multi do |multi|
            multi.hset(agent_key, 'name', name) # Store name in hash too for easier retrieval
            multi.hset(agent_key, 'description', description || '')
            multi.hset(agent_key, 'tools', tools_json)
            multi.hset(agent_key, 'model', model || ADK::Agent::DEFAULT_MODEL) # Use default if nil
            multi.hset(agent_key, 'fallback_mode', fallback_str)
            multi.hset(agent_key, 'mcp_servers_json', mcp_json_to_save)
            multi.hset(agent_key, 'instruction', instruction || '') # Save instruction (empty string if nil)
            multi.hset(agent_key, 'webhook_enabled', webhook_enabled.to_s) # Store boolean as string ('true'/'false')
            multi.hset(agent_key, 'webhook_secret', webhook_secret || '') # Store secret (empty if nil)
            multi.hset(agent_key, 'persistent_status', 'stopped') # Default new agents to 'stopped'
            multi.hset(agent_key, 'agent_type', agent_type_str) # Store agent type as string
            multi.sadd(AGENTS_SET_KEY, name)
          end

          # Check results - Redis MULTI returns an array of results for each command
          # For HSET, it returns integer (1 if new field, 0 if updated). For SADD, integer (1 if added, 0 if exists).
          # We mainly care if the transaction succeeded without error. Redis errors within MULTI abort it.
          if result.nil?
            # This happens if the transaction was aborted (e.g., due to WATCH)
            @logger.error("Redis transaction for saving agent '#{name}' failed (aborted).")
            raise StoreError, "Redis transaction aborted while saving agent '#{name}'."
          # Check if result is an array before calling any? or checking contents
          elsif result.is_a?(Array) && result.any? { |r| r.is_a?(Redis::CommandError) }
            # Check if any individual command resulted in an error object (shouldn't typically happen with these commands unless connection issue)
            @logger.error("Redis command error during multi for saving agent '#{name}': #{result.inspect}")
            raise StoreError, "Redis command error while saving agent '#{name}'."
          # Handle non-array result (e.g., `true` which some redis clients might return on simple success?)
          # Assuming non-array and non-nil means success if no error was raised during MULTI
          elsif !result.is_a?(Array)
            @logger.debug("Redis MULTI returned non-array result for agent '#{name}': #{result.inspect}. Assuming success.")
            true
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
      # @return [Hash, nil] A hash representing the agent definition (symbol keys), or nil if not found.
      #   Includes :name, :description, :tools, :model, :fallback_mode, :mcp_servers_json, :instruction, :webhook_enabled, :webhook_secret
      # @raise [ConfigurationError] if Redis client is not available.
      # @raise [StoreError] for Redis errors during retrieval or JSON parsing errors.
      def get_definition(agent_name)
        # Convert symbol to string if needed
        agent_name_str = agent_name.to_s
        raise ConfigurationError, 'Redis client not available.' unless @redis
        return nil if agent_name_str.nil? || agent_name_str.strip.empty?

        agent_key = agent_redis_key(agent_name_str) # Use string key

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
          # Use original agent_name symbol for consistency
          definition_hash['name'] = agent_name.is_a?(Symbol) ? agent_name : agent_name_str.to_sym
          # Deserialize tools JSON
          tools_json = definition_hash['tools']
          # Convert tool names to symbols
          definition_hash['tools'] = (tools_json && !tools_json.empty?) ? JSON.parse(tools_json).map(&:to_sym) : []
          # Set default model if missing
          definition_hash['model'] ||= ADK::Agent::DEFAULT_MODEL
          # Convert fallback_mode to symbol
          fallback_str = definition_hash['fallback_mode']
          definition_hash['fallback_mode'] = (fallback_str == 'echo') ? :echo : :error
          # Ensure MCP JSON is present (defaults to '[]' if nil)
          definition_hash['mcp_servers_json'] ||= '[]'
          # Ensure instruction is present (defaults to '' if nil)
          definition_hash['instruction'] ||= '' # Ensure instruction defaults to empty string if missing in Redis
          # --- Process Webhook Fields ---
          definition_hash['webhook_enabled'] = (definition_hash['webhook_enabled'] == 'true') # Convert string back to boolean
          definition_hash['webhook_secret'] = definition_hash['webhook_secret'] # Already string (or empty string)
          definition_hash['webhook_secret'] = nil if definition_hash['webhook_secret']&.empty? # Convert empty string back to nil
          # --- Process persistent_status ---
          definition_hash['persistent_status'] ||= 'stopped' # Default to 'stopped' if not present
          # --- Process agent_type ---
          agent_type_str = definition_hash['agent_type']
          if agent_type_str && !agent_type_str.empty?
            valid_types = %w[llm sequential parallel loop]
            definition_hash['agent_type'] = valid_types.include?(agent_type_str) ? agent_type_str.to_sym : :llm
          else
            definition_hash['agent_type'] = :llm # Default to :llm if not present or empty
          end
          # Note: Procs (validator, transformer, extractor) are not stored/retrieved.
          # --- END Webhook Fields ---
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
        raise ConfigurationError, 'Redis client not available.' unless @redis

        # Convert agent_name to string before calling strip
        agent_name_str = agent_name.to_s
        raise ArgumentError, 'Agent name cannot be empty.' if agent_name_str.nil? || agent_name_str.strip.empty?
        raise ArgumentError, 'Updates hash cannot be empty.' if updates_hash.nil? || updates_hash.empty?

        agent_key = agent_redis_key(agent_name_str) # Use stringified name for key

        # Check existence using the original name (definition_exists? handles symbols/strings)
        unless definition_exists?(agent_name)
          @logger.warn("Attempted to update non-existent agent: '#{agent_name}'")
          return false
        end

        # === START SPECIAL CASE ===
        # Check if this is ONLY a persistent_status update
        updates_hash_keys = updates_hash.keys.map(&:to_s)
        if updates_hash_keys.length == 1 && updates_hash_keys.first == 'persistent_status'
          status_val = updates_hash.values.first.to_s
          if %w[running stopped unknown].include?(status_val)
            begin
              @redis.hset(agent_key, 'persistent_status', status_val)
              @logger.info("Agent definition '#{agent_name}' updated successfully with fields: persistent_status (special case).")
              return true # Successfully handled the special case
            rescue Redis::BaseError => e
              @logger.error("Redis error updating agent '#{agent_name}' (special case persistent_status): #{e.class} - #{e.message}")
              raise StoreError, "Redis error updating agent definition: #{e.message}"
            end
          else
            @logger.warn("Attempted to update persistent_status with invalid value '#{status_val}' for agent '#{agent_name}' (special case). Ignoring.")
            return false # Treat as no-op / invalid update
          end
        end
        # === END SPECIAL CASE ===

        # If not the special case, proceed with the normal iteration and case statement
        redis_updates = {}
        updates_hash.each do |key, value|
          field_str = key.to_s

          case field_str
          when 'tools'
            # Wrap the specific call that can raise JSON::GeneratorError
            begin
              redis_updates[field_str] = value.is_a?(Array) ? value.to_json : '[]'
            rescue JSON::GeneratorError => e
              @logger.error("JSON error serializing tools for agent '#{agent_name}': #{e.message}")
              raise StoreError, "Failed to serialize tools for agent '#{agent_name}'."
            end
          when 'model'
            redis_updates[field_str] = value&.to_s || ADK::Agent::DEFAULT_MODEL
          when 'fallback_mode'
            redis_updates[field_str] = value&.to_s || 'error'
          when 'mcp_servers_json', 'mcp_servers'
            # Handle both key formats (consistency with hash types)
            if value.is_a?(String)
              # Try to validate if not empty
              if !value.strip.empty? && value.strip != '[]'
                begin
                  parsed = JSON.parse(value)
                  raise ArgumentError, 'MCP servers must be an array.' unless parsed.is_a?(Array)
                rescue JSON::ParserError => e
                  @logger.error("Invalid MCP servers JSON for agent '#{agent_name}': #{e.message}")
                  raise ArgumentError, "Invalid MCP servers JSON: #{e.message}"
                end
              end
              redis_updates['mcp_servers_json'] = value.strip.empty? ? '[]' : value.strip
            elsif value.is_a?(Array)
              # Convert Ruby array to JSON string
              begin
                redis_updates['mcp_servers_json'] = value.to_json
              rescue JSON::GeneratorError => e
                @logger.error("Failed to convert MCP servers to JSON for agent '#{agent_name}': #{e.message}")
                raise StoreError, "Could not serialize MCP servers: #{e.message}"
              end
            else
              # Default to empty array for any other type
              redis_updates['mcp_servers_json'] = '[]'
            end
          when 'instruction'
            redis_updates[field_str] = value&.to_s || ''
          when 'webhook_enabled'
            # Convert various truthy/falsy values to string 'true'/'false'
            redis_updates[field_str] = (!!value).to_s
          when 'webhook_secret'
            redis_updates[field_str] = value&.to_s || ''
          when 'agent_type'
            # Convert agent_type to string, validating it first
            agent_type_val = value&.to_s || 'llm'
            valid_types = %w[llm sequential parallel loop]
            if valid_types.include?(agent_type_val)
              redis_updates[field_str] = agent_type_val
            else
              # If invalid, default to 'llm'
              @logger.warn("Invalid agent_type '#{agent_type_val}' for agent '#{agent_name}'. Using 'llm' instead.")
              redis_updates[field_str] = 'llm'
            end
          else
            # Handle other fields generically as strings
            redis_updates[field_str] = value&.to_s || ''
          end
        end # end of .each loop

        return false if redis_updates.empty? # No valid updates to apply

        begin
          result = @redis.hset(agent_key, redis_updates)
          @logger.info("Agent definition '#{agent_name}' updated successfully with fields: #{redis_updates.keys.join(', ')}.")
          true
        rescue Redis::BaseError => e
          @logger.error("Redis error updating agent '#{agent_name}': #{e.class} - #{e.message}")
          raise StoreError, "Redis error updating agent definition: #{e.message}"
        rescue => e
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
        raise ConfigurationError, 'Redis client not available.' unless @redis
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
      #   (e.g., :name, :description, :model, :tools). Returns empty array if none found.
      # @raise [ConfigurationError] if Redis client is not available.
      # @raise [StoreError] for Redis errors.
      def list_definitions
        raise ConfigurationError, 'Redis client not available.' unless @redis

        definitions = []
        begin
          agent_names = @redis.smembers(AGENTS_SET_KEY)
          return [] if agent_names.empty?

          # Fields to fetch for the summary list - Use fully qualified constant and dup
          summary_fields = ADK::DefinitionStore::RedisStore::AGENT_DEFINITION_FIELDS.dup

          # Use pipelined HMGET for efficiency
          pipeline_results = @redis.pipelined do |pipe|
            agent_names.each do |name|
              pipe.hmget(agent_redis_key(name), *summary_fields)
            end
          end

          # Handle cases where pipelined might return something other than an array
          # (though typically it should return an array of results or raise an error)
          unless pipeline_results.is_a?(Array)
            @logger.error("Redis pipeline returned unexpected type: #{pipeline_results.class}. Expected Array. Agent Names: #{agent_names.inspect}")
            raise StoreError, 'Unexpected result type from Redis pipeline.'
          end

          agent_names.zip(pipeline_results).each do |name, values|
            if values.is_a?(Array) && !values.all?(&:nil?)
              # Process valid data
              summary_hash = Hash[ADK::DefinitionStore::RedisStore::AGENT_DEFINITION_FIELDS.zip(values)]
              summary_hash['name'] ||= name
              summary_hash['model'] ||= ADK::Agent::DEFAULT_MODEL
              tools_json = summary_hash['tools']
              parsed_tools = []
              if tools_json && !tools_json.empty?
                begin
                  parsed_tools = JSON.parse(tools_json)
                  parsed_tools = [] unless parsed_tools.is_a?(Array)
                rescue JSON::ParserError
                  @logger.warn("Failed to parse tools JSON for agent '#{name}' during listing. Defaulting to empty. Data: #{tools_json.inspect}")
                end
              end
              summary_hash['tools'] = parsed_tools.map(&:to_sym) # Convert tool strings to symbols
              # Ensure defaults for other potentially nil fields returned from hmget
              # Convert fallback_mode string to symbol
              fb_mode_str = summary_hash['fallback_mode']
              summary_hash['fallback_mode'] = (fb_mode_str == 'echo') ? :echo : :error
              summary_hash['mcp_servers_json'] ||= '[]' # Use '[]' if nil/missing
              summary_hash['instruction'] ||= '' # Use empty string if nil/missing
              # Convert agent name to symbol before transforming keys
              summary_hash['name'] = summary_hash['name'].to_sym if summary_hash['name']
              definitions << summary_hash.transform_keys(&:to_sym)
            elsif values.is_a?(Array) # Log warning only if it was an array but all nil
              @logger.warn("Inconsistency: Agent name '#{name}' found in set but hash key missing or empty.")
              # Do NOT add to definitions array
              # else - Handle case where `values` itself is not an array (should be caught by pipeline check earlier, but belt-and-suspenders)
              #   @logger.error("Unexpected data type received for agent '#{name}' in pipeline results: #{values.class}")
            end
          end

          @logger.debug("Listed #{definitions.count} agent definitions.")
          definitions.sort_by { |d| d[:name] } # Sort by name for predictable order
        # Remove the outer JSON::ParserError rescue, handle inline now
        rescue Redis::BaseError => e
          @logger.error("Redis error listing agents: #{e.class} - #{e.message}")
          raise StoreError, "Redis error listing agent definitions: #{e.message}"
        # Reinstate generic rescue block
        rescue => e
          @logger.error("Unexpected error listing agents: #{e.class} - #{e.message}\\n#{e.backtrace.first(5).join("\\n")}")
          raise StoreError, "Unexpected error listing agent definitions: #{e.message}"
        end
      end

      # Checks if an agent definition with the given name exists.
      # @param agent_name [String] The name of the agent to check.
      # @return [Boolean] true if the agent name exists in the set, false otherwise.
      # @raise [ConfigurationError] if Redis client is not available.
      # @raise [StoreError] for Redis errors.
      def definition_exists?(agent_name)
        raise ConfigurationError, 'Redis client not available.' unless @redis

        # Convert to string before stripping
        agent_name_str = agent_name.to_s
        return false if agent_name_str.nil? || agent_name_str.strip.empty?

        begin
          # Use the string version for Redis command
          exists = @redis.sismember(AGENTS_SET_KEY, agent_name_str)
          @logger.debug("Checked existence for agent '#{agent_name_str}': #{exists}")
          exists
        rescue Redis::BaseError => e
          @logger.error("Redis error checking agent existence for '#{agent_name_str}': #{e.class} - #{e.message}")
          raise StoreError, "Redis error checking agent existence: #{e.message}"
        rescue => e # Catch other unexpected errors
          @logger.error("Unexpected error checking agent existence for '#{agent_name_str}': #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
          raise StoreError, "Unexpected error checking agent existence: #{e.message}"
        end
      end

      # Checks the connection to the Redis server.
      # @return [Boolean] true if the connection is active (ping successful), false otherwise.
      # @raise [ConfigurationError] if Redis client has not been initialized.
      def check_connection
        raise ConfigurationError, 'Redis client not available.' unless @redis

        begin
          result = @redis.ping
          is_ok = (result == 'PONG')
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
