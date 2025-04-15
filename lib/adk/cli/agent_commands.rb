# File: lib/adk/cli/agent_commands.rb
# frozen_string_literal: true

require 'thor'
require 'redis'
require 'json'
require_relative '../tool_registry' # Require registry for validation and execute fallback
require_relative '../agent' # Require Agent class for start/execute

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
      method_option :description, type: :string, required: true, desc: 'Agent description'
      # --- Add --tools option ---
      method_option :tools,
                    type: :string, # Read as a single string
                    aliases: "-t",
                    desc: 'Comma-separated list of tool names to assign (e.g., "echo,calculator")'
      # --- End --tools option ---
      def create(name)
        redis = connect_redis
        key = agent_redis_key(name)

        if redis.sismember(REDIS_AGENTS_SET_KEY, name)
          say "Error: Agent definition '#{name}' already exists.", :red
          exit(1)
        end

        description = options[:description]

        # --- Process --tools option ---
        selected_tools = []
        valid_tools = ADK::ToolRegistry.list_tools.map { |t| t[:name].to_s } # Get valid tool names as strings

        if options[:tools]
          requested_tools = options[:tools].split(',').map(&:strip).reject(&:empty?)
          requested_tools.each do |tool_name|
            if valid_tools.include?(tool_name)
              selected_tools << tool_name unless selected_tools.include?(tool_name) # Add if valid and not duplicate
            else
              say "Warning: Unknown tool '#{tool_name}' specified, ignoring.", :yellow
            end
          end
        end
        tools_json = selected_tools.to_json
        # --- End process --tools ---

        begin
          results = redis.multi do |multi|
            multi.hset(key, 'description', description)
            multi.hset(key, 'tools', tools_json) # Save processed tools list
            multi.sadd(REDIS_AGENTS_SET_KEY, name)
          end
          # Check results more thoroughly
          if results.is_a?(Array) && results.length == 3 && results[0].is_a?(Integer) && results[1].is_a?(Integer) && results[2] == 1
            tools_msg = selected_tools.empty? ? "None" : selected_tools.join(', ')
            say "Agent definition '#{name}' created successfully (Tools: #{tools_msg}).", :green
          else
            say "Warning: Agent definition command executed, but Redis reported unexpected results: #{results.inspect}. Please verify.",
                :yellow
          end
        rescue Redis::BaseError => e
          say "Error: Failed to save agent definition to Redis: #{e.message}", :red
          exit(1)
        end
      end

      # --- Add Update Command ---
      desc 'update NAME', 'Update an existing agent definition in Redis'
      method_option :description, type: :string, desc: "New description for the agent"
      method_option :tools, type: :string, aliases: "-t",
                            desc: 'REPLACE existing tools with this comma-separated list (e.g., "echo,calculator")'
      method_option :add_tool, type: :string, repeatable: true, # Thor allows repeating this option
                               desc: 'Add a specific tool to the agent (can be used multiple times)'
      method_option :remove_tool, type: :string, repeatable: true,
                                  desc: 'Remove a specific tool from the agent (can be used multiple times)'
      def update(name)
        redis = connect_redis
        key = agent_redis_key(name)

        # Check if agent definition exists
        unless redis.exists?(key)
          say "Error: Agent definition '#{name}' not found.", :red
          exit(1)
        end

        # Fetch current data
        current_description, current_tools_json = redis.hmget(key, 'description', 'tools')
        current_tools = parse_tools(current_tools_json) # Array of string names

        # Prepare updates
        updates = {}
        final_tools = current_tools.dup # Start with current tools

        # Update description if provided
        if options[:description]
          updates['description'] = options[:description]
          say "Updating description.", :cyan
        end

        # Handle --tools (replacement)
        if options[:tools]
          # This option REPLACES the entire tool list
          valid_tools = ADK::ToolRegistry.list_tools.map { |t| t[:name].to_s }
          requested_tools = options[:tools].split(',').map(&:strip).reject(&:empty?)
          new_tool_list = []
          requested_tools.each do |tool_name|
            if valid_tools.include?(tool_name)
              new_tool_list << tool_name unless new_tool_list.include?(tool_name)
            else
              say "Warning: Unknown tool '#{tool_name}' specified in --tools, ignoring.", :yellow
            end
          end
          final_tools = new_tool_list # Replace the list
          say "Replacing tools with: [#{final_tools.join(', ')}].", :cyan
          updates['tools'] = final_tools.to_json
        else
          # Handle --add-tool and --remove-tool only if --tools wasn't used
          valid_tools = ADK::ToolRegistry.list_tools.map { |t| t[:name].to_s }
          needs_update = false

          # Add tools
          Array(options[:add_tool]).each do |tool_to_add|
            tool_name = tool_to_add.strip
            if valid_tools.include?(tool_name)
              unless final_tools.include?(tool_name)
                final_tools << tool_name
                say "Adding tool: #{tool_name}", :cyan
                needs_update = true
              else
                say "Tool '#{tool_name}' already present, skipping add.", :yellow
              end
            else
              say "Warning: Unknown tool '#{tool_name}' specified for --add-tool, ignoring.", :yellow
            end
          end

          # Remove tools
          Array(options[:remove_tool]).each do |tool_to_remove|
            tool_name = tool_to_remove.strip
            if final_tools.include?(tool_name)
              final_tools.delete(tool_name)
              say "Removing tool: #{tool_name}", :cyan
              needs_update = true
            else
              say "Warning: Tool '#{tool_name}' not found for removal.", :yellow
            end
          end

          # Set tools update only if additions/removals happened
          updates['tools'] = final_tools.to_json if needs_update
        end

        # Check if any updates were actually requested
        if updates.empty?
          say "No updates specified.", :yellow
          exit(0)
        end

        # Apply updates
        begin
          redis.hset(key, updates) # HSET can take a hash for multiple updates
          say "Agent definition '#{name}' updated successfully.", :green
        rescue Redis::BaseError => e
          say "Error: Failed to update agent definition in Redis: #{e.message}", :red
          exit(1)
        end
      end
      # --- End Update Command ---

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

      # --- Runtime/Execution Commands (Using Redis Definition) ---

      desc 'start NAME', 'Verify agent definition loading and start (Ephemeral)'
      long_desc <<-LONGDESC
        Loads the agent definition (name, description, tools) from Redis,
        instantiates the agent object, adds its configured tools, and calls start().
        This command verifies that the agent can be loaded correctly based on its persisted definition.
        NOTE: This command does NOT start a persistent background process.
      LONGDESC
      def start(name)
        say "Attempting to load and start agent '#{name}' based on Redis definition..."
        redis = connect_redis
        key = agent_redis_key(name)

        redis_agent_data = redis.hmget(key, 'description', 'tools')
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]

        unless description
          say "Error: Agent definition '#{name}' not found in Redis.", :red; exit(1)
        end

        begin
          agent = ADK::Agent.new(name: name, description: description)

          tool_names_to_load = parse_tools(tools_json_string).map(&:to_sym)
          added_tools_names = []
          if tool_names_to_load.empty?
            say "  - No tools configured for this agent.", :yellow
          else
            say "  - Adding configured tools: #{tool_names_to_load.join(', ')}", :cyan
            tool_names_to_load.each do |tool_name|
              tool_instance = ADK::ToolRegistry.create_instance(tool_name)
              if tool_instance then agent.add_tool(tool_instance); added_tools_names << tool_name
              else say "  - Warning: Configured tool '#{tool_name}' not found in registry.", :yellow; end
            end
          end

          agent.start
          say "Agent '#{name}' (with tools: [#{added_tools_names.join(', ')}]) loaded and started successfully (instance finished).",
              :green
        rescue StandardError => e
          say "Error during agent instantiation or start: #{e.class} - #{e.message}", :red; exit(1)
        end
      end

      # --- 'stop' command removed ---

      desc 'execute NAME TASK', 'Execute a task using the agent definition from Redis'
      long_desc <<-LONGDESC
        Loads the agent definition (name, description, tools) from Redis,
        instantiates the agent, adds its configured tools, starts it, runs the specified TASK,
        prints the result, stops the agent, and exits.
      LONGDESC
      def execute(name, task)
        say "Loading agent '#{name}' to execute task: \"#{task}\"..."
        redis = connect_redis
        key = agent_redis_key(name)

        redis_agent_data = redis.hmget(key, 'description', 'tools')
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]

        unless description
          say "Error: Agent definition '#{name}' not found in Redis.", :red; exit(1)
        end

        begin
          agent = ADK::Agent.new(name: name, description: description)

          tool_names_to_load = parse_tools(tools_json_string).map(&:to_sym)
          if tool_names_to_load.empty?
            say "  - Warning: Agent has no tools configured.", :yellow
          else
            say "  - Adding configured tools: [#{tool_names_to_load.join(', ')}]", :cyan
            tool_names_to_load.each do |tool_name|
              tool_instance = ADK::ToolRegistry.create_instance(tool_name)
              agent.add_tool(tool_instance) if tool_instance
            end
          end

          say "  - Starting agent #{agent.name}...", :cyan, false; agent.start; say "started.", :cyan
          say "  - Running task...", :cyan, false; result = agent.run_task(task); say "finished.", :cyan
          say "  - Stopping agent...", :cyan, false; agent.stop; say "stopped.", :cyan

          say "\nTask Result:", :green
          say result, :green
        rescue StandardError => e
          say "Error during agent execution: #{e.class} - #{e.message}", :red
          agent&.stop rescue nil; say "Agent #{agent.name} stopped!", :cyan if defined?(agent) && agent
          exit(1)
        end
      end
      # --- End Runtime/Execution Commands ---
    end # End AgentCommands class
  end # End CLI module
end # End ADK module
