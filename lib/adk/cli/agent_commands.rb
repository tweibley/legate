# File: lib/adk/cli/agent_commands.rb
# frozen_string_literal: true

require 'thor'
require 'redis'
require 'json'
require_relative '../tool_registry' # Require registry for execute fallback
require_relative '../agent' # Require Agent class for start/execute

module ADK
  module CLI
    # CLI commands for agent definition management AND execution
    class AgentCommands < Thor
      # --- Redis Configuration ---
      REDIS_AGENT_HASH_PREFIX = "adk:agent:"
      REDIS_AGENTS_SET_KEY = "adk:agents:all_names"

      no_commands do
        def agent_redis_key(name)
          "#{REDIS_AGENT_HASH_PREFIX}#{name}"
        end

        def connect_redis
          redis = Redis.new # Assumes localhost:6379
          redis.ping # Verify connection
          redis
        rescue Redis::CannotConnectError => e
          say "Error: Could not connect to Redis. Is it running? (#{e.message})", :red
          exit(1) # Exit if Redis is unavailable
        end

        def parse_tools(tools_json)
          return [] unless tools_json && !tools_json.empty?

          JSON.parse(tools_json) rescue [] # Return empty array on parse error
        end
      end
      # --- End Redis Configuration ---

      # --- Definition Management Commands ---
      desc 'list', 'List all defined agents from Redis'
      def list
        redis = connect_redis
        agent_names = redis.smembers(REDIS_AGENTS_SET_KEY).sort

        if agent_names.empty?
          say "No agent definitions found in Redis."
          return
        end

        say "Defined Agents:", :bold
        # Fetch data efficiently using pipelined HMGET
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
      method_option :description, type: :string, required: true
      # TODO: Add --tools option to select tools via CLI
      def create(name)
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
            say "Agent definition '#{name}' created successfully in Redis (Tools: None).", :green
          else
            say "Warning: Agent definition command executed, but Redis reported unexpected results: #{results.inspect}. Please verify.",
                :yellow
          end
        rescue Redis::BaseError => e
          say "Error: Failed to save agent definition to Redis: #{e.message}", :red
          exit(1)
        end
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
      # --- End Definition Management Commands ---

      # --- Runtime/Execution Commands ---

      desc 'start NAME', 'Verify agent definition loading and start (Ephemeral)'
      long_desc <<-LONGDESC
        Loads the agent definition (name, description, tools) from Redis,
        instantiates the agent object, adds its configured tools, and calls start().

        This command verifies that the agent can be loaded correctly based on its
        persisted definition.

        NOTE: This command does NOT start a persistent background process.
        The agent instance exists only for the duration of this command execution.
      LONGDESC
      def start(name)
        say "Attempting to load and start agent '#{name}' based on Redis definition..."
        redis = connect_redis
        key = agent_redis_key(name)

        # Fetch definition
        redis_agent_data = redis.hmget(key, 'description', 'tools')
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]

        unless description
          say "Error: Agent definition '#{name}' not found in Redis.", :red
          exit(1)
        end

        begin
          # Instantiate agent
          agent = ADK::Agent.new(name: name, description: description)

          # Load configured tools
          tool_names_to_load = parse_tools(tools_json_string).map(&:to_sym)
          added_tools_names = []
          if tool_names_to_load.empty?
            say "  - No tools configured for this agent.", :yellow
          else
            say "  - Adding configured tools: #{tool_names_to_load.join(', ')}", :cyan
            tool_names_to_load.each do |tool_name|
              tool_instance = ADK::ToolRegistry.create_instance(tool_name)
              if tool_instance
                agent.add_tool(tool_instance)
                added_tools_names << tool_name
              else
                say "  - Warning: Configured tool '#{tool_name}' not found in registry.", :yellow
              end
            end
          end

          # Call agent's start method
          agent.start
          say "Agent '#{name}' (with tools: [#{added_tools_names.join(', ')}]) loaded and started successfully (instance finished).",
              :green
        rescue StandardError => e
          say "Error during agent instantiation or start: #{e.class} - #{e.message}", :red
          # puts e.backtrace if options[:verbose] # Consider adding --verbose flag later
          exit(1)
        end
      end

      # --- 'stop' command removed ---

      desc 'execute NAME TASK', 'Execute a task using the agent definition from Redis'
      long_desc <<-LONGDESC
        Loads the agent definition (name, description, tools) from Redis,
        instantiates the agent, adds its configured tools, starts it, runs the specified TASK,
        prints the result, stops the agent, and exits.

        This executes the full agent lifecycle for a single task based on the
        persisted definition.
      LONGDESC
      def execute(name, task)
        say "Loading agent '#{name}' to execute task: \"#{task}\"..."
        redis = connect_redis
        key = agent_redis_key(name)

        # Fetch definition
        redis_agent_data = redis.hmget(key, 'description', 'tools')
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]

        unless description
          say "Error: Agent definition '#{name}' not found in Redis.", :red
          exit(1)
        end

        begin
          # Instantiate agent
          agent = ADK::Agent.new(name: name, description: description)

          # Load configured tools
          tool_names_to_load = parse_tools(tools_json_string).map(&:to_sym)
          if tool_names_to_load.empty?
            say "  - Warning: Agent has no tools configured.", :yellow
          else
            say "  - Adding configured tools: [#{tool_names_to_load.join(', ')}]", :cyan
            tool_names_to_load.each do |tool_name|
              tool_instance = ADK::ToolRegistry.create_instance(tool_name)
              agent.add_tool(tool_instance) if tool_instance # Silently skip if tool not found now
            end
          end

          # Start, Run, Stop
          say "  - Starting agent #{agent.name}...", :cyan, false
          agent.start
          say "started.", :cyan

          say "  - Running task...", :cyan, false
          result = agent.run_task(task)
          say "finished.", :cyan
          say "  - Stopping agent...", :cyan, false
          agent.stop
          say "stopped.", :cyan

          # Output result
          say ""
          say "Task Result:", :green
          say result, :green
        rescue StandardError => e
          say "Error during agent execution: #{e.class} - #{e.message}", :red
          # Try to stop agent even if task failed
          agent&.stop rescue nil
          say "Agent #{agent.name} stopped!", :cyan

          # puts e.backtrace if options[:verbose]
          exit(1)
        end
      end
      # --- End Runtime/Execution Commands ---
    end # End AgentCommands class
  end # End CLI module
end # End ADK module
