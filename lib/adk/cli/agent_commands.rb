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

        # --- NEW: Helper method to format CLI output ---
        def format_cli_result(result_data)
          if result_data.is_a?(Array)
            say "Multi-Step Result:", :cyan
            any_errors = false
            result_data.each_with_index do |step_hash, index|
              if step_hash.is_a?(Hash) && step_hash.key?(:status)
                if step_hash[:status] == :success
                  say "  Step #{index + 1} (Success):", :green
                  say "    Result: #{step_hash[:result]}"
                else # :error or other
                  say "  Step #{index + 1} (Error):", :red
                  say "    Message: #{step_hash[:error_message]}"
                  any_errors = true
                end
              else
                say "  Step #{index + 1} (Unknown Format): #{step_hash.inspect}", :yellow
                any_errors = true
              end
            end
            say "Overall Plan Status: #{any_errors ? 'Completed with errors' : 'Completed successfully'}",
                (any_errors ? :yellow : :green)

          elsif result_data.is_a?(Hash) && result_data.key?(:status)
            if result_data[:status] == :success
              say "Success:", :green
              say "  Result: #{result_data[:result]}"
            else # :error or other
              say "Error:", :red
              say "  Message: #{result_data[:error_message]}"
            end
          else
            say "Unknown Result Format:", :yellow
            say "  Data: #{result_data.inspect}"
          end
        end
        # --- End helper method ---
      end
      # --- End Redis Configuration ---

      # --- Definition Management Commands ---
      desc 'list', 'List all defined agents from Redis'
      def list
        # ... (connect redis, get names) ...
        say "Defined Agents:", :bold
        agents_data = redis.pipelined do |pipe|
          agent_names.each do |name|
            # --- Fetch model along with other fields ---
            pipe.hmget(agent_redis_key(name), 'description', 'tools', 'model')
          end
        end

        agent_names.zip(agents_data).each do |name, data|
          description = data[0] || "[No description]"
          tools = parse_tools(data[1])
          # --- Get model, apply default if missing ---
          model = data[2] || "#{ADK::Agent::DEFAULT_MODEL} (Default)"
          tools_str = tools.empty? ? "None" : tools.join(', ')
          # --- Display model ---
          say "- #{name}: #{description} (Model: #{model}, Tools: #{tools_str})"
        end
      end

      desc 'create NAME', 'Create a new agent definition in Redis'
      method_option :description, type: :string, required: true, desc: 'Agent description'
      method_option :tools, type: :string, aliases: "-t",
                            desc: 'Comma-separated list of tool names (e.g., "echo,calculator")'
      # --- Add model option ---
      method_option :model, type: :string, desc: "LLM model name (default: #{ADK::Agent::DEFAULT_MODEL})"
      def create(name)
        # ... (connect redis, check exists) ...
        description = options[:description]
        # --- Get model option or use default ---
        model_to_save = options[:model] && !options[:model].empty? ? options[:model] : ADK::Agent::DEFAULT_MODEL
        # ... (process tools option - no change needed) ...
        selected_tools = []
        valid_tools = ADK::ToolRegistry.list_tools.map { |t| t[:name].to_s }
        if options[:tools]
          requested_tools = options[:tools].split(',').map(&:strip).reject(&:empty?)
          requested_tools.each do |tool_name|
            if valid_tools.include?(tool_name)
              selected_tools << tool_name unless selected_tools.include?(tool_name)
            else say "Warning: Unknown tool '#{tool_name}', ignoring.", :yellow; end
          end
        end
        tools_json = selected_tools.to_json

        begin
          results = redis.multi do |multi|
            multi.hset(key, 'description', description)
            multi.hset(key, 'tools', tools_json)
            # --- Save model to Redis ---
            multi.hset(key, 'model', model_to_save)
            multi.sadd(REDIS_AGENTS_SET_KEY, name)
          end
          # Check results more thoroughly (now expecting 4 results)
          if results.is_a?(Array) && results.length == 4 && results.all? { |r|
            r.is_a?(Integer) || r == true || r.is_a?(String)
          } && results[3] == 1 # SADDS returns 1 on new add
            tools_msg = selected_tools.empty? ? "None" : selected_tools.join(', ')
            say "Agent definition '#{name}' created (Model: #{model_to_save}, Tools: #{tools_msg}).", :green
          else
            say "Warning: Agent definition command executed, but Redis reported unexpected results: #{results.inspect}. Please verify.",
                :yellow
          end
          # ... (rescue) ...
        end
      end

      # --- Add Update Command ---
      desc 'update NAME', 'Update an existing agent definition in Redis'
      method_option :description, type: :string, desc: "New description for the agent"
      method_option :tools, type: :string, aliases: "-t", desc: 'REPLACE existing tools with this list'
      method_option :add_tool, type: :string, repeatable: true, desc: 'Add a specific tool'
      method_option :remove_tool, type: :string, repeatable: true, desc: 'Remove a specific tool'
      # --- Add model option ---
      method_option :model, type: :string, desc: "New LLM model name for the agent"
      def update(name)
        redis = connect_redis
        key = agent_redis_key(name)

        # Check if agent definition exists
        unless redis.exists?(key)
          say "Error: Agent definition '#{name}' not found.", :red
          exit(1)
        end

        # Fetch current data
        # current_description, current_tools_json = redis.hmget(key, 'description', 'tools')
        # current_tools = parse_tools(current_tools_json) # Array of string names

        # Prepare updates
        updates = {}

        # Fetch current data (don't strictly need it unless confirming changes)
        current_description, current_tools_json, current_model = redis.hmget(key, 'description', 'tools', 'model')

        updates = {}
        # --- Handle model update ---
        if options[:model]
          if options[:model].empty?
            say "Warning: Empty model provided, ignoring update.", :yellow
          else
            updates['model'] = options[:model]
            say "Updating model to: #{options[:model]}", :cyan
          end
        end
        # ... (handle description update - no change) ...
        if options[:description]
          updates['description'] = options[:description]
          say "Updating description.", :cyan
        end

        # ... (handle tool updates - no change) ...
        # Fetch current tools needed for add/remove logic if --tools isn't used
        if !options[:tools] && (options[:add_tool] || options[:remove_tool])
          _desc, current_tools_json = redis.hmget(key, 'description', 'tools')
          current_tools = parse_tools(current_tools_json)
          final_tools = current_tools.dup
        else
          final_tools = [] # Will be populated if --tools is used
        end

        # Handle --tools (replacement)
        if options[:tools]
          # ... (tool replacement logic) ...
          valid_tools = ADK::ToolRegistry.list_tools.map { |t| t[:name].to_s }
          requested_tools = options[:tools].split(',').map(&:strip).reject(&:empty?)
          new_tool_list = []
          requested_tools.each do |tool_name|
            if valid_tools.include?(tool_name)
              new_tool_list << tool_name unless new_tool_list.include?(tool_name)
            else say "Warning: Unknown tool '#{tool_name}' specified in --tools, ignoring.", :yellow; end
          end
          final_tools = new_tool_list # Replace the list
          say "Replacing tools with: [#{final_tools.join(', ')}].", :cyan
          updates['tools'] = final_tools.to_json

        # Handle --add-tool and --remove-tool only if --tools wasn't used
        elsif options[:add_tool] || options[:remove_tool]
          valid_tools = ADK::ToolRegistry.list_tools.map { |t| t[:name].to_s }
          needs_update = false
          # Add tools
          Array(options[:add_tool]).each do |tool_to_add|
            # ... (add logic) ...
            tool_name = tool_to_add.strip
            if valid_tools.include?(tool_name)
              unless final_tools.include?(tool_name) then final_tools << tool_name;
                                                          say "Adding tool: #{tool_name}", :cyan; needs_update = true;
              else say "Tool '#{tool_name}' already present.", :yellow; end
            else say "Warning: Unknown tool '#{tool_name}' for --add-tool.", :yellow; end
          end
          # Remove tools
          Array(options[:remove_tool]).each do |tool_to_remove|
            # ... (remove logic) ...
            tool_name = tool_to_remove.strip
            if final_tools.include?(tool_name) then final_tools.delete(tool_name);
                                                    say "Removing tool: #{tool_name}", :cyan; needs_update = true;
            else say "Warning: Tool '#{tool_name}' not found for removal.", :yellow; end
          end
          updates['tools'] = final_tools.to_json if needs_update
        end

        # ... (check if updates empty) ...
        if updates.empty? then say "No updates specified.", :yellow; exit(0); end

        # Apply updates
        begin
          redis.hmset(key, updates.flatten) # Use hmset or hset(key, updates) in newer Redis versions
          say "Agent definition '#{name}' updated successfully.", :green
          # ... (rescue) ...
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

        # --- Fetch model ---
        redis_agent_data = redis.hmget(key, 'description', 'tools', 'model')
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]
        # --- Get model, apply default if missing ---
        model_name = redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL

        unless description
          say "Error: Agent definition '#{name}' not found in Redis.", :red; exit(1)
        end

        begin
          # --- Pass model_name to Agent constructor ---
          agent = ADK::Agent.new(name: name, description: description, model_name: model_name)
          # ... (tool loading logic - no change) ...
          tool_names_to_load = parse_tools(tools_json_string).map(&:to_sym)
          added_tools_names = []
          if tool_names_to_load.empty?
            say "  - No tools configured.", :yellow
          else
            say "  - Adding configured tools: #{tool_names_to_load.join(', ')}", :cyan
            tool_names_to_load.each do |tool_name|
              tool_instance = ADK::ToolRegistry.create_instance(tool_name)
              if tool_instance then agent.add_tool(tool_instance); added_tools_names << tool_name;
              else say "  - Warn: Tool '#{tool_name}' not found.", :yellow; end
            end
          end

          agent.start
          # --- Include model in success message ---
          say "Agent '#{name}' (Model: #{agent.model_name}, Tools: [#{added_tools_names.join(', ')}]) loaded and started successfully (instance finished).",
              :green
          # ... (rescue) ...
        end
      end

      # --- 'stop' command removed ---

      # --- 'execute' command ---
      desc 'execute NAME TASK', 'Execute a task using the agent definition from Redis'
      # ... (long desc) ...
      def execute(name, task)
        say "Loading agent '#{name}' to execute task: \"#{task}\"..."
        redis = connect_redis
        key = agent_redis_key(name)

        # --- Fetch model ---
        redis_agent_data = redis.hmget(key, 'description', 'tools', 'model')
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]
        # --- Get model, apply default if missing ---
        model_name = redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL

        unless description
          say "Error: Agent definition '#{name}' not found in Redis.", :red; exit(1)
        end

        agent = nil
        begin
          # --- Pass model_name to Agent constructor ---
          agent = ADK::Agent.new(name: name, description: description, model_name: model_name)
          # --- Include model in loading message ---
          say "  - Agent uses model: #{agent.model_name}", :cyan

          # ... (tool loading logic - no change) ...
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

          # ... (Execute and get result - no change) ...
          say "  - Starting agent #{agent.name}...", :cyan, false; agent.start; say "started.", :cyan
          say "  - Running task...", :cyan, false;
          result_data = agent.run_task(task);
          say "finished.", :cyan

          # --- Format and Print Result (Uses existing helper - no change needed here) ---
          say "\nTask Result:", :bold
          format_cli_result(result_data)

        # ... (rescue / ensure block - no change needed) ...
        rescue StandardError => e
          say "\nError during agent execution: #{e.class} - #{e.message}", :red
        ensure
          if agent&.running?
            say "  - Stopping agent...", :cyan, false; agent.stop; say "stopped.", :cyan
          end
          exit(1) if e
        end
      end
      # --- End 'execute' command ---
      # --- End Runtime/Execution Commands ---
    end # End AgentCommands class
  end # End CLI module
end # End ADK module
