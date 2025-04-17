# File: lib/adk/cli/agent_commands.rb
# frozen_string_literal: true

require 'thor'
require 'redis'
require 'json'
require_relative '../tool_registry'
require_relative '../agent'
require_relative '../event'   # Need Event for result formatting understanding
require_relative '../session' # Need Session for session service context
require_relative '../session_service/in_memory' # Need Service implementation
require_relative '../session_service/redis' # Add Redis session service

module ADK
  module CLI
    # CLI commands for agent definition management AND temporary execution
    class AgentCommands < Thor
      # Redis Keys Constants
      REDIS_AGENT_HASH_PREFIX = "adk:agent:"
      REDIS_AGENTS_SET_KEY = "adk:agents:all_names"

      # --- Session Service Instance ---
      # For the CLI, InMemorySessionService is suitable as state is lost anyway on exit.
      # A shared instance allows reusing session ID across multiple execute calls if needed.
      @@session_service = ADK::SessionService::InMemory.new

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

        # --- Updated format_cli_result to handle Event/Error Hash ---
        def format_cli_result(result_data)
          content_to_display = nil
          is_error = false
          status_prefix = ""

          # Determine what kind of result we got from run_task
          if result_data.is_a?(ADK::Event)
            if result_data.role == :agent
              # Standard successful execution returning the final agent event
              content_to_display = result_data.content
              # Check if the *content* itself is a status hash (e.g., from AgentTool success)
              if content_to_display.is_a?(Hash) && content_to_display.key?(:status)
                is_error = (content_to_display[:status] == :error)
                status_prefix = "(Nested Result) " # Indicate the origin
              end
            elsif result_data.role == :tool_result
              # Tool result event
              content_to_display = result_data.content
              if content_to_display.is_a?(Hash) && content_to_display.key?(:status)
                is_error = (content_to_display[:status] == :error)
              end
            end
          elsif result_data.is_a?(Hash) && result_data.key?(:status)
            # An error occurred directly during run_task (e.g., agent not running, planning error)
            content_to_display = result_data
            is_error = true # Assume error if it's a status hash from run_task itself
          else
            # Handle simple responses (like strings) as successful results
            content_to_display = result_data
            is_error = false
          end

          # Now format based on the determined content and error status
          if content_to_display.is_a?(Array) && !is_error # Likely Multi-Step Plan Result
            say "#{status_prefix}Multi-Step Result:", :cyan
            any_step_errors = false
            content_to_display.each_with_index do |step_hash, index|
              if step_hash.is_a?(Hash) && step_hash.key?(:status)
                if step_hash[:status] == :success
                  say "  Step #{index + 1} (Success):", :green
                  # Handle potential nested results from AgentTool
                  step_result = step_hash[:result]
                  if step_result.is_a?(Hash) && step_result.key?(:status)
                    say "    Result (Nested): #{step_result.inspect}"
                  else
                    say "    Result: #{step_result}"
                  end
                else # :error or other
                  say "  Step #{index + 1} (Error):", :red
                  say "    Message: #{step_hash[:error_message]}"
                  any_step_errors = true
                end
              else
                say "  Step #{index + 1} (Unknown Step Format): #{step_hash.inspect}", :yellow
                any_step_errors = true
              end
            end
            say "Overall Plan Status: #{any_step_errors ? 'Completed with errors' : 'Completed successfully'}",
                (any_step_errors ? :yellow : :green)

          elsif content_to_display.is_a?(Hash) && content_to_display.key?(:status)
            # Single step or error
            if content_to_display[:status] == :success
              say "#{status_prefix}Success:", :green
              say "  Result: #{content_to_display[:result]}"
            else
              say "#{status_prefix}Error:", :red
              say "  Message: #{content_to_display[:error_message]}"
            end
          else
            # Simple response (like a string)
            say "#{status_prefix}Success:", :green
            say "  Result: #{content_to_display}"
          end
        end
        # --- End format_cli_result ---
      end # end no_commands

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
            pipe.hmget(agent_redis_key(name), 'description', 'tools', 'model')
          end
        end

        agent_names.zip(agents_data).each do |name, data|
          description = data[0] || "[No description]"
          tools = parse_tools(data[1])
          model = data[2] || "#{ADK::Agent::DEFAULT_MODEL} (Default)"
          tools_str = tools.empty? ? "None" : tools.join(', ')
          say "- #{name}: #{description} (Model: #{model}, Tools: #{tools_str})"
        end
      end

      desc 'create NAME', 'Create a new agent definition in Redis'
      method_option :description, type: :string, required: true, desc: 'Agent description'
      method_option :tools, type: :string, aliases: "-t",
                            desc: 'Comma-separated list of tool names (e.g., "echo,calculator")'
      method_option :model, type: :string, desc: "LLM model name (default: #{ADK::Agent::DEFAULT_MODEL})"
      def create(name)
        redis = connect_redis
        key = agent_redis_key(name)

        if redis.sismember(REDIS_AGENTS_SET_KEY, name)
          say "Error: Agent definition '#{name}' already exists.", :red
          exit(1)
        end

        description = options[:description]
        model_to_save = options[:model] && !options[:model].empty? ? options[:model] : ADK::Agent::DEFAULT_MODEL

        selected_tools = []
        valid_tools = ADK::ToolRegistry.list_tools.map { |t| t[:name].to_s }
        if options[:tools]
          requested_tools = options[:tools].split(',').map(&:strip).reject(&:empty?)
          requested_tools.each do |tool_name|
            if valid_tools.include?(tool_name)
              selected_tools << tool_name unless selected_tools.include?(tool_name)
            else
              say "Warning: Unknown tool '#{tool_name}', ignoring.", :yellow
            end
          end
        end
        tools_json = selected_tools.to_json

        begin
          results = redis.multi do |multi|
            multi.hset(key, 'description', description)
            multi.hset(key, 'tools', tools_json)
            multi.hset(key, 'model', model_to_save)
            multi.sadd(REDIS_AGENTS_SET_KEY, name)
          end

          if results.is_a?(Array) && results.all? { |r| r.is_a?(Integer) || r == true || r.is_a?(String) }
            tools_msg = selected_tools.empty? ? "None" : selected_tools.join(', ')
            say "Agent definition '#{name}' created (Model: #{model_to_save}, Tools: #{tools_msg}).", :green
          else
            say "Warning: Agent definition command executed, but Redis reported unexpected results: #{results.inspect}. Please verify.",
                :yellow
          end
        rescue Redis::BaseError => e
          say "Error: Failed to save agent definition to Redis: #{e.message}", :red
          exit(1)
        end
      end

      desc 'update NAME', 'Update an existing agent definition in Redis'
      method_option :description, type: :string, desc: "New description for the agent"
      method_option :tools, type: :string, aliases: "-t", desc: 'REPLACE existing tools with this list'
      method_option :add_tool, type: :string, repeatable: true, desc: 'Add a specific tool'
      method_option :remove_tool, type: :string, repeatable: true, desc: 'Remove a specific tool'
      method_option :model, type: :string, desc: "New LLM model name for the agent"
      def update(name)
        redis = connect_redis
        key = agent_redis_key(name)

        unless redis.exists?(key)
          say "Error: Agent definition '#{name}' not found.", :red
          exit(1)
        end

        # Fetch current data
        current_data = redis.hmget(key, 'description', 'tools', 'model')
        current_description = current_data[0]
        current_tools = parse_tools(current_data[1]) # Array of string names
        current_model = current_data[2] || ADK::Agent::DEFAULT_MODEL

        # Prepare updates
        updates = {}
        final_tools = current_tools.dup # Start with current tools

        # Update description if provided
        if options[:description]
          updates['description'] = options[:description]
        end

        # Update model if provided
        if options[:model]
          updates['model'] = options[:model]
        end

        # Handle tool changes
        valid_tools = ADK::ToolRegistry.list_tools.map { |t| t[:name].to_s }

        # REPLACE all tools (highest priority)
        if options[:tools]
          # Reset tools completely
          final_tools = []
          requested_tools = options[:tools].split(',').map(&:strip).reject(&:empty?)
          requested_tools.each do |tool_name|
            if valid_tools.include?(tool_name)
              final_tools << tool_name unless final_tools.include?(tool_name)
            else
              say "Warning: Unknown tool '#{tool_name}' in --tools, ignoring.", :yellow
            end
          end
        else
          # Process individual adds/removes

          # Process add_tool options (can be repeated)
          if options[:add_tool]
            Array(options[:add_tool]).each do |tool_name|
              tool_name = tool_name.strip
              if valid_tools.include?(tool_name)
                final_tools << tool_name unless final_tools.include?(tool_name)
                say "Adding tool: #{tool_name}", :cyan
              else
                say "Warning: Unknown tool '#{tool_name}' in --add-tool, ignoring.", :yellow
              end
            end
          end

          # Process remove_tool options (can be repeated)
          if options[:remove_tool]
            Array(options[:remove_tool]).each do |tool_name|
              tool_name = tool_name.strip
              if final_tools.include?(tool_name)
                final_tools.delete(tool_name)
                say "Removing tool: #{tool_name}", :cyan
              else
                say "Warning: Tool '#{tool_name}' not found in agent tools, can't remove.", :yellow
              end
            end
          end
        end

        # Always update tools if we modified them
        if final_tools != current_tools
          updates['tools'] = final_tools.to_json
        end

        if updates.empty?
          say "No updates specified. Agent definition unchanged.", :yellow
          return
        end

        begin
          redis.multi do |multi|
            updates.each do |field, value|
              multi.hset(key, field, value)
            end
          end

          # Summary of changes
          changes = []
          changes << "description: '#{options[:description]}'" if options[:description]
          changes << "model: '#{options[:model]}'" if options[:model]

          if final_tools != current_tools
            curr_tools_str = current_tools.empty? ? "None" : current_tools.join(', ')
            final_tools_str = final_tools.empty? ? "None" : final_tools.join(', ')
            changes << "tools: [#{curr_tools_str}] => [#{final_tools_str}]"
          end

          say "Agent definition '#{name}' updated successfully.", :green
          say "Changes: #{changes.join(', ')}", :green
        rescue Redis::BaseError => e
          say "Error: Failed to update agent definition in Redis: #{e.message}", :red
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
          say "Deletion cancelled.", :yellow
        end
      end

      # --- Runtime/Execution Commands (Using Redis Definition) ---

      desc 'start NAME', 'Verify agent definition loading and start (Ephemeral)'
      long_desc <<-LONGDESC
        Loads agent definition, instantiates agent, starts agent runtime state,
        verifies all components loaded correctly, prints details & exits.
        This is a diagnostic tool to verify agent definition loads properly.
        Use 'execute' command to run an actual task with the agent.
      LONGDESC
      def start(name)
        say "Loading agent '#{name}'..."
        redis = connect_redis
        key = agent_redis_key(name)
        redis_agent_data = redis.hmget(key, 'description', 'tools', 'model')
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]
        model_name = redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL

        unless description
          say "Error: Agent definition '#{name}' not found.", :red
          exit(1)
        end

        agent = nil
        begin
          # Instantiate Agent
          agent = ADK::Agent.new(name: name, description: description, model_name: model_name)
          say "  - Agent uses model: #{agent.model_name}", :cyan

          # Load Tools
          tool_names_to_load = parse_tools(tools_json_string).map(&:to_sym)
          added_tools = []
          if tool_names_to_load.empty?
            say "  - Warning: No tools configured.", :yellow
          else
            say "  - Adding tools: [#{tool_names_to_load.join(', ')}]", :cyan
            tool_names_to_load.each do |t|
              instance = ADK::ToolRegistry.create_instance(t)
              if instance
                agent.add_tool(instance)
                added_tools << t
              else
                say "  - Warning: Tool '#{t}' not found in registry", :yellow
              end
            end
          end

          # Start Agent Runtime
          say "  - Starting agent runtime...", :cyan, false
          agent.start
          say "started.", :cyan
          say "\nAgent '#{name}' is ready.", :green
        rescue StandardError => e
          say "\nError during agent setup: #{e.class} - #{e.message}", :red
          puts e.backtrace.first(5).join("\n") # Print some backtrace for debug
          exit(1)
        ensure
          # Stop agent runtime if we started it
          if agent&.running?
            say "  - Stopping agent runtime...", :cyan, false
            agent.stop
            say "stopped.", :cyan
          end
        end
      end

      # --- Updated 'execute' command for Session Handling ---
      desc 'execute NAME TASK', 'Execute a task using agent definition (ephemeral)'
      long_desc <<-LONGDESC
        Loads agent definition, instantiates agent, runs TASK within a session context,
        prints the result, stops agent runtime & exits.

        Use --session-id to continue an existing conversation,
        otherwise starts a new session for this execution. The session ID used will be printed.

        Use --redis to use Redis for session storage instead of in-memory storage.
        This allows sessions to persist between CLI invocations.
      LONGDESC
      method_option :session_id, type: :string, desc: 'Optional ID of an existing session to use.'
      method_option :redis, type: :boolean, default: false, desc: 'Use Redis for session storage instead of in-memory.'
      def execute(name, task)
        say "Loading agent '#{name}' to execute task: \"#{task}\"..."
        redis = connect_redis
        key = agent_redis_key(name)
        redis_agent_data = redis.hmget(key, 'description', 'tools', 'model')
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]
        model_name = redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL

        unless description then say "Error: Agent definition '#{name}' not found.", :red; exit(1); end

        # --- Session Handling ---
        # Choose session service based on --redis option
        session_service = options[:redis] ? ADK::SessionService::Redis.new : @@session_service
        session_id = options[:session_id]
        adk_session = nil

        if session_id
          adk_session = session_service.get_session(session_id: session_id)
          if adk_session
            say "Continuing session: #{session_id}", :cyan
          else
            say "Warning: Session ID '#{session_id}' provided but not found. Starting a new session.", :yellow
            session_id = nil # Force creation below
          end
        end

        unless adk_session
          # Use agent name for app_name, generic user_id for CLI
          adk_session = session_service.create_session(app_name: name, user_id: 'cli_user')
          session_id = adk_session.id
          say "Started new session: #{session_id}", :cyan
          if options[:redis]
            say "  (Using Redis for persistent storage)", :cyan
          end
        end
        # --- End Session Handling ---

        agent = nil
        e = nil # Define error variable for ensure block
        begin
          # Instantiate Agent
          agent = ADK::Agent.new(name: name, description: description, model_name: model_name)
          say "  - Agent uses model: #{agent.model_name}", :cyan

          # Load Tools
          tool_names_to_load = parse_tools(tools_json_string).map(&:to_sym); added_tools = [];
          if tool_names_to_load.empty? then say "  - Warning: No tools configured.", :yellow;
          else say "  - Adding tools: [#{tool_names_to_load.join(', ')}]", :cyan; tool_names_to_load.each { |t|
                 i = ADK::ToolRegistry.create_instance(t);
                 if i then agent.add_tool(i); added_tools << t; else say "  - Warn: Tool '#{t}' not found", :yellow; end
               }; end

          # Start Agent Runtime & Execute Task within Session
          say "  - Starting agent runtime...", :cyan, false; agent.start; say "started.", :cyan
          say "  - Running task in session #{session_id}...", :cyan, false;
          # Call refactored run_task
          final_event_or_error = agent.run_task(
            session_id: session_id,
            user_input: task,
            session_service: session_service
          );
          say "finished.", :cyan

          # Format and Print Result
          say "\nTask Result:", :bold
          format_cli_result(final_event_or_error) # Use helper method
        rescue StandardError => e # Catch errors during setup or run_task
          say "\nError during agent execution: #{e.class} - #{e.message}", :red
          puts e.backtrace.first(5).join("\n") # Print some backtrace for debug
        ensure
          # Stop the ephemeral agent runtime state
          if agent&.running?
            say "  - Stopping agent runtime...", :cyan, false; agent.stop; say "stopped.", :cyan
          end
          # Exit with error code if an exception was caught
          exit(1) if e
        end
      end # End 'execute' command
    end # End AgentCommands class
  end # End CLI module
end # End ADK module
