# File: lib/adk/cli/agent_commands.rb
# frozen_string_literal: true

require 'thor'
require 'redis'
require 'json'
require_relative '../tool_registry' # Keep this for the 'execute' fallback
require_relative '../agent' # Add require for ADK::Agent for start/stop/execute

module ADK
  module CLI
    # CLI commands for agent definition management AND temporary execution
    class AgentCommands < Thor
      # --- Redis Configuration ---
      REDIS_AGENT_HASH_PREFIX = "adk:agent:"
      REDIS_AGENTS_SET_KEY = "adk:agents:all_names"

      no_commands do
        def agent_redis_key(name)
          "#{REDIS_AGENT_HASH_PREFIX}#{name}"
        end

        def connect_redis
          redis = Redis.new
          redis.ping
          redis
        rescue Redis::CannotConnectError => e
          say "Error: Could not connect to Redis. Is it running? (#{e.message})", :red
          exit(1)
        end

        def parse_tools(tools_json)
          return [] unless tools_json && !tools_json.empty?

          JSON.parse(tools_json) rescue []
        end
      end
      # --- End Redis Configuration ---

      desc 'list', 'List all defined agents from Redis'
      def list
        redis = connect_redis
        agent_names = redis.smembers(REDIS_AGENTS_SET_KEY).sort

        if agent_names.empty?
          say "No agent definitions found in Redis."
          return
        end

        say "Defined Agents:", :bold
        agents_data = redis.pipelined do |pipe|
          agent_names.each do |name|
            pipe.hmget(agent_redis_key(name), 'description', 'tools')
          end
        end

        agent_names.zip(agents_data).each do |name, data|
          description = data[0] || "[No description]"
          tools = parse_tools(data[1])
          tools_str = tools.empty? ? "None" : tools.join(', ')
          say "- #{name}: #{description} (Tools: #{tools_str})"
        end
      end

      desc 'create NAME', 'Create a new agent definition in Redis'
      method_option :description, type: :string, desc: 'Agent description', required: true
      def create(name)
        # --- THIS IS THE CORRECT 'create' METHOD ---
        redis = connect_redis
        key = agent_redis_key(name)

        if redis.sismember(REDIS_AGENTS_SET_KEY, name)
          say "Error: Agent definition '#{name}' already exists.", :red
          exit(1)
        end

        description = options[:description]
        selected_tools = [] # Default: No tools configured via CLI yet
        tools_json = selected_tools.to_json

        begin
          results = redis.multi do |multi|
            multi.hset(key, 'description', description)
            multi.hset(key, 'tools', tools_json)
            multi.sadd(REDIS_AGENTS_SET_KEY, name)
          end
          if results.is_a?(Array) && results.length == 3 && results[0].is_a?(Integer) && results[1].is_a?(Integer) && results[2] == 1
            say "Agent definition '#{name}' created successfully in Redis (with no tools configured).", :green
          else
            say "Warning: Agent definition command executed, but Redis reported unexpected results: #{results.inspect}. Please verify.",
                :yellow
          end
        rescue Redis::BaseError => e
          say "Error: Failed to save agent definition to Redis: #{e.message}", :red
          exit(1)
        end
        # --- END CORRECT 'create' METHOD ---
      end

      desc 'delete NAME', "Delete an agent's definition from Redis"
      def delete(name)
        redis = connect_redis
        key = agent_redis_key(name)

        unless redis.exists?(key)
          say "Error: Agent definition '#{name}' not found.", :red
          exit(1)
        end

        if yes?("Are you sure you want to permanently delete agent definition '#{name}'? [y/N]", :yellow)
          begin
            deleted_count = redis.multi do |multi|
              multi.del(key)
              multi.srem(REDIS_AGENTS_SET_KEY, name)
            end
            if deleted_count[0] >= 1 && deleted_count[1] >= 1
              say "Agent definition '#{name}' deleted successfully.", :green
            else
              say "Warning: Deletion command ran but Redis reported unexpected results: #{deleted_count.inspect}",
                  :yellow
            end
          rescue Redis::BaseError => e
            say "Error: Failed to delete agent definition from Redis: #{e.message}", :red
            exit(1)
          end
        else
          say "Deletion cancelled.", :cyan
        end
      end

      # --- Temporary Instance Commands (No Redis Interaction) ---
      desc 'start NAME', '[Temporary Instance] Start a temporary agent instance (does not use Redis definition)'
      def start(name)
        say "Warning: This command starts a temporary, non-persisted agent instance.", :yellow
        # Requires ADK::Agent definition
        agent = ADK::Agent.new(name: name, description: 'Temporary Loaded agent')
        agent.start
        puts "Started temporary agent instance: #{agent.name}"
      end

      desc 'stop NAME', '[Temporary Instance] Stop a temporary agent instance'
      def stop(name)
        say "Warning: This command only affects temporary instances created by 'adk agent start'.", :yellow
        # Requires ADK::Agent definition
        agent = ADK::Agent.new(name: name, description: 'Temporary Loaded agent')
        agent.stop
        puts "Stopped temporary agent instance: #{agent.name}"
      end

      desc 'execute NAME TASK', '[Temporary Instance] Execute task on temporary agent instance'
      def execute(name, task)
        say "Warning: This command uses a temporary, non-persisted agent instance.", :yellow
        # Requires ADK::Agent definition
        agent = ADK::Agent.new(name: name, description: 'Temporary Loaded agent')
        # Add default tools for basic execution
        begin
          echo = ADK::ToolRegistry.create_instance(:echo)
          agent.add_tool(echo) if echo
          calc = ADK::ToolRegistry.create_instance(:calculator)
          agent.add_tool(calc) if calc
        rescue NameError
          say "Warning: ToolRegistry not loaded, cannot add default tools to temporary agent.", :yellow
        end

        agent.start
        result = agent.run_task(task)
        puts "Task result: #{result}"
        agent.stop
      end
    end
  end
end
