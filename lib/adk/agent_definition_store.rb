# File: lib/adk/agent_definition_store.rb
# frozen_string_literal: true

require 'redis'
require 'json'
require_relative '../adk' # Access ADK.logger, ADK.redis_options

module ADK
  # Manages Agent Definitions both in-memory and persistently in Redis.
  module AgentDefinitionStore
    # Redis Keys Constants (Consider sharing with CLI)
    REDIS_AGENT_HASH_PREFIX = 'adk:agent:'
    REDIS_AGENTS_SET_KEY = 'adk:agents:all_names'

    # In-memory storage for loaded/registered definitions
    # { agent_name_symbol => definition_hash }
    @@definitions = {}

    # --- In-Memory Operations --- #

    # Register/update a definition in the in-memory store.
    # @param name [Symbol, String] Agent name.
    # @param definition_hash [Hash] The definition data ({ description:, tools:, model: }).
    def self.register(name, definition_hash)
      name_sym = name.to_sym
      unless definition_hash.is_a?(Hash) && definition_hash.key?(:description)
        ADK.logger.warn("AgentDefinitionStore: Invalid definition hash provided for '#{name_sym}'. Skipping registration.")
        return false
      end
      # Ensure tools is an array of strings/symbols
      definition_hash[:tools] = Array(definition_hash[:tools]).map(&:to_s)
      definition_hash[:fallback_mode] = definition_hash[:fallback_mode].to_sym if definition_hash[:fallback_mode].is_a?(String)
      # Convert webhook_enabled from string to boolean if necessary
      if ['true', 'false'].include?(definition_hash[:webhook_enabled].to_s.downcase)
        definition_hash[:webhook_enabled] = definition_hash[:webhook_enabled].to_s.downcase == 'true'
      end
      @@definitions[name_sym] = definition_hash
      ADK.logger.debug("AgentDefinitionStore: Registered/updated definition for '#{name_sym}' in memory.")
      true
    end

    # Find a definition in the in-memory store.
    # @param name [Symbol, String] Agent name.
    # @return [Hash, nil] The definition hash or nil if not found.
    def self.find(name)
      @@definitions[name.to_sym]
    end

    # Remove a definition from the in-memory store.
    # @param name [Symbol, String] Agent name.
    def self.remove(name)
      name_sym = name.to_sym
      if @@definitions.delete(name_sym)
        ADK.logger.debug("AgentDefinitionStore: Removed definition for '#{name_sym}' from memory.")
      end
    end

    # Get all currently loaded definitions.
    # @return [Hash] Hash of all definitions.
    def self.all
      @@definitions.dup # Return a copy
    end

    # Get a list of all known agent names (from memory and Redis).
    # @return [Array<String>] List of agent names.
    def self.all_names
      in_memory_names = @@definitions.keys.map(&:to_s)

      begin
        redis = Redis.new(ADK.redis_options)
        redis_names = redis.smembers(REDIS_AGENTS_SET_KEY)
        redis.close
      rescue Redis::BaseError => e
        ADK.logger.warn("AgentDefinitionStore: Failed to fetch all names from Redis: #{e.message}")
        redis_names = []
      end

      (in_memory_names + redis_names).uniq.sort
    end

    # Clear the in-memory store (for testing).
    def self.reset!
      @@definitions = {}
    end

    # --- Redis Operations --- #

    # Helper to get Redis key
    def self.agent_redis_key(name)
      "#{REDIS_AGENT_HASH_PREFIX}#{name}"
    end

    # Save/update a definition to Redis.
    # @param name [Symbol, String] Agent name.
    # @param definition_hash [Hash] Definition data.
    # @return [Boolean] True on success, false on Redis error.
    def self.save_to_redis(name, definition_hash)
      name_str = name.to_s
      key = agent_redis_key(name_str)
      redis = Redis.new(ADK.redis_options)

      # Prepare data for Redis (string keys, tools as JSON string)
      redis_data = {
        'description' => definition_hash[:description].to_s,
        'tools' => Array(definition_hash[:tools]).map(&:to_s).to_json,
        'model' => definition_hash[:model].to_s,
        'instruction' => definition_hash[:instruction].to_s, # Convert nil to empty string
        'fallback_mode' => definition_hash[:fallback_mode].to_s, # Convert symbol to string
        'mcp_servers_json' => definition_hash[:mcp_servers_json].to_s, # Should be JSON string already or empty
        'webhook_enabled' => definition_hash[:webhook_enabled].to_s, # Convert boolean to string 'true'/'false'
        'webhook_secret' => definition_hash[:webhook_secret].to_s # Convert nil to empty string
      }

      redis.multi do |multi|
        multi.hmset(key, redis_data)
        multi.sadd(REDIS_AGENTS_SET_KEY, name_str)
      end
      ADK.logger.debug("AgentDefinitionStore: Saved definition for '#{name_str}' to Redis.")
      true
    rescue Redis::BaseError => e
      ADK.logger.error("AgentDefinitionStore: Failed to save '#{name_str}' to Redis: #{e.message}")
      false
    ensure
      redis&.close
    end

    # Load a single definition from Redis.
    # @param name [Symbol, String] Agent name.
    # @return [Hash, nil] Definition hash or nil if not found/error.
    def self.load_from_redis(name)
      name_str = name.to_s
      key = agent_redis_key(name_str)
      redis = Redis.new(ADK.redis_options)

      fields = ['description', 'tools', 'model', 'instruction', 'fallback_mode', 'mcp_servers_json', 'webhook_enabled', 'webhook_secret']
      data = redis.hmget(key, *fields)
      return nil unless data[0] # Return nil if description (and thus agent) not found

      {
        description: data[0],
        tools: JSON.parse(data[1] || '[]'), # Parse tools JSON, default to empty array
        model: data[2] || ADK::Agent::DEFAULT_MODEL, # Use default model if not set
        instruction: data[3], # Will be nil if not set, or empty string
        fallback_mode: data[4] ? data[4].to_sym : :error, # Convert to symbol, default to :error
        mcp_servers_json: data[5] || '[]', # Default to empty JSON array string
        webhook_enabled: data[6] == 'true', # Convert 'true' string to true, others to false
        webhook_secret: data[7] # Will be nil if not set, or empty string
      }
    rescue Redis::BaseError => e
      ADK.logger.error("AgentDefinitionStore: Failed to load '#{name_str}' from Redis: #{e.message}")
      nil
    rescue JSON::ParserError => e
      ADK.logger.error("AgentDefinitionStore: Failed to parse tools JSON for '#{name_str}' from Redis: #{e.message}. Data: #{data[1]}")
      # Return definition but with empty tools array and other fields defaulted
      {
        description: data[0],
        tools: [],
        model: data[2] || ADK::Agent::DEFAULT_MODEL,
        instruction: data[3],
        fallback_mode: data[4] ? data[4].to_sym : :error,
        mcp_servers_json: data[5] || '[]',
        webhook_enabled: data[6] == 'true',
        webhook_secret: data[7]
      }
    ensure
      redis&.close
    end

    # Load all definitions from Redis into the in-memory store.
    # @return [Integer] Number of definitions loaded.
    def self.load_all_from_redis
      redis = Redis.new(ADK.redis_options)
      agent_names = redis.smembers(REDIS_AGENTS_SET_KEY)
      loaded_count = 0
      reset! # Clear memory before loading

      # Use pipelining for efficiency
      definitions_data = redis.pipelined do |pipe|
        fields = ['description', 'tools', 'model', 'instruction', 'fallback_mode', 'mcp_servers_json', 'webhook_enabled', 'webhook_secret']
        agent_names.each { |name| pipe.hmget(agent_redis_key(name), *fields) }
      end

      agent_names.zip(definitions_data).each do |name, data|
        if data && data[0] # Check if data was retrieved and description exists
          begin
            definition = {
              description: data[0],
              tools: JSON.parse(data[1] || '[]'),
              model: data[2] || ADK::Agent::DEFAULT_MODEL,
              instruction: data[3],
              fallback_mode: data[4] ? data[4].to_sym : :error,
              mcp_servers_json: data[5] || '[]',
              webhook_enabled: data[6] == 'true',
              webhook_secret: data[7]
            }
            register(name, definition) # Register in memory
            loaded_count += 1
          rescue JSON::ParserError => e
            ADK.logger.error("AgentDefinitionStore: Failed to parse tools JSON for '#{name}' during load_all: #{e.message}")
          end
        else
          ADK.logger.warn("AgentDefinitionStore: Found name '#{name}' in set but definition missing/incomplete in Redis during load_all.")
        end
      end
      ADK.logger.info("AgentDefinitionStore: Loaded #{loaded_count} agent definitions from Redis into memory.")
      loaded_count
    rescue Redis::BaseError => e
      ADK.logger.error("AgentDefinitionStore: Failed to load all definitions from Redis: #{e.message}")
      0
    ensure
      redis&.close
    end

    # Delete a definition from Redis.
    # @param name [Symbol, String] Agent name.
    # @return [Boolean] True on success, false on Redis error.
    def self.delete_from_redis(name)
      name_str = name.to_s
      key = agent_redis_key(name_str)
      redis = Redis.new(ADK.redis_options)

      deleted_count = redis.multi do |multi|
        multi.del(key)
        multi.srem(REDIS_AGENTS_SET_KEY, name_str)
      end
      # Check if both commands succeeded (DEL returns num deleted, SREM returns 1 if removed)
      success = deleted_count[0] >= 0 && deleted_count[1] >= 0
      if success
        ADK.logger.debug("AgentDefinitionStore: Deleted definition for '#{name_str}' from Redis.")
      else
        ADK.logger.warn("AgentDefinitionStore: Delete command for '#{name_str}' ran but Redis reported unexpected results: #{deleted_count.inspect}")
      end
      success
    rescue Redis::BaseError => e
      ADK.logger.error("AgentDefinitionStore: Failed to delete '#{name_str}' from Redis: #{e.message}")
      false
    ensure
      redis&.close
    end
  end # End AgentDefinitionStore
end # End ADK
