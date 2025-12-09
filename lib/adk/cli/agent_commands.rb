# File: lib/adk/cli/agent_commands.rb
# frozen_string_literal: true

require 'thor'
require 'redis'
require 'json'
require 'fileutils' # For creating directories
require 'cli/ui'    # Correct require
require_relative '../tool_registry'
require_relative '../agent'
require_relative '../event'
require_relative '../session'
require_relative '../session_service/in_memory'
require_relative '../session_service/redis'
require_relative '../agent_definition_store'
require_relative '../global_tool_manager'
require_relative '../../adk' # For ADK.config, ADK.logger

module ADK
  module CLI
    # CLI commands for agent definition management AND temporary execution
    class AgentCommands < Thor
      # Default session service can be overridden in tests or specific command options
      @@session_service = ADK::SessionService::InMemory.new

      # Keep existing @@session_service_for_execute for 'execute' command's default in-memory usage
      # This seems to be an older or differently purposed variable. Let's ensure it's distinct.
      # If it's truly redundant after initializing @@session_service, it might be removable later,
      # but for now, we will keep it to avoid breaking other logic that might rely on it.
      @@session_service_for_execute = ADK::SessionService::InMemory.new

      no_commands do
        # --- Existing format_cli_result (for 'execute' command) ---
        def format_cli_result(result_data)
          content_to_display = nil
          is_error = false
          is_pending = false
          status_prefix = ''

          if result_data.is_a?(ADK::Event)
            if %i[agent tool_result].include?(result_data.role)
              content_to_display = result_data.content
              if content_to_display.is_a?(Hash) && content_to_display.key?(:status)
                is_error = (content_to_display[:status] == :error)
                is_pending = (content_to_display[:status] == :pending)
                status_prefix = '(Nested Result) ' if result_data.role == :agent
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

          if content_to_display.is_a?(Array) && !is_error && !is_pending
            say "#{status_prefix}Multi-Step Result:", :cyan
            any_step_errors = false
            any_step_pending = false
            content_to_display.each_with_index do |step_hash, index|
              if step_hash.is_a?(Hash) && step_hash.key?(:status)
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
            overall_msg = if any_step_errors then 'Completed with errors'
                          elsif any_step_pending then 'Completed with pending steps'
                          else
                            'Completed successfully' end
            overall_color = if any_step_errors then :red
                            elsif any_step_pending then :yellow
                            else
                              :green end
            say "Overall Plan Status: #{overall_msg}", overall_color
          elsif content_to_display.is_a?(Hash) && content_to_display.key?(:status)
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
            say "#{status_prefix}Success:", :green
            say "  Result: #{content_to_display}"
          end
        end
        # --- End format_cli_result ---

        # Recursively extract the innermost :result value for nested :success hashes
        def deep_result_value(val)
          # Always normalize keys to symbols
          if val.is_a?(Hash)
            val = val.transform_keys(&:to_sym)
            # Prefer to recurse into :result if present
            if val.key?(:result)
              return deep_result_value(val[:result])
            elsif val.key?(:plan_details) && val[:plan_details].is_a?(Array) && !val[:plan_details].empty?
              return deep_result_value(val[:plan_details].last)
            end
          end
          val
        end

        # --- formatting helper for CLI UI Chat ---
        def _format_chat_turn_output_cli_ui(event_or_hash, role_override = nil, timestamp = nil)
          event_obj = event_or_hash.is_a?(ADK::Event) ? event_or_hash : nil
          data_to_format = event_obj ? event_obj.content : event_or_hash
          current_role = role_override || (event_obj ? event_obj.role : :agent)

          # Use provided timestamp or create one if not provided
          formatted_time = timestamp || Time.now.strftime('%H:%M:%S')

          # Normalize keys to symbols
          data_to_format = data_to_format.transform_keys(&:to_sym) if data_to_format.is_a?(Hash)

          if current_role == :user
            # Add extra line break for spacing and show timestamp
            ::CLI::UI.puts "\n{{blue:You}} {{gray:(#{formatted_time})}}:"
            ::CLI::UI.puts "  #{data_to_format}\n"
            return
          end

          if data_to_format.is_a?(Hash) && data_to_format.key?(:status) &&
             data_to_format[:status].to_s.downcase == 'success'
            actual_result = deep_result_value(data_to_format)
            # Add timestamp to the header for agent responses
            ::CLI::UI::Frame.open("Agent Response (#{formatted_time})", color: :green) do
              ::CLI::UI.puts actual_result.to_s
            end
            ::CLI::UI.puts '' # Add extra line break after the response
            return
          end

          unless data_to_format.is_a?(Hash) && data_to_format.key?(:status)
            ::CLI::UI::Frame.open("Agent Response (#{formatted_time})", color: :cyan) do
              ::CLI::UI.puts data_to_format.inspect
            end
            ::CLI::UI.puts '' # Add extra line break after the response
            return
          end

          case data_to_format[:status]
          when :error
            title_color = :red
            title_prefix = 'Agent Error'
            message_body_content = data_to_format[:error_message]
            ::CLI::UI::Frame.open("#{title_prefix} (#{formatted_time})", color: title_color) do
              ::CLI::UI.puts message_body_content
            end
          when :pending
            title_color = :yellow
            title_prefix = 'Agent Pending'
            message_body_content = "Job ID [#{data_to_format[:job_id]}] - #{data_to_format[:message]}"
            ::CLI::UI::Frame.open("#{title_prefix} (#{formatted_time})", color: title_color) do
              ::CLI::UI.puts message_body_content
            end
          else
            title_color = :magenta
            title_prefix = "Agent (Status: #{data_to_format[:status]})"
            message_body_content = data_to_format.inspect
            ::CLI::UI::Frame.open("#{title_prefix} (#{formatted_time})", color: title_color) do
              ::CLI::UI.puts message_body_content
            end
          end
          ::CLI::UI.puts '' # Add extra line break after any response
        end
        # --- END _format_chat_turn_output_cli_ui ---
      end # end no_commands

      # --- Definition Management Commands (Existing - no changes shown for brevity) ---
      desc 'list', 'List all defined agents'
      def list
        begin
          ADK::AgentDefinitionStore.load_all_from_redis
        rescue Redis::BaseError => e
          say "Error: Could not connect to Redis to load agent definitions. Is it running? (#{e.message})", :red
          exit(1)
        end
        definitions = ADK::AgentDefinitionStore.all
        if definitions.empty?
          say 'No agent definitions found.'
          return
        end
        say 'Defined Agents:', :bold
        definitions.sort_by { |name, _| name.to_s }.each do |name, data|
          description = data[:description] || '[No description]'
          tools = data[:tools]
          model = data[:model] || "#{ADK::Agent::DEFAULT_MODEL} (Default)"
          tools_str = tools.empty? ? 'None' : tools.join(', ')
          say "- #{name}: #{description} (Model: #{model}, Tools: #{tools_str})"
        end
      end

      desc 'save NAME', 'Create or update an agent definition'
      method_option :description, type: :string, required: true, desc: 'Agent description'
      method_option :tools, type: :string, aliases: '-t', desc: 'Comma-separated list of tool names (e.g., "echo,calculator")'
      method_option :model, type: :string, desc: "LLM model name (default: #{ADK::Agent::DEFAULT_MODEL})"
      method_option :instruction, type: :string, desc: "Core instructions for the agent's behavior (system prompt)."
      method_option :webhook_enabled, type: :boolean, default: false, desc: 'Enable webhook triggering for this agent.'
      method_option :webhook_secret, type: :string, desc: 'Secret key for webhook validation (if webhook_enabled).'
      method_option :mcp_servers_json, type: :string, desc: 'JSON string of MCP server configurations array.'

      def save(name)
        name_sym = name.to_sym
        description = options[:description]
        model_to_save = options[:model] && !options[:model].empty? ? options[:model] : ADK::Agent::DEFAULT_MODEL
        instruction_to_save = options[:instruction]

        selected_tools = []
        valid_tools = ADK::GlobalToolManager.registered_tool_names.map(&:to_s)
        if options[:tools]
          requested_tools = options[:tools].split(',').map(&:strip).reject(&:empty?)
          requested_tools.each do |tool_name|
            if valid_tools.include?(tool_name)
              selected_tools << tool_name unless selected_tools.include?(tool_name)
            else
              say "Warning: Unknown globally registered tool '#{tool_name}', ignoring.", :yellow
            end
          end
        end

        definition = {
          description: description,
          tools: selected_tools,
          model: model_to_save,
          instruction: instruction_to_save,
          fallback_mode: :error,
          mcp_servers_json: options[:mcp_servers_json] || '[]',
          webhook_enabled: options[:webhook_enabled],
          webhook_secret: options[:webhook_secret]
        }

        unless ADK::AgentDefinitionStore.save_to_redis(name_sym, definition)
          say 'Error saving definition to Redis. Aborting.', :red
          exit(1)
        end
        ADK::AgentDefinitionStore.register(name_sym, definition)
        tools_msg = selected_tools.empty? ? 'None' : selected_tools.join(', ')
        say "Agent definition '#{name}' saved (Model: #{model_to_save}, Tools: #{tools_msg}, Instruction: #{instruction_to_save ? 'Set' : 'Not Set'}).", :green
      end

      desc 'delete NAME', "Delete an agent's definition"
      def delete(name)
        name_sym = name.to_sym
        definition_exists = false

        # Check in-memory first
        if ADK::AgentDefinitionStore.find(name_sym)
          definition_exists = true
        else
          # Then check Redis
          begin
            definition_from_redis = ADK::AgentDefinitionStore.load_from_redis(name_sym)
            definition_exists = !definition_from_redis.nil?
          rescue Redis::BaseError => e
            say "Error: Could not connect to Redis to check agent definition. #{e.message}", :red
            exit(1)
          end
        end

        unless definition_exists
          say "Error: Agent definition '#{name}' not found.", :red
          exit(1)
        end

        if yes?("Are you sure you want to permanently delete agent definition '#{name}'? [y/N]", :yellow)
          redis_deleted = ADK::AgentDefinitionStore.delete_from_redis(name_sym)
          ADK::AgentDefinitionStore.remove(name_sym)
          if redis_deleted
            say "Agent definition '#{name}' deleted successfully.", :green
          else
            say 'Error deleting definition from Redis. It has been removed from memory, but may still exist in Redis.', :red
            exit(1)
          end
        else
          say 'Deletion cancelled.', :yellow
        end
      end

      desc 'generate NAME', 'Generate a new agent definition file'
      method_option :description, type: :string, default: 'A new ADK agent.', desc: 'Agent description'
      method_option :instruction, type: :string, default: 'You are a helpful assistant.', desc: 'Agent instruction (system prompt)'
      method_option :tools, type: :string, aliases: '-t', default: '', desc: 'Comma-separated list of tool names (e.g., "echo,calculator")'
      method_option :model, type: :string, desc: 'LLM model name (uses framework default if blank)'
      method_option :dir, type: :string, default: './agents', desc: 'Directory to save the agent definition file'
      method_option :force, type: :boolean, default: false, desc: 'Overwrite existing file without prompting'
      method_option :webhook_enabled, type: :boolean, default: false, desc: 'Include webhook configuration placeholders'
      def generate(name)
        agent_name_sym = name.to_sym
        dir_path = File.expand_path(options[:dir])
        file_path = File.join(dir_path, "#{name}_agent.rb")
        if File.exist?(file_path) && !options[:force] && !yes?("Agent file '#{file_path}' already exists. Overwrite? [y/N]", :yellow)
          say 'Generation cancelled.', :yellow
          exit(0)
        end
        begin
          FileUtils.mkdir_p(dir_path)
        rescue SystemCallError => e
          say "Error: Could not create directory '#{dir_path}': #{e.message}", :red
          exit(1)
        end
        agent_name_str = name
        description = options[:description]
        instruction = options[:instruction]
        tools_list = options[:tools].split(',').map(&:strip).reject(&:empty?).map(&:to_sym)
        model_str = options[:model]
        webhook_enabled = options[:webhook_enabled]
        code = <<~RUBY
          require 'adk'

          ADK::Agent.define do |a|
            a.name :#{agent_name_sym}
            a.description "#{description}"
            a.instruction "#{instruction}"
          #{'  '}
        RUBY
        if model_str && !model_str.empty?
          code += "  # Optional: Specify model (defaults to ADK.config.default_model_name)\n"
          code += "  a.model_name '#{model_str}'\n\n"
        else
          code += "  # Model will use framework default: #{ADK.config.default_model_name}\n\n"
        end
        code += "  # Define tools the agent can use\n"
        if tools_list.empty?
          code += "  # a.use_tool :echo # Example\n"
        else
          tools_list.each { |tool| code += "  a.use_tool :#{tool}\n" }
        end
        code += "\n"
        if webhook_enabled
          code += <<~WEBHOOK
            # --- Webhook Configuration ---#{' '}
            # This agent can be triggered by POST /webhooks/agents/#{agent_name_sym}/trigger
            # (Assuming default listener base_path and dynamic_agent_route_pattern in ADK.configure)

            a.webhook_enabled true

            a.webhook_transformer ->(request_body) do#{' '}
              raise NotImplementedError, "Please implement the webhook_transformer proc to convert request_body into agent user_input."
            end

            a.webhook_session_extractor ->(request_body) do
              raise NotImplementedError, "Please implement the webhook_session_extractor proc to extract a session ID."
            end
          WEBHOOK
        end
        code += "end\n"
        begin
          File.write(file_path, code)
          say "Agent definition file created at '#{file_path}'", :green
          if webhook_enabled
            say "\nWebhook configuration placeholders added. Please implement the required transformer and extractor procs.", :yellow
            say 'Remember to configure validation and secrets for production use!', :yellow
          end
        rescue SystemCallError => e
          say "Error: Could not write file '#{file_path}': #{e.message}", :red
          exit(1)
        end
      end

      desc 'start NAME', 'Verify agent definition loading and start (Ephemeral)'
      long_desc <<-LONGDESC
        Loads agent definition, instantiates agent, starts agent runtime state,
        verifies all components loaded correctly, prints details & exits.
        This is a diagnostic tool to verify agent definition loads properly.
        Use 'execute' or 'chat' command to run an actual task with the agent.
      LONGDESC
      def start(name)
        name_sym = name.to_sym
        say "Loading agent '#{name}'..."

        # First check the global registry
        agent_definition_object = ADK::GlobalDefinitionRegistry.find(name_sym)

        # If not found in memory, try loading from Redis
        if agent_definition_object.nil?
          definition_hash = ADK::AgentDefinitionStore.load_from_redis(name_sym)

          unless definition_hash
            say "Error: Agent definition '#{name}' not found.", :red
            exit(1)
          end

          say "Creating agent '#{name}' from definition object..."
          agent_definition_object = ADK::AgentDefinition.from_hash(definition_hash)

          unless agent_definition_object
            say "Error: Could not create a valid AgentDefinition object for '#{name}' from the loaded hash.", :red
            exit(1)
          end
        end

        agent = nil
        begin
          # Pass the definition object directly. Session service will use global default.
          agent = ADK::Agent.new(definition: agent_definition_object)

          say "  - Agent uses model: #{agent.model_name}", :cyan
          say "  - Agent instruction: #{agent.instruction.inspect}", :cyan

          # Tool loading is now handled by ADK::Agent#initialize via the definition.
          # We can check which tools the agent *actually* loaded for verification.
          loaded_tool_names = agent.tools.map(&:name)
          defined_tool_names = agent_definition_object.tool_names.to_a
          missing_tools = defined_tool_names - loaded_tool_names

          say "  - Warning: Tools defined but not loaded/found: [#{missing_tools.join(', ')}]", :yellow unless missing_tools.empty?
          say "  - Loaded tools: [#{loaded_tool_names.join(', ')}]", :cyan

          say '  - Starting agent runtime...', :cyan, false
          agent.start
          say 'started.', :cyan
          say "\nAgent '#{name}' is ready.", :green
        rescue StandardError => e
          say "\nError during agent setup: #{e.class} - #{e.message}", :red
          puts e.backtrace.first(5).join("\n")
          exit(1)
        ensure
          if agent&.running?
            say '  - Stopping agent runtime...', :cyan, false
            agent.stop
            say 'stopped.', :cyan
          end
        end
      end

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
        definition_hash = ADK::AgentDefinitionStore.find(name_sym)
        definition_hash ||= ADK::AgentDefinitionStore.load_from_redis(name_sym)

        unless definition_hash
          say "Error: Agent definition '#{name}' not found.", :red
          exit(1)
        end

        say "Creating agent '#{name}' from definition object..."
        agent_definition_object = ADK::AgentDefinition.from_hash(definition_hash)

        unless agent_definition_object
          say "Error: Could not create a valid AgentDefinition object for '#{name}' from the loaded hash.", :red
          exit(1)
        end

        session_service_instance = options[:redis] ? ADK::SessionService::Redis.new : @@session_service_for_execute
        session_id_opt = options[:session_id]
        adk_session = nil
        if session_id_opt
          adk_session = session_service_instance.get_session(session_id: session_id_opt)
          if adk_session then say "Continuing session: #{session_id_opt}", :cyan
          else
            say "Warning: Session ID '#{session_id_opt}' provided but not found. Starting a new session.", :yellow
            session_id_opt = nil end
        end
        unless adk_session
          adk_session = session_service_instance.create_session(app_name: name, user_id: 'cli_user')
          session_id_opt = adk_session.id
          say "Started new session: #{session_id_opt}", :cyan
          say "  (Using #{options[:redis] ? 'Redis' : 'in-memory'} session storage)", :cyan
        end

        agent = nil
        e_outer = nil
        begin
          # Pass the definition object. Session service for the agent instance itself will use global default
          # or the one passed if ADK::Agent.new supported it directly for its own session_service attr.
          # The run_task method will use the session_service_instance passed to it for actual session operations.
          agent = ADK::Agent.new(
            definition: agent_definition_object,
            session_service: session_service_instance
          )

          say "  - Agent uses model: #{agent.model_name}", :cyan

          # Tool loading is now handled by ADK::Agent#initialize via the definition.
          loaded_tool_instances = agent.tools
          loaded_tool_names = loaded_tool_instances.map(&:name)
          defined_tool_names = agent_definition_object.tool_names.to_a
          missing_tools = defined_tool_names - loaded_tool_names

          say "  - Warning: Tools defined but not loaded/found: [#{missing_tools.join(', ')}]", :yellow unless missing_tools.empty?
          say "  - Loaded tools: [#{loaded_tool_names.join(', ')}]", :cyan
          say '  - Starting agent runtime...', :cyan, false
          agent.start
          say 'started.', :cyan
          say "  - Running task in session #{session_id_opt}: '#{task}'...", :cyan, false
          final_event_or_error = agent.run_task(
            session_id: session_id_opt,
            user_input: task,
            session_service: session_service_instance
          )
          say 'finished.', :cyan
          say "\nTask Result:", :bold
          format_cli_result(final_event_or_error)
        rescue StandardError => e
          e_outer = e
          say "\nError during agent execution: #{e.class} - #{e.message}", :red
          puts e.backtrace.first(5).join("\n")
        ensure
          if agent&.running?
            say '  - Stopping agent runtime...', :cyan, false
            agent.stop
            say 'stopped.', :cyan
          end
          exit(1) if e_outer
        end
      end # End 'execute' command

      # --- CHAT COMMAND ---
      desc 'chat AGENT_NAME', 'Interactively chat with an agent definition'
      long_desc <<-LONGDESC
        Starts an interactive chat session with the specified agent.
        The agent definition is loaded from the configured store (usually Redis).

        Session Handling:
        - By default, uses an in-memory session that is lost when the chat ends.
        - Use `--session-service redis` to use persistent Redis-backed sessions.
        - Use `--session-id <ID>` to resume a specific existing session. If the ID
          is not found with the specified service, a new session will be created.

        Type "exit" or "quit" to end the chat.
      LONGDESC
      method_option :session_id, type: :string, desc: 'ID of an existing session to resume.'
      method_option :session_service, type: :string, default: 'memory', enum: %w[memory redis],
                                      desc: 'Session service to use (memory or redis).'
      def chat(agent_name_str)
        ::CLI::UI::StdoutRouter.enable
        agent_name_sym = agent_name_str.to_sym

        definition = ADK::AgentDefinitionStore.load_from_redis(agent_name_sym)
        unless definition
          ::CLI::UI.puts "{{red:Error: Agent definition '#{agent_name_str}' not found in Redis.}}"
          exit(1)
        end

        session_service_instance = if options[:session_service] == 'redis'
                                     ADK::SessionService::Redis.new
                                   else
                                     ADK::SessionService::InMemory.new
                                   end

        current_session_id = options[:session_id]
        adk_session = nil # Will hold the loaded ADK::Session object

        ::CLI::UI::Frame.open("Chat Session with #{agent_name_str}", color: :blue) do
          ::CLI::UI.puts "{{bold:Agent Description:}} #{definition[:description]}"
          if current_session_id
            adk_session = session_service_instance.get_session(session_id: current_session_id)
            if adk_session
              ::CLI::UI.puts "{{green:Resuming session:}} #{current_session_id} (#{options[:session_service]})"
              # --- MODIFIED: Display history if session is loaded and has events ---
              if adk_session.events && !adk_session.events.empty?
                ::CLI::UI.puts "\n{{bold:━━━ Recent Conversation History ━━━}}"

                # Group events by conversation turns
                history_events = adk_session.events.last(20) # Show more history items
                current_date = nil

                history_events.each do |event|
                  # Extract timestamp from event and format it
                  event_time = event.timestamp ? Time.at(event.timestamp) : Time.now
                  formatted_time = event_time.strftime('%H:%M:%S')

                  # Show date separator if this is a new day
                  event_date = event_time.strftime('%Y-%m-%d')
                  if current_date != event_date
                    current_date = event_date
                    ::CLI::UI.puts "\n{{bold:┅┅┅ #{event_time.strftime('%B %d, %Y')} ┅┅┅}}"
                  end

                  if event.role == :user
                    # For user role, event.content is the string message
                    _format_chat_turn_output_cli_ui(event.content, :user, formatted_time)
                  elsif event.role == :agent
                    # For agent role, event.content is the hash {status:, result:, ...}
                    _format_chat_turn_output_cli_ui(event.content, :agent, formatted_time)
                  end
                  # Tool events are generally not shown in simple chat history
                end
                ::CLI::UI.puts "{{bold:━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━}}\n"
              else
                ::CLI::UI.puts '{{italic:No previous messages in this session.}}'
              end
              # --- END MODIFICATION ---
            else
              ::CLI::UI.puts "{{yellow:Warning: Session ID '#{current_session_id}' not found. Starting new session.}}"
              current_session_id = nil # Force new session creation
            end
          end
          unless adk_session # If still no session (either not provided, or provided but not found)
            adk_session = session_service_instance.create_session(app_name: agent_name_str, user_id: "cli_chat_user_#{SecureRandom.hex(3)}")
            current_session_id = adk_session.id # Update current_session_id with the new one
            ::CLI::UI.puts "{{green:Started new session:}} #{current_session_id} (#{options[:session_service]})"
          end
          ::CLI::UI.puts "{{gray:Type 'exit' or 'quit' to end the chat.}}"
        end
        ::CLI::UI.puts '---'

        agent = nil
        begin
          # The definition hash is already loaded as `definition` variable earlier in this command.
          # Convert hash to an ADK::AgentDefinition object
          agent_definition_object = ADK::AgentDefinition.from_hash(definition)

          unless agent_definition_object
            ::CLI::UI.puts "{{red:Error: Could not create a valid AgentDefinition object for '#{agent_name_str}' from the loaded hash.}}"
            exit(1)
          end

          # Instantiate the agent with its definition object and the selected session service
          agent = ADK::Agent.new(
            definition: agent_definition_object,
            session_service: session_service_instance # Pass the already determined session service
          )
          # Tool setup is now handled within ADK::Agent#initialize based on the definition object.

          agent.start
        rescue StandardError => e
          ::CLI::UI.puts "{{red:Error initializing or starting agent: #{e.message}}}"
          exit(1)
        end

        loop do
          user_input = ::CLI::UI::Prompt.ask('You')
          break if user_input.nil?

          user_input.strip!
          break if %w[exit quit].include?(user_input.downcase)
          next if user_input.empty?

          final_event = nil
          session_lost_flag = false
          begin
            ::CLI::UI::Spinner.spin('Agent thinking...') do |_spinner|
              current_adk_session_for_task = session_service_instance.get_session(session_id: current_session_id)
              unless current_adk_session_for_task
                ::CLI::UI.puts "{{red:Error: Session '#{current_session_id}' lost. Please restart chat.}}"
                session_lost_flag = true
                break
              end

              final_event = agent.run_task(
                session_id: current_session_id,
                user_input: user_input,
                session_service: session_service_instance
              )
            end
            break if session_lost_flag

            _format_chat_turn_output_cli_ui(final_event)
          rescue StandardError => e
            ::CLI::UI::Frame.open('Error During Task', color: :red) do
              ::CLI::UI.puts e.message
            end
          end
        end
      ensure
        agent&.stop if agent&.running?
        ::CLI::UI.puts '{{yellow:Chat ended.}}'
      end
      # --- END CHAT COMMAND ---

      def self.exit_on_failure?
        true
      end
    end # End AgentCommands class
  end # End CLI module
end # End ADK module
