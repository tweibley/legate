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
require_relative '../agent_definition_store' # Added require

module ADK
  module CLI
    # CLI commands for agent definition management AND temporary execution
    class AgentCommands < Thor
      # --- Session Service Instance ---
      # For the CLI, InMemorySessionService is suitable as state is lost anyway on exit.
      # A shared instance allows reusing session ID across multiple execute calls if needed.
      @@session_service = ADK::SessionService::InMemory.new

      no_commands do
        # REMOVED: agent_redis_key helper

        # REMOVED: connect_redis helper (assume AgentDefinitionStore handles connections)

        # REMOVED: parse_tools helper (AgentDefinitionStore handles tool format)

        # --- Updated format_cli_result to handle Event/Error/Pending Hash ---
        def format_cli_result(result_data)
          content_to_display = nil
          is_error = false
          is_pending = false
          status_prefix = ""

          # Determine what kind of result we got
          if result_data.is_a?(ADK::Event)
            if result_data.role == :agent || result_data.role == :tool_result
              content_to_display = result_data.content
              if content_to_display.is_a?(Hash) && content_to_display.key?(:status)
                is_error = (content_to_display[:status] == :error)
                is_pending = (content_to_display[:status] == :pending)
                status_prefix = "(Nested Result) " if result_data.role == :agent
              end
            end
          elsif result_data.is_a?(Hash) && result_data.key?(:status)
            content_to_display = result_data
            is_error = (result_data[:status] == :error)
            is_pending = (result_data[:status] == :pending)
          else
            content_to_display = result_data
            is_error = false
            is_pending = false
          end

          # Now format based on the determined content and status
          if content_to_display.is_a?(Array) && !is_error && !is_pending # Multi-Step Plan Result
            say "#{status_prefix}Multi-Step Result:", :cyan
            any_step_errors = false
            any_step_pending = false
            content_to_display.each_with_index do |step_hash, index|
              if step_hash.is_a?(Hash) # Ensure it's a hash before checking status
                case step_hash[:status]
                when :success
                  say "  Step #{index + 1} (Success):", :green
                  step_result = step_hash[:result]
                  if step_result.is_a?(Hash) && step_result.key?(:status)
                    say "    Result (Nested): #{step_result.inspect}"
                  else
                    say "    Result: #{step_result}"
                  end
                when :pending
                  say "  Step #{index + 1} (Pending):", :yellow
                  say "    Job ID: #{step_hash[:job_id]}"
                  say "    Message: #{step_hash[:message]}" if step_hash[:message]
                  any_step_pending = true
                when :error
                  say "  Step #{index + 1} (Error):", :red
                  say "    Message: #{step_hash[:error_message]}"
                  any_step_errors = true
                else
                  say "  Step #{index + 1} (Unknown Status): #{step_hash.inspect}", :yellow
                  any_step_errors = true
                end
              else
                say "  Step #{index + 1} (Unknown Step Format): #{step_hash.inspect}", :yellow
                any_step_errors = true
              end
            end
            # --- UPDATED Overall Status ---
            overall_msg = if any_step_errors then 'Completed with errors'
                          elsif any_step_pending then 'Completed with pending steps'
                          else 'Completed successfully' end
            overall_color = if any_step_errors then :red
                            elsif any_step_pending then :yellow
                            else :green end
            say "Overall Plan Status: #{overall_msg}", overall_color

          elsif content_to_display.is_a?(Hash) && content_to_display.key?(:status)
            # Single step result or error/pending
            case content_to_display[:status]
            when :success
              say "#{status_prefix}Success:", :green
              say "  Result: #{content_to_display[:result]}"
            when :pending
              say "#{status_prefix}Pending:", :yellow
              say "  Job ID: #{content_to_display[:job_id]}"
              say "  Message: #{content_to_display[:message]}" if content_to_display[:message]
            when :error
              say "#{status_prefix}Error:", :red
              say "  Message: #{content_to_display[:error_message]}"
            else
              say "#{status_prefix}Unknown Status:", :yellow
              say "  Data: #{content_to_display.inspect}"
            end
          else
            # Simple response (like a string) - Treat as success
            say "#{status_prefix}Success:", :green
            say "  Result: #{content_to_display}"
          end
        end
        # --- End format_cli_result ---
      end # end no_commands

      # --- Definition Management Commands ---
      desc 'list', 'List all defined agents'
      def list
        # Load from Redis into memory first
        begin
          ADK::AgentDefinitionStore.load_all_from_redis
        rescue Redis::BaseError => e
          say "Error: Could not connect to Redis to load agent definitions. Is it running? (#{e.message})", :red
          exit(1)
        end

        definitions = ADK::AgentDefinitionStore.all

        if definitions.empty?
          say "No agent definitions found."
          return
        end

        say "Defined Agents:", :bold
        definitions.sort_by { |name, _| name.to_s }.each do |name, data|
          description = data[:description] || "[No description]"
          tools = data[:tools] # Already an array from store
          model = data[:model] || "#{ADK::Agent::DEFAULT_MODEL} (Default)"
          tools_str = tools.empty? ? "None" : tools.join(', ')
          say "- #{name}: #{description} (Model: #{model}, Tools: #{tools_str})"
        end
      end

      desc 'save NAME', 'Create or update an agent definition'
      method_option :description, type: :string, required: true, desc: 'Agent description'
      method_option :tools, type: :string, aliases: "-t",
                            desc: 'Comma-separated list of tool names (e.g., "echo,calculator")'
      method_option :model, type: :string, desc: "LLM model name (default: #{ADK::Agent::DEFAULT_MODEL})"
      def save(name)
        name_sym = name.to_sym
        description = options[:description]
        model_to_save = options[:model] && !options[:model].empty? ? options[:model] : ADK::Agent::DEFAULT_MODEL

        selected_tools = []
        valid_tools = ADK::GlobalToolManager.registered_tool_names.map(&:to_s)
        if options[:tools]
          requested_tools = options[:tools].split(',').map(&:strip).reject(&:empty?)
          requested_tools.each do |tool_name|
            if valid_tools.include?(tool_name)
              selected_tools << tool_name unless selected_tools.include?(tool_name)
            else
              # Check if it's a valid tool name even if not globally registered (could be agent-specific)
              # For simplicity, we'll only check against globally known tools here.
              # A more robust check might involve loading agent definitions.
              say "Warning: Unknown globally registered tool '#{tool_name}', ignoring.", :yellow
            end
          end
        end

        definition = {
          description: description,
          tools: selected_tools,
          model: model_to_save
        }

        # Save to Redis first (for persistence)
        unless ADK::AgentDefinitionStore.save_to_redis(name_sym, definition)
          say "Error saving definition to Redis. Aborting.", :red
          exit(1)
        end

        # Register in memory for current process
        ADK::AgentDefinitionStore.register(name_sym, definition)

        tools_msg = selected_tools.empty? ? "None" : selected_tools.join(', ')
        say "Agent definition '#{name}' saved (Model: #{model_to_save}, Tools: #{tools_msg}).", :green
      end

      desc 'delete NAME', "Delete an agent's definition"
      def delete(name)
        name_sym = name.to_sym
        # Check if it exists in memory first (might have been loaded)
        unless ADK::AgentDefinitionStore.find(name_sym)
          # If not in memory, check Redis before prompting
          begin
            definition_from_redis = ADK::AgentDefinitionStore.load_from_redis(name_sym)
            unless definition_from_redis
              say "Error: Agent definition '#{name}' not found.", :red
              exit(1)
            end
          rescue Redis::BaseError => e
            say "Error: Could not connect to Redis to check agent definition. #{e.message}", :red
            exit(1)
          end
        end

        if yes?("Are you sure you want to permanently delete agent definition '#{name}'? [y/N]", :yellow)
          # Delete from Redis
          redis_deleted = ADK::AgentDefinitionStore.delete_from_redis(name_sym)
          # Remove from memory
          ADK::AgentDefinitionStore.remove(name_sym)

          if redis_deleted
            say "Agent definition '#{name}' deleted successfully.", :green
          else
            say "Error deleting definition from Redis. It has been removed from memory, but may still exist in Redis.",
                :red
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
        name_sym = name.to_sym
        say "Loading agent '#{name}'..."

        # Load definition using the store
        definition = ADK::AgentDefinitionStore.find(name_sym)
        definition ||= ADK::AgentDefinitionStore.load_from_redis(name_sym)

        unless definition
          say "Error: Agent definition '#{name}' not found.", :red
          exit(1)
        end

        description = definition[:description]
        tool_names_to_load = definition[:tools].map(&:to_sym)
        model_name = definition[:model]

        agent = nil
        begin
          # Instantiate Agent (pass tool classes directly)
          tool_classes = tool_names_to_load.map do |t_name|
            ADK::GlobalToolManager.find_class(t_name)
          end.compact
          missing_tools = tool_names_to_load - tool_classes.map { |tc| tc.tool_metadata[:name] }

          agent = ADK::Agent.new(
            name: name,
            description: description,
            model_name: model_name,
            tool_classes: tool_classes
          )
          say "  - Agent uses model: #{agent.model_name}", :cyan

          unless missing_tools.empty?
            say "  - Warning: Tools defined but not found in GlobalToolManager: [#{missing_tools.join(', ')}]", :yellow
          end
          say "  - Loaded tools: [#{agent.tools.map(&:name).join(', ')}]", :cyan

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
          if agent&.running?
            say "  - Stopping agent runtime...", :cyan, false
            agent.stop
            say "stopped.", :cyan
          end
        end
      end

      # --- Updated 'execute' command for Session Handling and Pending Status ---
      desc 'execute NAME TASK', 'Execute a task using agent definition (ephemeral)'
      long_desc <<-LONGDESC
        Loads agent definition, instantiates agent, runs TASK within a session context,
        prints the result, stops agent runtime & exits.

        Use --session-id to continue an existing conversation,
        otherwise starts a new session for this execution. The session ID used will be printed.

        Use --redis to use Redis for session storage instead of in-memory storage.
        This allows sessions to persist between CLI invocations.

        If a task results in a :pending status (e.g., for an async job),
        the job_id will be printed. Use the check_job_status tool
        in a subsequent call to get the final result.
      LONGDESC
      method_option :session_id, type: :string, desc: 'Optional ID of an existing session to use.'
      method_option :redis, type: :boolean, default: false, desc: 'Use Redis for session storage instead of in-memory.'
      def execute(name, task)
        name_sym = name.to_sym
        say("Loading agent '#{name}' to execute task: \"#{task}\"...")

        # Load definition using the store
        definition = ADK::AgentDefinitionStore.find(name_sym)
        definition ||= ADK::AgentDefinitionStore.load_from_redis(name_sym)

        unless definition
          say "Error: Agent definition '#{name}' not found.", :red
          exit(1)
        end

        description = definition[:description]
        tool_names_to_load = definition[:tools].map(&:to_sym)
        model_name = definition[:model]

        # --- Session Handling ---
        session_service = options[:redis] ? ADK::SessionService::Redis.new : @@session_service
        session_id = options[:session_id]
        adk_session = nil
        if session_id
          adk_session = session_service.get_session(session_id: session_id)
          if adk_session then say "Continuing session: #{session_id}", :cyan
          else say "Warning: Session ID '#{session_id}' provided but not found. Starting a new session.", :yellow;
               session_id = nil end
        end
        unless adk_session
          adk_session = session_service.create_session(app_name: name, user_id: 'cli_user')
          session_id = adk_session.id
          say "Started new session: #{session_id}", :cyan
          say "  (Using #{options[:redis] ? 'Redis' : 'in-memory'} session storage)", :cyan
        end
        # --- End Session Handling ---

        agent = nil
        e = nil
        begin
          # Instantiate Agent (pass tool classes directly)
          tool_classes = tool_names_to_load.map do |t_name|
            ADK::GlobalToolManager.find_class(t_name)
          end.compact
          missing_tools = tool_names_to_load - tool_classes.map { |tc| tc.tool_metadata[:name] }

          agent = ADK::Agent.new(
            name: name,
            description: description,
            model_name: model_name,
            tool_classes: tool_classes
          )
          say "  - Agent uses model: #{agent.model_name}", :cyan

          unless missing_tools.empty?
            say "  - Warning: Tools defined but not found in GlobalToolManager: [#{missing_tools.join(', ')}]", :yellow
          end
          say "  - Loaded tools: [#{agent.tools.map(&:name).join(', ')}]", :cyan

          # Start Agent Runtime & Execute Task
          say "  - Starting agent runtime...", :cyan, false; agent.start; say "started.", :cyan
          say "  - Running task in session #{session_id}: '#{task}'...", :cyan, false;
          final_event_or_error = agent.run_task(
            session_id: session_id,
            user_input: task,
            session_service: session_service
          )
          say "finished.", :cyan

          # Format and Print Result
          say "\nTask Result:", :bold
          format_cli_result(final_event_or_error)
        rescue StandardError => e
          say "\nError during agent execution: #{e.class} - #{e.message}", :red
          puts e.backtrace.first(5).join("\n")
        ensure
          if agent&.running?
            say "  - Stopping agent runtime...", :cyan, false; agent.stop; say "stopped.", :cyan
          end
          exit(1) if e
        end
      end # End 'execute' command
    end # End AgentCommands class
  end # End CLI module
end # End ADK module
