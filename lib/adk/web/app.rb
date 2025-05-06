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
require_relative 'routes/agent_definition_routes'
require_relative 'routes/agent_interaction_routes'

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
      register ADK::Web::AgentDefinitionRoutes
      register ADK::Web::AgentInteractionRoutes

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

      # --- Agent Interaction Routes --- MOVED
      # GET /agents/:name/chat - MOVED to agent_interaction_routes.rb
      # POST /agents/:name/chat - MOVED to agent_interaction_routes.rb
      # POST /agents/:name/execute - MOVED to agent_interaction_routes.rb
      # GET /agents/:name/generate_example_task - MOVED to agent_interaction_routes.rb

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
      
      # --- Agent Definition Field Edit/Display Routes --- MOVED
      # These were part of the agent_definition_routes logic and are now in that module.
      # GET /agents/:name/edit/:field - MOVED
      # GET /agents/:name/display/tool_table - MOVED
      # GET /agents/:name/display/:field - MOVED
      # PUT /agents/:name/update/:field - MOVED

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
