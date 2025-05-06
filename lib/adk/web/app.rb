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

      # --- Agent Definition Management Routes (Redis Persistence) ---
      # These routes handle CRUD operations for agent *definitions*, which are stored in Redis.

      # GET /agents - Display the main agent management page.
      # Lists all agents defined in Redis, showing their status (Running/Stopped)
      # and providing controls to create, manage, and start/stop agents.
      get '/agents' do
        @view_agents = []
        if @definition_store
          begin
            agent_summaries = @definition_store.list_definitions
            # @logger.debug("[GET /agents] Summaries from store: #{agent_summaries.inspect}") # <<< REMOVE LOGGING

            @view_agents = agent_summaries.map do |summary|
              agent_name = summary[:name]
              is_running = @agents.key?(agent_name)
              # @logger.debug("[GET /agents] Processing summary for '#{agent_name}' BEFORE rename: #{summary.inspect}") # <<< REMOVE LOGGING
              summary[:configured_tools] = summary.delete(:tools)
              # @logger.debug("[GET /agents] Processing summary for '#{agent_name}' AFTER rename: #{summary.inspect}") # <<< REMOVE LOGGING
              summary.merge(running: is_running)
            end
          rescue ADK::DefinitionStore::StoreError => e
            logger.error("Store error fetching agent list: #{e.message}")
          end
        else
          logger.error("Definition Store unavailable during GET /agents")
        end
        # @logger.debug("[GET /agents] Final @view_agents: #{@view_agents.inspect}") # <<< REMOVE LOGGING
        @available_tools = ADK::GlobalToolManager.list_all_tools
        @available_models = AVAILABLE_MODELS
        slim :agents
      end

      # POST /agents - Create a new agent definition in Redis.
      # Receives form data (name, description, tools, model, fallback, MCP config),
      # validates input, and saves the definition as a hash in Redis.
      # Also adds the agent name to the central set of agent names.
      # Returns HTML fragments for the new agent row and potentially removes the
      # "no agents" message via HTMX OOB swap.
      post '/agents' do
        halt 503, "Redis unavailable." unless @definition_store
        agent_name = params['name']&.strip; agent_description = params['description']&.strip
        selected_tools = params['tools'] || []; selected_model = params['model']&.strip
        selected_fallback = params['fallback_mode'] || 'error'
        mcp_servers_json = params['mcp_servers_json']&.strip
        instruction = params['instruction']&.strip # <<< Get instruction

        mcp_servers_json_to_save = (mcp_servers_json.nil? || mcp_servers_json.empty?) ? '[]' : mcp_servers_json
        model_to_save = selected_model && !selected_model.empty? ? selected_model : ADK::Agent::DEFAULT_MODEL

        if agent_name.nil? || agent_name.empty? || agent_description.nil? || agent_description.empty?
          status 400; halt "<div class='notification is-danger'>Name and description required.</div>"; end

        begin
          @definition_store.save_definition(
            name: agent_name,
            description: agent_description,
            tools: selected_tools,
            model: model_to_save,
            fallback_mode: selected_fallback,
            mcp_servers_json: mcp_servers_json_to_save,
            instruction: instruction # <<< Pass instruction
          )
          logger.info("Agent '#{agent_name}' definition saved (Model: #{model_to_save}, Tools: #{selected_tools}, Fallback: #{selected_fallback}, MCP: #{!mcp_servers_json_to_save.empty? && mcp_servers_json_to_save != '[]'}, Instruction: #{!instruction.nil? && !instruction.empty?})") # Log instruction status
        rescue ADK::DefinitionStore::StoreError => e
          logger.error("Store error saving agent definition: #{e.message}")
          halt 500, "Error saving agent definition."
        end
        content_type :html
        # <<< Add instruction to data passed to partial if needed by _agent_row >>>
        agent_data = { name: agent_name, description: agent_description, running: false,
                       configured_tools: selected_tools, model: model_to_save, fallback_mode: selected_fallback, instruction: instruction,
                       is_new: true } # <<< ADDED is_new flag
        available_tools = ADK::GlobalToolManager.list_all_tools
        agent_row_html = slim(:_agent_row, layout: false,
                                           locals: { agent_info: agent_data, available_tools: available_tools })
        oob_remove_message_html = "<tr id='no-agents-row' hx-swap-oob='true'></tr>"

        # Trigger event to close the details section on the client
        headers 'HX-Trigger' => 'closeCreateAgentForm'

        agent_row_html + oob_remove_message_html
      end

      # DELETE /agents/:name - Delete an agent definition from Redis.
      # Stops the agent runtime instance if it's currently running.
      # Removes the agent's definition hash and its name from the set in Redis.
      # Returns an empty 200 OK response, triggering HTMX to remove the corresponding row.
      delete '/agents/:name' do |name|
        logger.info("Received request to delete agent '#{name}'")
        halt 503, "Definition Store unavailable." unless @definition_store
        if @agents.key?(name)
          logger.info("Stopping running agent '#{name}' before deletion...")
          begin @agents[name].stop;
                @agents.delete(name);
                logger.info("Agent '#{name}' stopped.");
          rescue => e; logger.error("Error stopping agent: #{e.message}"); end
        end
        begin
          @definition_store.delete_definition(name)
          logger.info("Agent '#{name}' definition deleted from Redis.")
          status 200; body ''
        rescue ADK::DefinitionStore::StoreError => e
          logger.error("Store error deleting agent '#{name}': #{e.message}");
          halt 500, "Database error during deletion."; end
      end

      # GET /agents/:name - Display the detail page for a specific agent.
      # Fetches the agent's definition from Redis.
      # Fetches metadata for available native tools (from GlobalToolManager) and
      # remote MCP tools (using fetch_mcp_tools helper based on agent's MCP config).
      # Displays the combined list of tools *configured* for this agent.
      # Shows agent details, runtime status, chat link, and task execution controls.
      # Implicitly adds 'check_job_status' tool to the view if any configured tool is async.
      get '/agents/:name' do |name|
        # --- MODIFIED: Use Definition Store ---
        halt 503, "Definition Store unavailable." unless @definition_store
        agent_definition = nil
        begin
          agent_definition = @definition_store.get_definition(name)
        rescue ADK::DefinitionStore::StoreError => e
          logger.error("Store error fetching definition for '#{name}': #{e.message}")
          halt 500, "Error retrieving agent definition."
        end

        unless agent_definition
          logger.warn("Agent definition not found for '#{name}' in store.")
          halt 404,
               slim(:error_404, locals: { title: "Agent Not Found", message: "Definition for '#{name}' not found." })
        end

        # Extract data from the definition hash (store returns symbol keys)
        description = agent_definition[:description]
        configured_tool_names = agent_definition[:tools] # Array of strings
        loaded_model = agent_definition[:model]
        fallback_mode = agent_definition[:fallback_mode] # Symbol
        mcp_servers_json = agent_definition[:mcp_servers_json] # String
        instruction = agent_definition[:instruction]

        # --- NEW: Pre-process MCP JSON for display ---
        mcp_display_string = begin
          parsed = JSON.parse(mcp_servers_json)
          if parsed.is_a?(Array) && parsed.empty?
            "No MCP Server(s) Configured."
          else
            pretty_json(parsed) # Assumes pretty_json helper is available
          end
        rescue JSON::ParserError
          mcp_servers_json # Fallback to raw string on error
        end
        # --- END Pre-processing ---

        is_running = @agents.key?(name)

        # --- START: Refactored Tool Metadata Fetching (Copied from GET /display/tool_table) ---

        # 1. Get NATIVE tool info from registry and format parameters/source
        all_native_tools_metadata = ADK::GlobalToolManager.list_all_tools.map do |tm|
          parameters_array = []
          # Convert native params hash to array format
          if tm[:parameters].is_a?(Hash) && !tm[:parameters].empty?
            tm[:parameters].each do |param_name, details|
              parameters_array << {
                name: param_name,
                type: details[:type],
                description: details[:description],
                required: details[:required]
              }
            end
          end
          tm.merge(parameters: parameters_array, source: :native, source_detail: "Native")
        end

        # 2. Fetch MCP tool results and convert parameters/mark source
        # mcp_servers_json is already fetched above
        mcp_configs = []
        begin
          mcp_configs = JSON.parse(mcp_servers_json) if mcp_servers_json && !mcp_servers_json.empty? && mcp_servers_json != '[]'
        rescue JSON::ParserError => e
          logger.error("Invalid JSON in mcp_servers_json for agent '#{name}' (GET /agents/:name): #{e.message}")
          mcp_configs = [] # Continue without MCP if JSON is invalid
        end
        mcp_tool_results = fetch_mcp_tools(mcp_configs) # Contains raw results and status

        fetched_mcp_tools_metadata = []
        mcp_tool_results.each do |result|
          if result[:status] == :success && result[:tools]
            result[:tools].each do |mcp_tool_schema|
              parameters = []
              begin
                input_schema = mcp_tool_schema[:inputSchema]
                if input_schema && input_schema.is_a?(Hash)
                  properties = input_schema['properties'] || {}
                  required = input_schema['required'] || []
                  # Use SchemaConverter here
                  parameters = ADK::Mcp::Util::SchemaConverter.json_to_adk(properties, required)
                end
              rescue => e
                logger.error("Error converting MCP schema for tool '#{mcp_tool_schema[:name]}' (GET /agents/:name): #{e.message}")
              end
              fetched_mcp_tools_metadata << { name: mcp_tool_schema[:name].to_sym,
                                              description: mcp_tool_schema[:description] || "",
                                              parameters: parameters, # Use converted params
                                              source: :mcp,
                                              source_detail: "MCP (#{result[:server]})" } # Include server source
            end
          end
        end

        # 3. Merge native and processed MCP metadata into a single map
        all_available_tools_metadata_map = {}
        (all_native_tools_metadata + fetched_mcp_tools_metadata).each do |tm|
          all_available_tools_metadata_map[tm[:name]] ||= tm # Prioritize native if name collision
        end

        # 4. Filter map by configured symbols
        configured_tool_syms = configured_tool_names.map(&:to_sym) # Convert strings to symbols
        view_configured_tools = configured_tool_syms.map do |tool_sym|
          all_available_tools_metadata_map[tool_sym]
        end.compact # Remove nil entries if a configured tool wasn't found in the merged map

        # 5. Handle Implicit Tool Addition
        # Check if *any* of the *configured* tools (using the filtered list) might require check_job_status
        # (Simplified check: Look for async flag in metadata if available, or class check if needed)
        needs_check_job_status = view_configured_tools.any? do |tm|
          tm[:async] == true || ADK::GlobalToolManager.find_class(tm[:name])&.ancestors&.include?(ADK::Tools::BaseAsyncJobTool)
        end

        if needs_check_job_status && !view_configured_tools.any? { |t| t[:name] == :check_job_status }
          status_tool_meta = all_available_tools_metadata_map[:check_job_status]
          if status_tool_meta
            # Add note that it was implicitly added
            status_tool_meta_clone = status_tool_meta.dup
            status_tool_meta_clone[:description] = "(Implicitly added) #{status_tool_meta_clone[:description]}"
            status_tool_meta_clone[:source_detail] = "Native (Implicit)" # Clarify source
            view_configured_tools << status_tool_meta_clone
            logger.debug("Implicitly added check_job_status tool to view for agent '#{name}'")
          end
        end
        # Sort the final list for consistent display
        view_configured_tools.sort_by! { |t| t[:name].to_s }

        # --- END: Refactored Tool Metadata Fetching ---

        # --- Assemble data for the view ---
        @view_agent_data = {
          name: name,
          description: description,
          running: is_running,
          model: loaded_model,
          fallback_mode: fallback_mode,
          instruction: instruction,
          mcp_servers_json: mcp_servers_json,
          mcp_display_string: mcp_display_string,
          configured_tool_names: configured_tool_names # Needed for edit forms
        }

        # --- Render the main agent view ---
        slim :agent, locals: {
          view_configured_tools: view_configured_tools,
          mcp_tool_results: mcp_tool_results # Pass MCP results hash for potential errors
          # @session_id and @chat_history_events are now available as instance vars
        }
      end

      # GET /agents/:name/chat - Display the chat interface for an agent.
      # Establishes a user session and loads existing chat history.
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

      # POST /agents/:name/chat - Process a user message from the chat interface.
      # Requires the agent to be running and a valid ADK session ID in the Sinatra session.
      # Retrieves the message from the form data.
      # Calls the agent's `run_task` method, passing the user input and session ID.
      # The `run_task` method handles planning, tool execution, and updating the session history.
      # Returns an HTML fragment (`_chat_message.slim`) containing the user message
      # and the agent's processed response, intended for HTMX append swap into the chat log.
      post '/agents/:name/chat' do |name| # <<< ENSURE THIS LINE EXISTS AND IS CORRECT
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

      # POST /agents/:name/execute - Execute a task directly via JSON input.
      # Requires the agent to be running. Bypasses the chat UI and session history persistence.
      # Accepts a JSON payload in the `task_json` form field. Supports two formats:
      # 1. Planner execution: `{"task": "User's natural language task description"}`
      # 2. Direct tool execution: `{"tool_name": "tool_symbol", "task": "Optional task description", "parameters": {"param1": "value1", ...}}`
      # Creates a temporary ADK session for the execution context.
      # If direct execution: Finds the specified tool, creates a ToolContext, and calls `tool.execute`.
      # If planner execution: Calls `agent.run_task` with the task description.
      # Returns:
      #   - Success (200 OK): HTML body containing the formatted result (using `format_execution_result_html`). Target element updated via HTMX.
      #   - Input Error (200 OK + JSON): `{"error": "..."}`. Triggers `showTaskError` JS event via `HX-Trigger-After-Swap`.
      #   - Server Error (200 OK + JSON): `{"error": "..."}`. Triggers `showTaskServerError` JS event via `HX-Trigger-After-Swap`.
      # Note: Returning 200 OK even for errors allows HTMX to process the response and trigger events.
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

      # --- ADDED START: Missing stop/detail route ---
      # POST /agents/:name/stop/detail - Stop a runtime instance (from agent detail view).
      # Calls the `_stop_agent` helper method.
      # Returns the `_agent_status_controls.slim` partial for the detail view's status section,
      # plus OOB swap fragments to disable/update the "Execute Task" button, chat input/button, and chat help text.
      post '/agents/:name/stop/detail' do |name|
        content_type :html
        stop_success = _stop_agent(name) # <<< Use helper

        # Fetch definition to render the status controls correctly
        agent_definition = nil
        agent_data_for_view = nil
        if @definition_store
          begin
            agent_definition = @definition_store.get_definition(name)
            if agent_definition
              # Construct hash expected by the partial
              agent_data_for_view = {
                name: name,
                description: agent_definition[:description],
                running: false, # Always show as stopped
                model: agent_definition[:model]
                # Add other fields if the partial needs them, e.g., :fallback_mode, :mcp_servers_json
              }
            else
              agent_data_for_view = { name: name, description: "Error: Definition not found", running: false,
                                      model: "N/A" }
            end
          rescue ADK::DefinitionStore::StoreError => e
            logger.error("Store error fetching definition after stop detail for '#{name}': #{e.message}")
            agent_data_for_view = { name: name, description: "Error retrieving definition", running: false,
                                    model: "N/A" }
          end
        else
          agent_data_for_view = { name: name, description: "Error: Store unavailable", running: false, model: "N/A" }
        end

        # Render the status controls partial
        status_controls_html = slim(:_agent_status_controls, layout: false, locals: { agent_data: agent_data_for_view })

        # Construct the OOB button HTML (always disabled after stop)
        execute_button_oob_html = %(
          <button class="button is-primary" id="execute-task-button" type="submit" disabled hx-swap-oob="true">
            <span class="icon is-small"><i class="fas fa-play-circle"></i></span>
            <span>Execute (Requires Start)</span>
          </button>
        )

        # --- NEW: Add OOB swaps for chat elements (always disabled) ---
        chat_input_oob_html = %(
          <input class="input" id="chat-input" type="text" name="message" placeholder="Enter your message..." required="true" autofocus disabled hx-swap-oob="true">
        )
        chat_button_oob_html = %(
          <button class="button is-info" id="send-button" type="submit" disabled hx-swap-oob="true">
            <span>Send</span>
            <span class="icon is-small htmx-indicator ml-2" id="send-button-indicator"><i class="fas fa-spinner fa-pulse"></i></span>
          </button>
        )
        # --- END NEW OOB swaps ---

        # --- NEW: OOB swap for chat help text (show on stop by replacing p tag) ---
        chat_help_oob_html = %(<p id="chat-status-help" hx-swap-oob="outerHTML" class="help is-danger">Agent must be running to chat.</p>)
        # --- END NEW OOB swap ---

        # Return combined HTML
        status 200
        status_controls_html + execute_button_oob_html + chat_input_oob_html + chat_button_oob_html + chat_help_oob_html
      end
      # --- ADDED END ---

      # --- API Endpoints (JSON) ---
      # Provide simple JSON data about the system state.

      # GET /api/agents - MOVED to api_routes.rb

      # GET /api/tools - MOVED to api_routes.rb

      # --- NEW: Tools Page Route ---
      # GET /tools - MOVED to tools_ui_routes.rb

      # --- NEW: Tool Detail Page Route ---
      # GET /tools/:name - MOVED to tools_ui_routes.rb

      # --- Private Helper Methods ---
      private

      # Stops a running agent instance and removes it from the in-memory @agents hash.
      # @param name [String] The name of the agent to stop.
      # @return [Boolean] True if the agent was stopped successfully or was already stopped, false if an error occurred during stopping.
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

      # Starts an agent instance based on its definition stored in Redis.
      # If the agent is already running, returns the existing instance.
      # Fetches configuration (description, tools, model, fallback, MCP) from Redis.
      # Instantiates `ADK::Agent`, adds configured native tools, calls `agent.start`
      # (which handles MCP tool registration), and stores the instance in @agents.
      # @param name [String] The name of the agent to start.
      # @return [ADK::Agent, nil] The started (or already running) agent instance, or nil if starting failed (e.g., definition not found, error during initialization).
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

      # For 'tools', it fetches all available native and MCP tools to populate the selector.
      get '/agents/:name/edit/:field' do |name, field|
        supported_fields = ['description', 'model', 'tools', 'fallback', 'mcp', 'instruction'] # <<< Added instruction
        halt 404, "Editing field '#{field}' not supported." unless supported_fields.include?(field)

        # --- MODIFIED: Use Definition Store ---
        halt 503, "Definition Store unavailable." unless @definition_store
        agent_definition = nil
        begin
          agent_definition = @definition_store.get_definition(name)
        rescue ADK::DefinitionStore::StoreError => e
          logger.error("Store error fetching definition for '#{name}' edit: #{e.message}")
          halt 500, "Error retrieving agent definition for edit."
        end

        unless agent_definition
          logger.warn("Agent definition not found for '#{name}' in store during edit.")
          halt 404 # Or render an error partial
        end

        # Prepare data for the view/locals (uses symbol keys from store)
        agent_data = {
          name: name,
          description: agent_definition[:description],
          model: agent_definition[:model],
          fallback_mode: agent_definition[:fallback_mode], # Symbol
          mcp_servers_json: agent_definition[:mcp_servers_json], # String
          instruction: agent_definition[:instruction] # <<< Add instruction here
        }
        # --- END MODIFICATION ---

        locals = { agent_data: agent_data }

        # Add field-specific data needed by partials
        if field == 'model'
          locals[:available_models] = AVAILABLE_MODELS
        elsif field == 'tools'
          # Tools are already an array of strings from get_definition
          configured_tool_names = agent_definition[:tools]
          locals[:configured_tool_names] = configured_tool_names

          # --- Combine Native and Fetched MCP Tools for display ---
          # 1. Get Native Tools from Global Manager
          native_tools = ADK::GlobalToolManager.list_all_tools

          # 2. Fetch tools from this agent's MCP config
          mcp_servers_json = agent_definition[:mcp_servers_json]
          mcp_configs = []
          begin
            mcp_configs = JSON.parse(mcp_servers_json) if mcp_servers_json && !mcp_servers_json.empty? && mcp_servers_json != '[]'
          rescue JSON::ParserError => e
            logger.error("Invalid JSON in mcp_servers_json while editing tools for agent '#{name}': #{e.message}")
            mcp_configs = []
          end
          mcp_tool_results = fetch_mcp_tools(mcp_configs)

          # 3. Extract successfully fetched MCP tool metadata
          #    (SchemaConverter already converts MCP schema to ADK format needed by edit partial)
          fetched_mcp_tools = []
          mcp_tool_results.each do |result|
            if result[:status] == :success && result[:tools]
              result[:tools].each do |mcp_tool_schema|
                mcp_props = mcp_tool_schema[:inputSchema]['properties'] || {}
                mcp_req = mcp_tool_schema[:inputSchema]['required'] || []
                adk_params = ADK::Mcp::Util::SchemaConverter.json_to_adk(mcp_props, mcp_req)
                fetched_mcp_tools << {
                  name: mcp_tool_schema[:name].to_sym, # Use symbol consistent with native tools
                  description: mcp_tool_schema[:description] || "",
                  parameters: adk_params # Pass the converted params
                }
              end
            end
          end

          # 4. Combine and remove duplicates (prefer native if name clash)
          combined_tools = (native_tools + fetched_mcp_tools).uniq { |tool| tool[:name] }

          # 5. Pass the combined list to the partial
          locals[:all_available_tools] = combined_tools.sort_by { |t| t[:name].to_s }
          # --- END MCP/Native Tool Combining Logic ---

        elsif field == 'mcp'
          # Nothing specific needed for locals for mcp, agent_data has the json
        end

        # Render the correct partial
        slim :"_edit_agent_#{field}", layout: false, locals: locals
      end

      # GET /agents/:name/display/tool_table - Render the tool table display partial.
      # Used by the "Cancel" button in the 'tools' edit view to revert to the display state.
      # Fetches agent definition and tool metadata (native+MCP) similar to the GET /agents/:name route
      # to render the `_agent_tool_table.slim` partial.
      get '/agents/:name/display/tool_table' do |name|
        # --- MODIFIED: Use Definition Store ---
        halt 503, "Definition Store unavailable." unless @definition_store
        agent_definition = nil
        begin
          agent_definition = @definition_store.get_definition(name)
        rescue ADK::DefinitionStore::StoreError => e
          logger.error("Store error fetching definition for '#{name}' tool table: #{e.message}")
          halt 500, "Error retrieving agent definition for tool table."
        end

        unless agent_definition
          logger.warn("Agent definition not found for '#{name}' in store during tool table display.")
          halt 404
        end

        # Extract data from definition hash (symbol keys)
        # --- END MODIFICATION ---

        # --- Use the definition hash ---
        agent_data = {
          name: name,
          description: agent_definition[:description],
          model: agent_definition[:model], # Already has default applied by store
          fallback_mode: agent_definition[:fallback_mode], # Already symbol
          mcp_servers_json: agent_definition[:mcp_servers_json] # Already string
        }
        agent_data[:running] = @agents.key?(name)

        # Get configured tool names (array of strings)
        configured_tool_names = agent_definition[:tools]

        # Convert to symbols for internal processing
        configured_tool_syms = configured_tool_names.map(&:to_sym)

        # --- START: Refactored Tool Metadata Fetching ---

        # 1. Get NATIVE tool info from registry
        all_native_tools_metadata = ADK::GlobalToolManager.list_all_tools.map do |tm|
          tm.merge(source: :native, source_detail: "Native")
        end

        # 2. Fetch MCP tool results and convert parameters
        mcp_servers_json = agent_data[:mcp_servers_json] # Use value from agent_data hash
        mcp_configs = []
        begin
          mcp_configs = JSON.parse(mcp_servers_json) if mcp_servers_json && !mcp_servers_json.empty? && mcp_servers_json != '[]'
        rescue JSON::ParserError => e
          logger.error("Invalid JSON in mcp_servers_json for agent '#{name}' (display table): #{e.message}")
          mcp_configs = [] # Continue without MCP if JSON is invalid
        end
        mcp_tool_results = fetch_mcp_tools(mcp_configs) # Contains raw results and status

        fetched_mcp_tools_metadata = []
        mcp_tool_results.each do |result|
          if result[:status] == :success && result[:tools]
            result[:tools].each do |mcp_tool_schema|
              parameters = []
              begin
                input_schema = mcp_tool_schema[:inputSchema]
                if input_schema && input_schema.is_a?(Hash)
                  properties = input_schema['properties'] || {}
                  required = input_schema['required'] || []
                  parameters = ADK::Mcp::Util::SchemaConverter.json_to_adk(properties, required)
                end
              rescue => e
                logger.error("Error converting MCP schema for tool '#{mcp_tool_schema[:name]}' (display table): #{e.message}")
              end
              fetched_mcp_tools_metadata << { name: mcp_tool_schema[:name].to_sym,
                                              description: mcp_tool_schema[:description] || "",
                                              parameters: parameters,
                                              source: :mcp,
                                              source_detail: "MCP (#{result[:server]})" }
            end
          end
        end

        # 3. Merge native and processed MCP metadata into a single map
        all_available_tools_metadata_map = {}
        (all_native_tools_metadata + fetched_mcp_tools_metadata).each do |tm|
          all_available_tools_metadata_map[tm[:name]] ||= tm # Prioritize native if name collision
        end

        # 4. Filter map by configured symbols
        logger.debug("[Display Tool Table] Configured tool names (symbols): #{configured_tool_syms.inspect}")
        view_configured_tools_list = configured_tool_syms.map do |tool_sym|
          all_available_tools_metadata_map[tool_sym]
        end.compact # Remove nil entries if a configured tool wasn't found in the merged map

        logger.debug("[Display Tool Table] Filtered tool list count: #{view_configured_tools_list.length}")
        # logger.debug("[Display Tool Table] Filtered tool list details: #{view_configured_tools_list.inspect}") # Verbose

        # --- END: Refactored Tool Metadata Fetching ---

        # Implicitly add check_job_status if needed (simplified check as agent not running)
        # Check if *any* of the *configured* tools are async
        if view_configured_tools_list.any? { |tm|
          ADK::GlobalToolManager.find_class(tm[:name])&.ancestors&.include?(ADK::Tools::BaseAsyncJobTool)
        }
          status_tool_meta = all_available_tools_metadata_map[:check_job_status]
          if status_tool_meta && !view_configured_tools_list.any? { |t| t[:name] == :check_job_status }
            view_configured_tools_list << status_tool_meta
            logger.debug("Implicitly added check_job_status tool to view for agent '#{name}'")
          end
        end

        # logger.debug("[Display Tool Table] Final tool list count: #{view_configured_tools_list.length}")

        slim :_agent_tool_table, layout: false, locals: {
          agent_data: agent_data,
          view_configured_tools: view_configured_tools_list,
          mcp_tool_results: mcp_tool_results # Pass raw results for error display in partial
        }
      end

      # to swap the edit form back to the static display view (`_display_agent_*.slim`).
      get '/agents/:name/display/:field' do |name, field|
        supported_fields = ['description', 'model', 'tools', 'fallback', 'mcp', 'instruction'] # <<< Added instruction
        halt 404, "Displaying field '#{field}' not supported." unless supported_fields.include?(field)

        # --- MODIFIED: Use Definition Store ---
        halt 503, "Definition Store unavailable." unless @definition_store
        agent_definition = nil
        begin
          agent_definition = @definition_store.get_definition(name)
        rescue ADK::DefinitionStore::StoreError => e
          logger.error("Store error fetching definition for '#{name}' display: #{e.message}")
          halt 500, "Error retrieving agent definition for display."
        end

        unless agent_definition
          logger.warn("Agent definition not found for '#{name}' in store during display.")
          halt 404
        end
        # --- END MODIFICATION ---

        response_locals = {};
        response_locals[:agent_data] =
          { name: name,
            description: agent_definition[:description],
            model: agent_definition[:model],
            fallback_mode: agent_definition[:fallback_mode], # Symbol
            mcp_servers_json: agent_definition[:mcp_servers_json], # String
            instruction: agent_definition[:instruction] # <<< Add instruction
          }
        # <-------------------------------------------->
        if field == 'tools'
          # Tools are already an array of strings
          configured_tool_names_str = agent_definition[:tools]
          all_tools = ADK::GlobalToolManager.list_all_tools
          response_locals[:configured_tools] = configured_tool_names_str.map { |tn|
            all_tools.find { |t| t[:name].to_s == tn }
          }
        end

        # --- Add specific handling for MCP display ---
        if field == 'mcp'
          mcp_json = agent_definition[:mcp_servers_json]
          mcp_display_string = begin
            parsed = JSON.parse(mcp_json)
            if parsed.is_a?(Array) && parsed.empty?
              "No MCP Server(s) Configured."
            else
              pretty_json(parsed)
            end
          rescue JSON::ParserError
            mcp_json # Fallback
          end
          # <<< Pass the processed string and raw JSON >>>
          response_locals[:agent_data][:mcp_display_string] = mcp_display_string
          response_locals[:agent_data][:mcp_servers_json] = mcp_json # Ensure raw is still there if needed
        elsif field == 'tools'
          # ... tool logic ...
        end
        # --- END MCP Handling ---

        # Explicitly tell the display partial to show the edit button when restoring
        response_locals[:show_edit_button] = true

        # Render the correct partial
        slim :"_display_agent_#{field}", layout: false, locals: response_locals
      end

      # May include an `HX-Trigger-After-Swap` header to show a toast notification
      # on the frontend about the automatic restart (`showRestartToast` or `showRestartErrorToast`).
      put '/agents/:name/update/:field' do |name, field|
        supported_fields = ['description', 'model', 'tools', 'fallback', 'mcp', 'instruction'] # <<< Added instruction
        halt 404, "Updating field '#{field}' not supported." unless supported_fields.include?(field)

        # --- MODIFIED: Use Definition Store ---
        halt 503, "Definition Store unavailable." unless @definition_store

        # Field name mapping for store update (uses string keys internally in store)
        field_to_update = case field
                          when 'fallback' then 'fallback_mode'
                          when 'mcp' then 'mcp_servers_json'
                          else field # Handles description, model, tools, instruction
                          end

        new_value = nil # Holds the validated value to be saved
        # --- END MODIFICATION ---

        response_locals = {} # Locals for rendering success partial
        agent_data_hash = { name: name } # Base hash for success partials

        # --- Handle specific field updates & Validation ---
        if field == 'tools'
          # Fetch current MCP config to validate selected MCP tools
          current_definition = @definition_store.get_definition(name)
          unless current_definition
            # Cannot validate tools without current definition if MCP is used
            logger.error("Cannot update tools for '#{name}', agent definition not found.")
            halt 404, "Agent definition not found, cannot update tools."
          end
          mcp_servers_json = current_definition[:mcp_servers_json]

          # Get all available tool names (Native + MCP based on *current* config)
          native_tools_metadata = ADK::GlobalToolManager.list_all_tools
          native_tool_names = native_tools_metadata.map { |t| t[:name].to_s }
          mcp_configs = []
          begin
            mcp_configs = JSON.parse(mcp_servers_json) if mcp_servers_json && !mcp_servers_json.empty? && mcp_servers_json != '[]'
          rescue JSON::ParserError => e
            logger.error("Invalid current MCP JSON for '#{name}' during tool update validation: #{e.message}")
          end
          mcp_tool_results = fetch_mcp_tools(mcp_configs)
          mcp_tool_names = []
          mcp_tool_results.each do |result|
            if result[:status] == :success && result[:tools]
              mcp_tool_names.concat(result[:tools].map { |t| t[:name].to_s }) # Assuming name is string
            end
          end
          all_valid_tool_names = (native_tool_names + mcp_tool_names).uniq

          # Validate submitted tools
          selected_tools = params['tools'] || []
          validated_tools = selected_tools.select { |st|
            if all_valid_tool_names.include?(st) then true
            else
              logger.warn("Invalid tool '#{st}' submitted for agent '#{name}'. Valid options: #{all_valid_tool_names.join(', ')}")
              false
            end
          }
          new_value = validated_tools # Store array for update call

          # Prepare data for the _agent_tool_table partial (on success)
          response_locals[:mcp_tool_results] = mcp_tool_results # Pass fresh results (based on current config)
          # Rebuild full metadata map based on current config
          fetched_mcp_tools_metadata = []
          mcp_tool_results.each do |result|
            if result[:status] == :success && result[:tools]
              result[:tools].each do |mcp_tool_schema|
                parameters = []
                begin
                  input_schema = mcp_tool_schema[:inputSchema]
                  if input_schema && input_schema.is_a?(Hash)
                    properties = input_schema['properties'] || {}
                    required = input_schema['required'] || []
                    parameters = ADK::Mcp::Util::SchemaConverter.json_to_adk(properties, required)
                  end
                rescue => e
                  logger.error("Error converting MCP schema post-update for tool '#{mcp_tool_schema[:name]}': #{e.message}")
                end
                fetched_mcp_tools_metadata << { name: mcp_tool_schema[:name].to_sym,
                                                description: mcp_tool_schema[:description] || "", parameters: parameters, source: :mcp, source_detail: "MCP (#{result[:server]})" }
              end
            end
          end
          # <<< START CHANGE: Convert native params hash to array >>>
          all_native_tools_metadata = native_tools_metadata.map do |tm|
            parameters_array = []
            if tm[:parameters].is_a?(Hash) && !tm[:parameters].empty?
              tm[:parameters].each do |param_name, details|
                parameters_array << {
                  name: param_name,
                  type: details[:type],
                  description: details[:description],
                  required: details[:required]
                }
              end
            end
            tm.merge(parameters: parameters_array, source: :native, source_detail: "Native") # Use the converted array
          end
          # <<< END CHANGE >>>
          all_tools_metadata_map = {}
          (all_native_tools_metadata + fetched_mcp_tools_metadata).each { |tm|
            all_tools_metadata_map[tm[:name]] ||= tm
          }
          # Filter map by *validated* tools
          response_locals[:view_configured_tools] = validated_tools.map { |tn|
            all_tools_metadata_map[tn.to_sym]
          }.compact

        elsif field == 'mcp'
          submitted_value = params['value']&.strip
          mcp_json_to_save = (submitted_value.nil? || submitted_value.empty?) ? '[]' : submitted_value
          # Basic JSON validation (Store also validates, but good to catch early for form re-render)
          begin
            parsed = JSON.parse(mcp_json_to_save)
            unless parsed.is_a?(Array)
              raise JSON::ParserError, "Input must be a valid JSON array."
            end

            new_value = mcp_json_to_save # Store validated JSON string
          rescue JSON::ParserError => e
            logger.warn("Update failed for '#{name}', field '#{field}': Invalid JSON - #{e.message}. Value: '#{mcp_json_to_save}'")
            # Fetch current definition to re-render form
            current_definition = @definition_store.get_definition(name) # Assume it exists if we got here
            edit_locals = {
              agent_data: { name: name,
                            mcp_servers_json: current_definition ? current_definition[:mcp_servers_json] : mcp_json_to_save },
              error_message: "Invalid JSON format: #{e.message}"
            }
            halt 200, slim(:_edit_agent_mcp, layout: false, locals: edit_locals)
          end
          agent_data_hash[:mcp_servers_json] = new_value # For display partial if needed

        elsif field == 'fallback'
          submitted_value = params['value']&.strip
          unless ['error', 'echo'].include?(submitted_value)
            logger.warn("Update failed for '#{name}', field '#{field}': Invalid value '#{submitted_value}'.")
            current_definition = @definition_store.get_definition(name)
            edit_locals = {
              agent_data: { name: name,
                            fallback_mode: current_definition ? current_definition[:fallback_mode] : :error },
              error_message: "Invalid fallback mode selected."
            }
            halt 400, slim(:_edit_agent_fallback, layout: false, locals: edit_locals)
          end
          new_value = submitted_value.to_sym # Store as symbol for update
          agent_data_hash[:fallback_mode] = new_value # For display partial

        elsif field == 'instruction' # <<< Added instruction handling
          # Instructions can be empty, so no specific validation needed here besides stripping
          new_value = params['value']&.strip || "" # Default to empty string if nil
          agent_data_hash[:instruction] = new_value
        else # description or model
          submitted_value = params['value']&.strip
          if submitted_value.nil? || submitted_value.empty?
            logger.warn("Update failed for '#{name}', field '#{field}': Value empty.")
            current_definition = @definition_store.get_definition(name)
            edit_locals = {
              agent_data: { name: name,
                            description: current_definition ? current_definition[:description] : '',
                            model: current_definition ? current_definition[:model] : '' },
              error_message: "#{field.capitalize} cannot be empty."
            }
            halt 400, slim(:'_edit_agent_#{field}', layout: false, locals: edit_locals)
          end
          new_value = submitted_value
          agent_data_hash[field.to_sym] = new_value # Update the field in the hash for display partial
        end

        # --- Update Definition Store ---
        begin
          update_success = @definition_store.update_definition(name, { field_to_update => new_value })

          unless update_success
            logger.error("Definition store failed to update field '#{field_to_update}' for agent '#{name}'. Agent might not exist.")
            halt 404, "Agent definition not found, cannot update." unless @definition_store.definition_exists?(name)
            halt 500, "Error updating agent definition."
          end

          logger.info("Agent '#{name}' field '#{field_to_update}' updated successfully via store.")

          # --- Automatic Restart Logic ---
          was_running = @agents.key?(name)
          if was_running
            logger.info("Agent '#{name}' config updated while running. Triggering automatic restart.")
            stop_success = _stop_agent(name)
            if stop_success
              newly_started_agent = _start_agent(name)
              agent_data_hash[:running] = !newly_started_agent.nil?
              logger.info("Automatic restart for '#{name}' completed. Running: #{agent_data_hash[:running]}")
              headers 'HX-Trigger-After-Swap' => 'showRestartToast'
            else
              logger.error("Failed to stop running agent '#{name}' during automatic restart. State might be inconsistent.")
              agent_data_hash[:running] = true # Best guess
              headers 'HX-Trigger-After-Swap' => 'showRestartErrorToast'
            end
          else
            logger.info("Agent '#{name}' config updated while stopped.")
            agent_data_hash[:running] = false # Ensure status reflects stopped state
          end

          # --- Prepare Final Response ---
          # Fetch the complete updated definition for rendering display partials
          updated_definition = @definition_store.get_definition(name)
          if updated_definition
            agent_data_hash[:description] = updated_definition[:description]
            agent_data_hash[:model] = updated_definition[:model]
            agent_data_hash[:fallback_mode] = updated_definition[:fallback_mode]
            agent_data_hash[:mcp_servers_json] = updated_definition[:mcp_servers_json]
          else
            logger.error("Failed to retrieve definition for '#{name}' immediately after successful update.")
            # Use the values we prepared earlier in agent_data_hash if re-fetch fails
          end

          response_locals[:agent_data] = agent_data_hash

          # --- Determine response partial based on updated field ---
          main_response_html = if field == 'tools'
                                 slim(:_agent_tool_table, layout: false, locals: response_locals)
                               else
                                 # --- FIXED: Use double quotes for symbol interpolation ---
                                 slim(:"_display_agent_#{field}", layout: false, locals: response_locals)
                               end

          main_response_html # HX headers are set automatically by Sinatra's `headers` call

        # --- MODIFIED: Catch Store Errors ---
        rescue ArgumentError => e # Catch validation errors from store/this route
          logger.warn("Update failed for '#{name}', field '#{field_to_update}': #{e.message}")
          halt 400, "Invalid input: #{e.message}" unless response.status == 400 # Avoid double halt if form re-rendered
        rescue ADK::DefinitionStore::StoreError => e
          logger.error("Store error updating agent '#{name}': #{e.message}")
          halt 500, "Error updating agent definition."
        rescue => e # Catch other unexpected errors
          logger.error("Unexpected error updating agent '#{name}': #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
          halt 500, "Internal server error during update."
        end
        # --- END MODIFICATION ---
      end

      #   - Error (various codes): JSON body `{"error": "..."}`.
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
    end # End App class
  end # End Web module
end # End ADK module
