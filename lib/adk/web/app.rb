# File: lib/adk/web/app.rb
# frozen_string_literal: true

# This file defines the main Sinatra application for the ADK Web UI.
# It handles agent definition management (via Redis), runtime management (in-memory),
# user interactions (chat, direct execution), tool discovery (native and MCP),
# and provides a dynamic web interface using HTMX.

# STDOUT.sync = true # Uncomment for immediate output flushing if needed
# --- Core Web Framework Dependencies ---
require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/custom_logger' # For using helpers Sinatra::CustomLogger
require 'sinatra/reloader'
require 'slim' # Templating engine
require 'json'
require_relative 'sass_compiler' # For compiling Sass/SCSS to CSS
require 'rack/utils' # For escape_html
require 'redis' # For agent definition persistence
require 'securerandom' # For session secret generation
require 'sidekiq/api' # Used for potential future async job display (not currently used in active logic)
require_relative '../mcp/util/schema_converter' # For converting MCP tool schemas
require 'gemini-ai' # For example task generation via Gemini API

# --- Load ADK Components ---
# Order matters: Load core concepts before components that depend on them.
require_relative '../event'   # Core event structure used by sessions
require_relative '../session' # Session structure for conversation history
require_relative '../tool_context' # Context object passed to tools during execution
require_relative '../agent' # Core Agent class (defines DEFAULT_MODEL)
require_relative '../tool' # Base Tool class
require_relative '../tool_registry' # Manages tools within an agent instance
require_relative '../session_service/in_memory' # Default in-memory session storage
require_relative '../session_service/redis' # Alternative Redis-based session storage (not currently used by default)
require_relative '../global_tool_manager' # Discovers and manages native tools available to the application
# Explicitly require built-in native tools so GlobalToolManager can find them
require_relative '../tools/echo'
require_relative '../tools/calculator'
require_relative '../tools/cat_facts'
require_relative '../tools/random_number_tool'
require_relative '../tools/agent_tool' # Tool that allows an agent to call another agent
require_relative '../tools/base_async_job_tool' # Base class for tools that run asynchronously
require_relative '../tools/check_job_status_tool' # Tool to check the status of async jobs
require_relative '../tools/sleepy_tool' # Example async tool
# --- NEW: Require Definition Store ---
require_relative '../definition_store'

# --- Route Modules ---
require_relative 'routes/core_routes'
require_relative 'routes/api_routes'
require_relative 'routes/tools_ui_routes'
require_relative 'routes/agent_runtime_routes'
require_relative 'routes/agent_definition_routes' # Ensure this is present

# Load dotenv for development environment variables
if ENV['RACK_ENV'] == 'development' || Sinatra::Base.development?
  begin; require 'dotenv/load'; rescue LoadError; end
end

module ADK
  module Web
    # Sinatra application providing a web UI for managing and interacting with ADK Agents.
    # Uses Redis for agent definition persistence and an in-memory hash for running agent instances.
    # Leverages HTMX for dynamic UI updates and communicates with external tools via MCP.
    class App < Sinatra::Base
      helpers Sinatra::CustomLogger # Integrate Sinatra logging with the central ADK logger

      # Development-specific configurations
      configure :development do
        register Sinatra::Reloader # Enable automatic code reloading
        # Optional: Increase logging level specifically for development web server
        # ADK.logger.level = Logger::DEBUG if ADK.logger
      end

      # General configurations for all environments
      configure do
        set :logger, ADK.logger # Use the central ADK logger
        # Enable Sinatra sessions for storing user-specific chat session IDs
        enable :sessions
        # Set session secret. Use environment variable in production for security.
        set :session_secret, ENV['SESSION_SECRET'] || SecureRandom.hex(64)
      end

      # --- Sinatra Settings ---
      set :root, File.expand_path('../../..', __dir__) # Project root directory
      set :views, File.expand_path('../views', __FILE__) # Views directory for Slim templates
      set :public_folder, File.expand_path('../public', __FILE__) # Directory for static assets (CSS, JS, images)
      set :slim, pretty: true # Configure Slim for readable HTML output

      # --- Constants ---
      # Prefix for Redis keys storing agent definition hashes.
      REDIS_AGENT_HASH_PREFIX = "adk:agent:"
      # Redis key for the set containing all defined agent names.
      REDIS_AGENTS_SET_KEY = "adk:agents:all_names"
      # List of available Gemini models selectable in the UI.
      AVAILABLE_MODELS = ['gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-1.5-pro', 'gemini-1.0-pro'].freeze

      # --- Register Route Modules ---
      register ADK::Web::CoreRoutes
      register ADK::Web::ApiRoutes
      register ADK::Web::ToolsUIRoutes
      register ADK::Web::AgentRuntimeRoutes
      register ADK::Web::AgentDefinitionRoutes # Ensure this is present

      # --- Instance Variables ---
      # Initializes application state, including connections and services.
      def initialize
        super
        @logger = ADK.logger # Ensure logger is set early
        # In-memory hash storing active/running ADK::Agent instances, keyed by agent name.
        @agents = {}
        # Service responsible for managing chat sessions (stores conversation history).
        # Defaulting to in-memory storage.
        @session_service = ADK::SessionService::InMemory.new
        # --- MODIFIED: Initialize Definition Store ---
        @definition_store = nil
        begin
          # 1. Create Redis client instance
          #    (Consider making connection details configurable via ENV vars)
          redis_client = Redis.new

          # 2. Check connection explicitly before creating store
          redis_client.ping
          @logger.info("Successfully connected to Redis.")

          # 3. Instantiate the definition store
          @definition_store = ADK::DefinitionStore::RedisStore.new(redis_client: Redis.new(ADK.redis_options))
          @logger.info("Agent Definition Store initialized.")
        rescue Redis::CannotConnectError => e
          @logger.error("Could not connect to Redis. Agent definition persistence disabled. #{e.message}")
          # @definition_store remains nil
        rescue ADK::DefinitionStore::ConfigurationError => e
          # Catch errors specifically from store initialization if any
          @logger.error("Failed to initialize Definition Store: #{e.message}")
          # @definition_store remains nil
        rescue => e # Catch other potential errors during Redis init
          @logger.error("Unexpected error during Redis/Definition Store initialization: #{e.class} - #{e.message}")
          # @definition_store remains nil
        end
        # --- END MODIFICATION ---

        # Compile SASS/SCSS files in public/styles to CSS in public/css on application startup.
        SassCompiler.compile_all
      end

      # --- Sinatra Helpers ---
      # Utility methods accessible within route handlers and Slim templates.
      helpers do
        # Fetches tool lists from one or more MCP (Multi-Capability Protocol) servers.
        # Connects to each server defined in the mcp_configs array, lists its tools,
        # and handles connection errors or timeouts.
        # @param mcp_configs [Array<Hash>] Array of hashes, each defining an MCP server connection (e.g., {type: :stdio, command: "...", name: "..."}, {type: :tcp, url: "...", name: "..."}).
        # @param timeout_seconds [Integer] Connection/fetch timeout per server.
        # @return [Array<Hash>] An array of result hashes, one for each config.
        #   Success: { status: :success, server: String, config: Hash, tools: Array<Hash> }
        #   Error:   { status: :error, server: String, config: Hash, message: String }
        def fetch_mcp_tools(mcp_configs, timeout_seconds = 5)
          # Ensure necessary ADK::Mcp classes are loaded (might be redundant if loaded globally, but safe)
          require_relative '../mcp/client'
          require_relative '../mcp/error'
          require 'timeout'

          aggregated_results = [] # Store results for each server config
          return aggregated_results unless mcp_configs.is_a?(Array)

          mcp_configs.each_with_index do |config, index|
            # --- FIXED: Use string keys for server_label ---\
            server_label = config['name'] || config['command'] || config['url'] || "Server #{index + 1}" # Need string keys here
            begin
              logger.info("Attempting to fetch tools from MCP server: #{server_label}")
              result = Timeout.timeout(timeout_seconds) do
                client = nil
                fetched_tools = []
                begin
                  # Transform keys to symbols for the client
                  symbolized_config = config.transform_keys(&:to_sym)
                  # --- NEW: Explicitly convert string 'stdio' value to symbol :stdio ---
                  if symbolized_config[:type] == "stdio"
                    symbolized_config[:type] = :stdio
                  end
                  # Pass the modified hash with symbol keys and potentially symbolized type value
                  client = ADK::Mcp::Client.new(symbolized_config)
                  # Connect implicitly calls list_tools during handshake in current implementation
                  # If connect succeeds, tools should be available via client instance if needed
                  client.connect # Performs handshake
                  fetched_tools = client.list_tools # Explicitly list tools
                  logger.info("Successfully fetched #{fetched_tools.count} tools from #{server_label}.")
                  # Add server label/config for context in results
                  aggregated_results << { status: :success, server: server_label, config: config, tools: fetched_tools }
                rescue ADK::Mcp::ConnectionError, ADK::Mcp::ProtocolError => e
                  logger.error("MCP Error fetching tools from #{server_label}: #{e.message}")
                  aggregated_results << { status: :error, server: server_label, config: config,
                                          message: "MCP Connection/Protocol Error: #{e.message}" }
                rescue StandardError => e
                  logger.error("Unexpected Error fetching tools from #{server_label}: #{e.class} - #{e.message}")
                  logger.error(e.backtrace.first(5).join("\n")) # Log backtrace for unexpected errors
                  aggregated_results << { status: :error, server: server_label, config: config,
                                          message: "Internal Error: #{e.message}" }
                ensure
                  # Ensure disconnect is always attempted if client was created
                  client&.disconnect
                end
              end # Timeout block
            rescue Timeout::Error
              logger.error("Timeout (#{timeout_seconds}s) fetching tools from MCP server: #{server_label}")
              aggregated_results << { status: :error, server: server_label, config: config,
                                      message: "Timeout after #{timeout_seconds} seconds" }
            end # Begin/rescue Timeout
          end # each_with_index

          aggregated_results
        end
        # <---------------------------------------------------->

        # Helper for Agent Start/Stop button fragments (used in table view)
        def agent_status_fragments(agent_data_or_obj)
          agent_name = agent_data_or_obj.is_a?(Hash) ? agent_data_or_obj[:name] : agent_data_or_obj.name
          is_running = agent_data_or_obj.is_a?(Hash) ? agent_data_or_obj[:running] : agent_data_or_obj.running?
          status_content_id = "agent-status-content-#{agent_name}"
          start_button_id = "agent-start-button-#{agent_name}"
          stop_button_id = "agent-stop-button-#{agent_name}"

          status_tag_class = is_running ? 'is-success' : 'is-light'
          status_text = is_running ? 'Running' : 'Stopped'
          status_content_html = %(<span class='tag #{status_tag_class}'>#{status_text}</span>)

          start_button_html = %(
            <button class='button is-success is-light is-small' type='button' id='#{start_button_id}'
                    hx-post='/agents/#{agent_name}/start' hx-target='##{status_content_id}' hx-swap='innerHTML'
                    #{is_running ? 'disabled' : ''} hx-swap-oob='outerHTML:##{start_button_id}'>Start</button>
          )
          stop_button_html = %(
            <button class='button is-warning is-light is-small' type='button' id='#{stop_button_id}'
                    hx-post='/agents/#{agent_name}/stop' hx-target='##{status_content_id}' hx-swap='innerHTML'
                    #{is_running ? '' : 'disabled'} hx-swap-oob='outerHTML:##{stop_button_id}'>Stop</button>
          )
          status_content_html + start_button_html + stop_button_html
        end # end agent_status_fragments

        # Helper for formatting tool/agent execution results into HTML <-- MODIFIED
        # Handles success, error, and pending statuses.
        def format_execution_result_html(result_data)
          html_parts = []
          notification_class = 'is-info'
          overall_status = :unknown

          # Handle ADK::Event first
          if result_data.is_a?(ADK::Event)
            result_data = result_data.content
          end

          # Determine overall status from hash or array
          if result_data.is_a?(Hash) && result_data.key?(:status)
            overall_status = result_data[:status]
          elsif result_data.is_a?(Array) && result_data.all? { |h| h.is_a?(Hash) && h.key?(:status) }
            if result_data.any? { |h| h[:status] == :error } then overall_status = :error
            elsif result_data.any? { |h| h[:status] == :pending } then overall_status = :pending
            elsif result_data.empty? then overall_status = :warning
            else overall_status = :success end
          else
            overall_status = :error
            result_data = { status: :error, error_message: "Unexpected result format: #{result_data.inspect}" }
          end

          # Set notification class based on status
          notification_class = case overall_status
                               when :success then 'is-success'
                               when :error then 'is-danger'
                               when :pending then 'is-warning' # Use warning for pending
                               else 'is-info' end

          # Generate HTML content
          if result_data.is_a?(Array) # Multi-step result array
            html_parts << "<p><strong>Multi-step Result:</strong></p><ol>"
            result_data.each_with_index do |step_hash, index|
              html_parts << "<li>"
              if step_hash.is_a?(Hash)
                case step_hash[:status]
                when :success
                  step_result_content = step_hash[:result]
                  if step_result_content.is_a?(Hash) && step_result_content.key?(:status)
                    html_parts << "<strong>Step #{index + 1} (Success - Delegated):</strong>"
                    html_parts << "<blockquote style='margin-left: 1em; border-left: 3px solid #dbdbdb; padding-left: 1em;'>"
                    html_parts << format_execution_result_html(step_result_content)
                    html_parts << "</blockquote>"
                  else
                    html_parts << "<strong>Step #{index + 1} (Success):</strong> <pre>#{Rack::Utils.escape_html(step_result_content.to_s)}</pre>"
                  end
                when :pending
                  html_parts << "<strong>Step #{index + 1} (Pending):</strong>"
                  html_parts << "<pre>Job ID: #{Rack::Utils.escape_html(step_hash[:job_id].to_s)}"
                  html_parts << "\nMessage: #{Rack::Utils.escape_html(step_hash[:message].to_s)}" if step_hash[:message]
                  html_parts << "</pre>"
                when :error
                  html_parts << "<strong>Step #{index + 1} (Error):</strong> <pre class='has-text-danger'>#{Rack::Utils.escape_html(step_hash[:error_message].to_s)}</pre>"
                else # Unknown status
                  html_parts << "<strong>Step #{index + 1} (Unknown Status):</strong> <pre>#{Rack::Utils.escape_html(step_hash.inspect)}</pre>"
                end
              else
                html_parts << "<strong>Step #{index + 1} (Invalid format):</strong> <pre>#{Rack::Utils.escape_html(step_hash.inspect)}</pre>"
              end
              html_parts << "</li>"
            end
            html_parts << "</ol>"

          elsif result_data.is_a?(Hash) # Single result/error/pending hash
            case result_data[:status]
            when :success
              result_content = result_data[:result]
              if result_content.is_a?(Hash) && result_content.key?(:status)
                html_parts << "<p><strong>Result (from delegated agent):</strong></p>"
                html_parts << "<blockquote style='margin-left: 1em; border-left: 3px solid #dbdbdb; padding-left: 1em;'>"
                html_parts << format_execution_result_html(result_content)
                html_parts << "</blockquote>"
              else
                html_parts << "<p><strong>Result:</strong></p><pre>#{Rack::Utils.escape_html(result_content.to_s)}</pre>"
              end
            when :pending
              html_parts << "<p><strong>Status: Pending</strong></p>"
              html_parts << "<pre>Job ID: #{Rack::Utils.escape_html(result_data[:job_id].to_s)}"
              html_parts << "\nMessage: #{Rack::Utils.escape_html(result_data[:message].to_s)}" if result_data[:message]
              html_parts << "\n(Use tool 'check_job_status' with this ID to get the final result)</pre>"
            when :error
              html_parts << "<p><strong>Error:</strong></p><pre class='has-text-danger'>#{Rack::Utils.escape_html(result_data[:error_message].to_s)}</pre>"
            else # Unknown status within hash
              html_parts << "<p><strong>Result (Unknown Status):</strong></p><pre>#{Rack::Utils.escape_html(result_data.inspect)}</pre>"
            end
          end

          # Return final HTML structure
          "<div class='notification #{notification_class} mt-4'>#{html_parts.join}</div>"
        end # end format_execution_result_html

        # --- NEW HELPER: Process agent chat response for display ---
        def process_agent_response(agent_result)
          response_data = {
            msg_class: 'is-warning',
            display_content: "",
            raw_json_content: "",
            event_id: SecureRandom.hex(4) # Default unique ID
          }

          case agent_result
          when ADK::Event
            response_data[:event_id] = agent_result.event_id || response_data[:event_id]
            if agent_result.role == :agent
              content = agent_result.content
              # --- Ensure raw content is always the full hash inspection ---
              response_data[:raw_json_content] = content.inspect

              if content.is_a?(Hash)
                # Extract the primary result/message based on status
                case content[:status]
                when :success
                  response_data[:msg_class] = 'is-success'
                  # --- MODIFIED: Explicitly convert only the result value to string ---
                  result_value = content[:result]
                  response_data[:display_content] = result_value.to_s # Explicit .to_s here
                  # --------------------------------------------------------------------
                when :error
                  response_data[:msg_class] = 'is-danger'
                  original_error = content[:error_message] || "Agent error (no message)"
                  # --- Make planning error friendlier ---
                  if original_error == "I cannot fulfill this request with the available tools (empty plan)."
                    response_data[:display_content] =
                      "Sorry, I couldn't determine how to handle that request with the tools I have available."
                  else
                    response_data[:display_content] = original_error
                  end
                  # --- End friendly error ---
                when :pending
                  response_data[:msg_class] = 'is-warning'
                  response_data[:display_content] = "Task pending... Job ID: #{content[:job_id]}"
                  if content[:message] then response_data[:display_content] << " - #{content[:message]}"; end
                else # Unknown status in hash
                  response_data[:display_content] = "Agent response has unknown status: #{content[:status]}"
                  # Raw content is already set above
                end
              else # Event Content wasn't a hash
                response_data[:display_content] = "Agent event content format unexpected: #{content.inspect}"
                # Raw content is already set above
              end
            else # Event not from agent role
              response_data[:display_content] = "Received non-agent event role: #{agent_result.role}"
              response_data[:raw_json_content] = agent_result.inspect
            end

          when Hash
            response_data[:raw_json_content] = agent_result.inspect
            if agent_result[:status] == :error # Explicit error hash (e.g., agent not running)
              response_data[:msg_class] = 'is-danger'
              response_data[:display_content] = agent_result[:error_message] || "An unspecified error occurred."
            else # Other hash format?
              response_data[:display_content] = "Unexpected hash format from server: #{agent_result.inspect}"
            end

          else # Not Event or Hash
            response_data[:raw_json_content] = agent_result.inspect
            response_data[:display_content] = "Unexpected response type from server: #{agent_result.class}"
          end

          response_data # Return the processed hash
        end
        # --- END NEW HELPER ---

        # --- NEW HELPER: Format historical agent message content ---
        def format_historical_agent_content(content)
          display_content = ""
          if content.is_a?(Hash) && content.key?(:status)
            case content[:status]
            when :success
              display_content = content[:result]
            when :error
              original_error = content[:error_message] || "Agent error (no message)"
              if original_error == "I cannot fulfill this request with the available tools (empty plan)."
                display_content = "Sorry, I couldn't determine how to handle that request with the tools I have available."
              else
                display_content = original_error
              end
            when :pending
              display_content = "Task pending... Job ID: #{content[:job_id]}"
              if content[:message] then display_content << " - #{content[:message]}"; end
            else # Unknown status in hash
              display_content = "Agent response (unknown status): #{content.inspect}"
            end
          elsif content.is_a?(Array) # Handle array case if needed, or show inspect
            display_content = "Agent response (array): #{content.inspect}"
          else # Simple string or other type
            display_content = content.to_s
          end
          # Return the formatted string (ensure it's a string)
          display_content.to_s
        end
        # --- END NEW HELPER ---

        # --- NEW HELPER: Pretty Print JSON ---
        # --- MODIFIED: Accepts Ruby object, not just JSON string ---
        def pretty_json(object)
          begin
            JSON.pretty_generate(object)
          rescue => e # Catch errors during generation (like NestingError)
            # Fallback to inspect on error
            object.inspect
          end
        end
        # --- END NEW HELPER ---
      end # end helpers

      # --- Routes ---
      # Defines the HTTP endpoints for the web application.

      # --- Agent Definition Management Routes (Redis Persistence) --- MOVED
      # All routes previously under this heading have been moved to agent_definition_routes.rb
      # This includes:
      # GET /agents
      # POST /agents
      # DELETE /agents/:name
      # GET /agents/:name
      # GET /agents/:name/edit/:field
      # PUT /agents/:name/update/:field
      # GET /agents/:name/display/:field
      # GET /agents/:name/display/tool_table

      # --- Agent Interaction Routes ---
      get '/agents/:name/chat' do |name|
        # 1. Ensure Definition Store is available
        halt 503, "Definition Store unavailable." unless @definition_store

        # 2. Check if Agent Definition exists
        agent_definition = nil
        begin
          agent_definition = @definition_store.get_definition(name)
        rescue ADK::DefinitionStore::StoreError => e
          logger.error("Store error fetching definition for '#{name}' chat: #{e.message}")
          halt 500, "Error retrieving agent definition."
        end
        unless agent_definition
          logger.warn("Agent definition not found for '#{name}' in store (GET /chat).")
          halt 404,
               slim(:error_404, locals: { title: "Agent Not Found", message: "Definition for '#{name}' not found." })
        end
        agent_description = agent_definition[:description] # Fetch description for display

        # --- ADD: Check running status ---
        is_running = @agents.key?(name)
        # ---------------------------------

        # 3. Manage Session ID
        # --- MODIFIED: Use agent-specific session keys ---
        session[:adk_sessions] ||= {}
        session_id = session[:adk_sessions][name]
        # --- END MODIFICATION ---

        unless session_id && @session_service.get_session(session_id: session_id)
          # Create a new session if needed
          begin
            new_session = @session_service.create_session(app_name: name, user_id: "web_user_#{SecureRandom.hex(4)}")
            session_id = new_session.id
            # --- MODIFIED: Store session ID under agent name key ---
            session[:adk_sessions][name] = session_id # Store in Sinatra session hash
            # --- END MODIFICATION ---
            logger.info("Created new ADK session for agent '#{name}': #{session_id}")
          rescue => e
            logger.error("Failed to create ADK session for agent '#{name}': #{e.message}")
            halt 500, "Failed to initialize chat session."
          end
        end
        logger.debug("Using ADK session ID: #{session_id} for agent '#{name}' chat")

        # 4. Load Chat History
        chat_history = []
        begin
          adk_session_obj = @session_service.get_session(session_id: session_id)
          chat_history = adk_session_obj&.events || []
        rescue => e
          logger.error("Failed to load chat history for session '#{session_id}': #{e.message}")
          # Proceed with empty history
        end

        # 5. Render View
        # --- MODIFIED: Set instance variables instead of locals ---
        @agent_data = { name: name, description: agent_description, running: is_running }
        @session_id = session_id
        @chat_history_events = chat_history
        slim :chat
        # --- END MODIFICATION ---
      end

      post '/agents/:name/chat' do |name|
        content_type :html
        @agent = @agents[name] # Agent must be running
        user_message = params['message']&.strip

        # --- MODIFIED: Fetch agent-specific session ID ---
        session[:adk_sessions] ||= {}
        session_id = session[:adk_sessions][name] # Get session ID from the agent-keyed hash
        # --- END MODIFICATION ---

        # Prepare locals for rendering _chat_message partial
        locals = {
          user_message: user_message || "[Empty Message]",
          agent_result: nil, # Default to nil, populated below
          agent_name: @agent ? @agent.name : name
        }

        # --- Pre-execution checks ---
        unless session_id && @session_service.get_session(session_id: session_id)
          logger.error("Chat POST Error: Missing or invalid session ID (#{session_id}). Redirecting to establish session.")
          session.delete(:adk_session_id) # Clear potentially invalid ID
          redirect "/agents/#{name}/chat" # Redirect to GET
        end
        unless @agent
          locals[:agent_result] = { status: :error, error_message: "[Error: Agent '#{name}' is not running.]" }
          halt 400, slim(:_chat_message, layout: false, locals: locals)
        end
        if user_message.nil? || user_message.empty?
          locals[:agent_result] = { status: :error, error_message: "[Error: Message cannot be empty.]" }
          halt 400, slim(:_chat_message, layout: false, locals: locals)
        end
        # --- End checks ---

        # --- Call Agent ---
        begin
          logger.info("Agent '#{name}' processing chat in session '#{session_id}': #{user_message}")
          final_event_or_error = @agent.run_task(
            session_id: session_id,
            user_input: user_message,
            session_service: @session_service
          )
          logger.info("Agent '#{name}' task processing complete. Final result: #{final_event_or_error.inspect}")
          locals[:agent_result] = final_event_or_error # Pass event/error hash to partial
          slim :_chat_message, layout: false, locals: locals
        rescue => e
          logger.error("Error processing chat for agent #{name}: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
          locals[:agent_result] = { status: :error, error_message: "[Internal Error executing task: #{e.message}]" }
          halt 500, slim(:_chat_message, layout: false, locals: locals)
        end
      end

      post '/agents/:name/execute' do
        name = params[:name]; content_type :json # <--- Change default content_type to json for this route
        agent = @agents[name]

        html_error = lambda do |message, code = 400|
          trigger_event = (code == 400) ? 'showTaskError' : 'showTaskServerError' # Use different events
          # --- Set HX header to trigger JS event ---
          headers 'HX-Trigger-After-Swap' => trigger_event
          # --- Return 200 OK with JSON error message ---
          halt 200, json(error: message) # Halt stops execution
        end

        # Define success handler separately for clarity
        html_success = lambda do |result_hash|
          # Format result, return 200 OK with HTML body
          format_execution_result_html(result_hash)
        end

        html_error.call("Error: Agent '#{name}' not found or not running.", 400) unless agent
        json_string = params['task_json'];
        html_error.call("Error: Missing 'task_json' data.", 400) unless json_string && !json_string.empty?

        # --- Parse and Determine Execution Path ---
        task_description = nil
        parameters = nil
        tool_name_to_execute = nil
        begin
          data = JSON.parse(json_string)
          if data.is_a?(Hash)
            # Check for direct execution format first
            if data.key?('tool_name') && data.key?('task') && data.key?('parameters')
              tool_name_to_execute = data['tool_name']&.strip
              task_description = data['task'] # Still grab task description if present
              parameters = data['parameters']
              html_error.call("Error: Missing 'tool_name' in JSON for direct execution.",
                              400) if tool_name_to_execute.nil? || tool_name_to_execute.empty?
              html_error.call("Error: Missing or invalid 'parameters' object in JSON for direct execution.",
                              400) unless parameters.is_a?(Hash)
            # Check for standard task format
            elsif data.key?('task')
              task_description = data['task']
              # Check for unexpected extra keys if not direct execution
              unless (data.keys - ['task']).empty?
                html_error.call(
                  "Error: Invalid JSON structure. Use either {'task': '...'} or {'tool_name': '...', 'task': '...', 'parameters': {...}}.", 400
                )
              end
            else # Hash doesn't match expected structures
              html_error.call("Error: Invalid JSON structure. Missing required 'task' key.", 400)
            end
          else # Not a hash
            html_error.call("Error: Input must be a JSON object.", 400)
          end
        rescue JSON::ParserError => e
          # JSON parsing failed
          logger.warn("Invalid JSON submitted to /execute: #{e.message}. Input: #{json_string}")
          html_error.call("Error: Invalid JSON format - #{e.message}", 400)
        end
        # Ensure task description is present if we fell through to planning mode
        html_error.call("Error: Missing task description.",
                        400) if tool_name_to_execute.nil? && (task_description.nil? || task_description.empty?)
        # -------------------------------------

        # --- Execute based on path ---
        temp_session = nil
        begin
          if tool_name_to_execute
            # --- Direct Tool Execution ---
            logger.info("Agent '#{name}' executing DIRECT tool '#{tool_name_to_execute}' with params: #{parameters.inspect}")
            tool_instance = agent.find_tool(tool_name_to_execute.to_sym)
            html_error.call("Error: Tool '#{tool_name_to_execute}' not configured for agent '#{name}'.",
                            400) unless tool_instance
            temp_session = @session_service.create_session(app_name: name, user_id: "web_direct_#{SecureRandom.hex(4)}")
            tool_context = ADK::ToolContext.new(
              session_id: temp_session.id,
              user_id: temp_session.user_id,
              app_name: temp_session.app_name,
              tool_registry: agent.tool_registry
            )
            result_hash = tool_instance.execute(parameters.transform_keys(&:to_sym), tool_context)
            # --- Call success lambda for HTML response ---
            html_success.call(result_hash)
          else
            # --- Standard Planning Execution ---
            logger.info("Agent '#{name}' executing task via PLANNER: #{task_description}")
            temp_session = @session_service.create_session(app_name: name, user_id: "web_direct_#{SecureRandom.hex(4)}")
            final_event_or_error = agent.run_task(
              session_id: temp_session.id,
              user_input: task_description,
              session_service: @session_service
            )
            logger.info("Agent '#{name}' planning execution result: #{final_event_or_error.inspect}")
            content_to_display = final_event_or_error.is_a?(ADK::Event) ? final_event_or_error.content : final_event_or_error
            # --- Call success lambda for HTML response ---
            html_success.call(content_to_display)
          end
        rescue => e
          # --- Use single quotes for the outer string to avoid escape sequence conflicts ---
          logger.error 'Error during agent execution for \'#{name}\': #{e.class} - #{e.message}\n' + e.backtrace.join("\n")
          # --- Use the error lambda, passing 500 for internal errors ---
          html_error.call("Error: Internal server error during task execution: #{e.message}", 500)
        ensure
          @session_service.delete_session(session_id: temp_session.id) if temp_session
        end
      end
      
      get '/agents/:name/generate_example_task' do |name|
        content_type :json # Default response type
        logger.info("Received request to generate example task for agent: #{name}")

        # --- 1. Fetch Agent Definition using Store ---
        halt 503, json(error: "Definition Store unavailable.") unless @definition_store
        agent_definition = nil
        begin
          agent_definition = @definition_store.get_definition(name)
        rescue ADK::DefinitionStore::StoreError => e
          logger.error("Store error fetching definition for '#{name}' (generate task): #{e.message}")
          halt 500, json(error: "Error retrieving agent definition.")
        end

        unless agent_definition
          logger.warn("Agent definition not found for '#{name}' in store (generate task).")
          halt 404, json(error: "Agent definition not found for '#{name}'")
        end

        # Extract data (symbol keys)
        agent_model = agent_definition[:model]
        configured_tool_names = agent_definition[:tools] # Array of strings
        mcp_servers_json = agent_definition[:mcp_servers_json]
        # --- END Fetch ---

        # Convert to symbols for processing tool metadata
        configured_tool_syms = configured_tool_names.map(&:to_sym)

        if configured_tool_syms.empty? && mcp_servers_json == '[]'
          return json(example: { task: "Agent '#{name}' has no tools configured. Cannot generate example." })
        end

        # --- 2. Get All Available Tool Metadata (Native + MCP) ---
        # (This logic is similar to GET /agents/:name, could potentially be refactored)
        # Native
        all_native_tools_metadata = ADK::GlobalToolManager.list_all_tools.map do |tool_meta|
          # <<< START CHANGE: Convert native params hash to array >>>
          parameters_array = []
          if tool_meta[:parameters].is_a?(Hash) && !tool_meta[:parameters].empty?
            tool_meta[:parameters].each do |param_name, details|
              parameters_array << {
                name: param_name,
                type: details[:type],
                description: details[:description],
                required: details[:required]
              }
            end
          end
          # <<< END CHANGE >>>
          tool_meta.merge(parameters: parameters_array, source: :native, source_detail: "Native") # Use the converted array
        end

        # MCP
        mcp_configs = []
        begin
          mcp_configs = JSON.parse(mcp_servers_json) if mcp_servers_json && !mcp_servers_json.empty? && mcp_servers_json != '[]'
        rescue JSON::ParserError => e
          logger.error("Invalid JSON in mcp_servers_json for agent '#{name}' (generate task): #{e.message}")
        end
        mcp_tool_results = fetch_mcp_tools(mcp_configs)

        all_mcp_tools_metadata = []
        mcp_tool_results.each do |result|
          next unless result[:status] == :success && result[:tools]

          result[:tools].each do |mcp_tool_hash|
            parameters = []
            begin
              input_schema = mcp_tool_hash[:inputSchema]
              if input_schema && input_schema.is_a?(Hash)
                properties = input_schema['properties'] || {}
                required = input_schema['required'] || []
                parameters = ADK::Mcp::Util::SchemaConverter.json_to_adk(properties, required)
              end
            rescue => e
              logger.error("Error converting MCP schema for tool '#{mcp_tool_hash[:name]}' (generate task): #{e.message}")
            end
            all_mcp_tools_metadata << {
              name: mcp_tool_hash[:name].to_sym,
              description: mcp_tool_hash[:description] || '',
              parameters: parameters,
              source: :mcp,
              source_detail: "MCP (#{result[:server]})"
            }
          end
        end

        # Combine
        all_available_tools_metadata_map = {}
        (all_native_tools_metadata + all_mcp_tools_metadata).each do |tool_meta|
          all_available_tools_metadata_map[tool_meta[:name]] ||= tool_meta
        end

        # --- 3. Filter by Configured Symbols ---
        configured_tools_metadata = configured_tool_syms.map do |tool_sym|
          all_available_tools_metadata_map[tool_sym]
        end.compact

        # (Removed potentially flawed re-selection logic from previous version)

        if configured_tools_metadata.empty?
          return json(example: { task: "Agent '#{name}' has tools configured, but metadata couldn't be retrieved. Cannot generate example." })
        end

        logger.debug("Metadata for example generation: #{configured_tools_metadata.inspect}")

        # --- 4. Construct Prompt for Gemini ---
        tool_details = configured_tools_metadata.map do |metadata|
          params_string = if metadata[:parameters].is_a?(Array) && !metadata[:parameters].empty?
                            metadata[:parameters].map { |p|
                              # <<< CHANGE: Add required/optional status >>>
                              "#{p[:name]} (#{p[:type]}, #{p[:required] ? 'required' : 'optional'})"
                            }.join(', ')
                          else
                            'None'
                          end
          "- Tool: #{metadata[:name]}\n  Description: #{metadata[:description]}\n  Parameters: #{params_string}"
        end.join("\n")

        prompt = <<~PROMPT
          Based on the following tools configured for an agent, generate a single, simple example JSON object representing a task that uses ONE of these tools.#{' '}

          The JSON object MUST follow this exact structure:#{' '}
          { "tool_name": "chosen_tool_name", "task": "A brief description of what the example task does", "parameters": { /* parameters for the chosen tool */ } }

          **Instructions for choosing a tool and generating parameters:**
          1.  ** You can pick any tool you want. Do not pick the calculator or cat fact tool every time if others are available. **
          2.  If multiple tools have required parameters, choose one that seems suitable for a simple example.
          3.  If no tools have required parameters, you may choose a tool with only optional parameters or one with no parameters.
          4.  If the chosen tool has parameters (required or optional), populate the `parameters` object in the JSON with plausible example values matching their specified types and descriptions.
          5.  **Crucially, if the chosen tool has REQUIRED parameters, the generated `parameters` object MUST include ALL of those required parameters.**
          6.  If the chosen tool has no parameters, the `parameters` object MUST be empty: {}.
          7.  The `task` description should briefly explain what the example task does.
          8.  Include the chosen tool's exact name in the `tool_name` field.

          Return ONLY the raw JSON object string. Do not include any other text, explanations, markdown formatting like ```json, or anything else.

          Available Tools:
          ---
          #{tool_details}
          ---
          You should generate engaging examples!
          Generate the example JSON object now:
        PROMPT
        logger.debug("Prompt for Gemini Example Generation:\n#{prompt}") # Keep log for debugging prompt issues

        # --- 5. Call Gemini API ---
        generated_json_string = nil
        begin
          api_key = ENV['GOOGLE_API_KEY']
          unless api_key && !api_key.empty?
            logger.error("GOOGLE_API_KEY not found. Cannot generate example.")
            halt 503, json(error: "AI service API key not configured.")
          end

          # --- Use the fetched agent model ---
          logger.info("Using model '#{agent_model}' to generate example task.")

          temp_gemini_client = Gemini.new(
            credentials: { service: 'generative-language-api', api_key: api_key },
            options: { model: agent_model, server_sent_events: false }
          )

          response = temp_gemini_client.generate_content(
            { contents: [{ role: 'user', parts: { text: prompt } }] }
          )

          generated_json_string = response.dig('candidates', 0, 'content', 'parts', 0, 'text')

          unless generated_json_string && !generated_json_string.strip.empty?
            logger.error("Gemini response was empty or missing text content.")
            halt 500, json(error: "AI service returned an empty response.")
          end
          logger.debug("Raw response from Gemini: #{generated_json_string}")

          # Clean potential markdown fences
          clean_json_string = generated_json_string.strip
          if clean_json_string.start_with?('```json') && clean_json_string.end_with?('```')
            clean_json_string = clean_json_string.delete_prefix('```json').delete_suffix('```').strip
          elsif clean_json_string.start_with?('```') && clean_json_string.end_with?('```')
            clean_json_string = clean_json_string.delete_prefix('```').delete_suffix('```').strip
          end

          # --- 6. Validate & Return Response ---
          begin
            parsed_json = JSON.parse(clean_json_string)
            unless parsed_json.is_a?(Hash) && parsed_json.key?('tool_name') && parsed_json.key?('task') && parsed_json.key?('parameters')
              raise JSON::ParserError, "Generated JSON missing required 'tool_name', 'task' or 'parameters' keys."
            end

            return JSON.pretty_generate(parsed_json)
          rescue JSON::ParserError => e
            logger.error("Gemini generated invalid/unexpected JSON: #{e.message}. Cleaned Response: #{clean_json_string}")
            halt 500, json(error: "Failed to generate valid JSON example from AI.")
          end
        rescue StandardError => e # Catch other API/client errors
          logger.error("Error calling Gemini API: #{e.class} - #{e.message}")
          logger.error(e.backtrace.first(5).join("\n"))
          error_message = if e.message.downcase.include?('authenticat') || e.message.include?('API key')
                            "AI service authentication failed. Check API key."
                          else
                            "Error communicating with AI service."
                          end
          halt 503, json(error: error_message)
        end
      end
      # --- END generate_example_task Route ---

      # --- Agent Runtime Control Routes --- MOVED 
      # POST /agents/:name/start/detail - MOVED to agent_runtime_routes.rb
      # POST /agents/:name/stop/detail - MOVED to agent_runtime_routes.rb
      # (The /agents/:name/start and /agents/:name/stop routes for main list are also in agent_runtime_routes.rb)

      # --- API Endpoints (JSON) --- MOVED
      # GET /api/agents - MOVED to api_routes.rb
      # GET /api/tools - MOVED to api_routes.rb

      # --- Tools Page Routes --- MOVED
      # GET /tools - MOVED to tools_ui_routes.rb
      # GET /tools/:name - MOVED to tools_ui_routes.rb

      # --- Private Helper Methods ---
      private

      def _stop_agent(name)
        agent = @agents[name]
        if agent
          logger.info("Stopping agent '#{name}'...")
          begin
            agent.stop
            @agents.delete(name)
            logger.info("Agent '#{name}' stopped.")
            true
          rescue => e
            logger.error("Error stopping agent '#{name}': #{e.message}")
            false # Indicate error
          end
        else
          logger.warn("Attempted to stop non-running agent: '#{name}'.")
          true # Considered success as it's already stopped
        end
      end

      def _start_agent(name)
        return @agents[name] if @agents.key?(name) # Already running

        # --- MODIFIED: Use Definition Store ---
        halt 503, "Definition Store unavailable." unless @definition_store
        agent_definition = nil
        begin
          agent_definition = @definition_store.get_definition(name)
        rescue ADK::DefinitionStore::StoreError => e
          logger.error("Store error fetching definition for starting agent '#{name}': #{e.message}")
          return nil # Failed to start
        end

        unless agent_definition
          logger.error("Agent definition not found for '#{name}', cannot start.")
          return nil # Failed to start
        end

        # Extract data from definition hash (symbol keys)
        agent_description = agent_definition[:description]
        selected_tool_names = agent_definition[:tools].map(&:to_sym) # Agent expects symbols
        model_name = agent_definition[:model]
        fallback_mode_sym = agent_definition[:fallback_mode] # Already symbol
        mcp_servers_json = agent_definition[:mcp_servers_json]
        # --- END MODIFICATION ---

        # --- FIXED: Parse MCP JSON before counting for logging ---
        mcp_server_count = 0
        begin
          parsed_mcp = JSON.parse(mcp_servers_json)
          mcp_server_count = parsed_mcp.is_a?(Array) ? parsed_mcp.count : 0
        rescue JSON::ParserError
          # Keep count 0 if JSON is invalid
        end
        logger.info("Attempting to start agent '#{name}' (Model: #{model_name}, Fallback: #{fallback_mode_sym}, MCP: #{mcp_server_count} servers)... Selected Tools: #{selected_tool_names.inspect}")
        # --- END FIX ---
        agent = ADK::Agent.new(
          name: name, description: agent_description, model_name: model_name,
          fallback_mode: fallback_mode_sym,
          mcp_servers: mcp_servers_json,
          selected_tool_names: selected_tool_names
        )

        # --- Add explicitly configured NATIVE tools ---
        # MCP tools are registered during agent.start -> discover_and_register_mcp_tools
        selected_tool_names.each do |tn|
          # Check if this selected tool is a known NATIVE tool
          inst = ADK::GlobalToolManager.create_instance(tn)
          if inst
            logger.debug("Adding selected native tool: #{tn}")
            agent.add_tool(inst)
          else
            # Assuming it's an intended MCP tool, do nothing here.
            # It will be registered later if available on the server and selected.
            logger.debug("Tool '#{tn}' selected but not found in GlobalToolManager (assuming MCP tool).")
          end
        end

        agent.start
        @agents[name] = agent
        logger.info("Agent '#{name}' started successfully.")
        agent # Return the agent instance
      rescue StandardError => e
        logger.error("Failed to start agent '#{name}': #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        @agents.delete(name) # Clean up if partially added
        nil # Failed to start
      end
    end # End App class
  end # End Web module
end # End ADK module
