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

      # --- Instance Variables ---
      # Initializes application state, including connections and services.
      def initialize
        super
        # In-memory hash storing active/running ADK::Agent instances, keyed by agent name.
        @agents = {}
        # Service responsible for managing chat sessions (stores conversation history).
        # Defaulting to in-memory storage.
        @session_service = ADK::SessionService::InMemory.new
        # Redis client connection for persisting agent definitions.
        # Application can function without Redis, but agent definitions won't be saved.
        begin
          @redis = Redis.new # Assumes default connection (e.g., localhost:6379)
          @redis.ping
          logger.info("Successfully connected to Redis.")
        rescue Redis::CannotConnectError => e
          logger.error("Could not connect to Redis. Persistence disabled. #{e.message}")
          @redis = nil
        end
        # Compile SASS/SCSS files in public/styles to CSS in public/css on application startup.
        SassCompiler.compile_all
      end

      # Generates the Redis hash key for a specific agent's definition.
      # @param name [String] The name of the agent.
      # @return [String] The Redis key.
      def agent_redis_key(name)
        "#{REDIS_AGENT_HASH_PREFIX}#{name}"
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
              response_data[:raw_json_content] = content.inspect

              if content.is_a?(Hash)
                case content[:status]
                when :success
                  response_data[:msg_class] = 'is-success'
                  response_data[:display_content] = content[:result]
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
                  response_data[:raw_json_content] = content.inspect # Ensure raw is set
                end
              else # Event Content wasn't a hash
                response_data[:display_content] = "Agent event content format unexpected: #{content.inspect}"
                response_data[:raw_json_content] = content.inspect # Ensure raw is set
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
        def pretty_json(json_string)
          begin
            parsed = JSON.parse(json_string || '[]')
            JSON.pretty_generate(parsed)
          rescue JSON::ParserError
            json_string # Fallback to raw string on error
          end
        end
        # --- END NEW HELPER ---
      end # end helpers

      # --- Routes ---
      # Defines the HTTP endpoints for the web application.

      # GET / - Main welcome page.
      get '/' do
        logger.debug("GET / route handler entered")
        slim :index
      end

      # --- Agent Definition Management Routes (Redis Persistence) ---
      # These routes handle CRUD operations for agent *definitions*, which are stored in Redis.

      # GET /agents - Display the main agent management page.
      # Lists all agents defined in Redis, showing their status (Running/Stopped)
      # and providing controls to create, manage, and start/stop agents.
      get '/agents' do
        @view_agents = []
        if @redis
          agent_names = @redis.smembers(REDIS_AGENTS_SET_KEY).sort
          agent_data_list = @redis.pipelined do |pipe|
            agent_names.each { |n| pipe.hmget(agent_redis_key(n), 'description', 'tools', 'model') }
          end
          agent_names.zip(agent_data_list).each do |name, data|
            description, tools_json, model = data[0] || "N/A", data[1], data[2]
            configured_tools = []; begin tools_json && configured_tools = JSON.parse(tools_json) rescue []; end
            is_running = @agents.key?(name)
            @view_agents << { name: name, description: description, running: is_running,
                              configured_tools: configured_tools, model: model }
          end
        else logger.error("Redis unavailable during GET /agents"); end
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
        halt 503, "Redis unavailable." unless @redis
        agent_name = params['name']&.strip; agent_description = params['description']&.strip
        selected_tools = params['tools'] || []; selected_model = params['model']&.strip
        selected_fallback = params['fallback_mode'] || 'error' # <-- Get fallback mode, default to error
        mcp_servers_json = params['mcp_servers_json']&.strip
        mcp_servers_json_to_save = (mcp_servers_json.nil? || mcp_servers_json.empty?) ? '[]' : mcp_servers_json
        model_to_save = selected_model && !selected_model.empty? ? selected_model : ADK::Agent::DEFAULT_MODEL

        if agent_name.nil? || agent_name.empty? || agent_description.nil? || agent_description.empty?
          status 400; halt "<div class='notification is-danger'>Name and description required.</div>"; end
        key = agent_redis_key(agent_name)
        if @redis.sismember(REDIS_AGENTS_SET_KEY, agent_name)
          status 409; halt "<div class='notification is-warning'>Agent '#{agent_name}' already exists.</div>"; end

        # --- BEGIN ADDED: Validate MCP JSON ---
        begin
          unless mcp_servers_json_to_save == '[]' # Skip parsing the default empty array
            parsed_mcp = JSON.parse(mcp_servers_json_to_save)
            unless parsed_mcp.is_a?(Array)
              raise JSON::ParserError, "Input must be a valid JSON array."
            end
            # Optional: Add deeper validation of array contents here if needed
          end
        rescue JSON::ParserError => e
          logger.warn("Agent creation failed for '#{agent_name}': Invalid MCP JSON - #{e.message}. Value: '#{mcp_servers_json_to_save}'")
          status 400;
          halt "<div class='notification is-danger'>Invalid format for MCP Server Configurations: #{e.message}. Please provide a valid JSON array or leave empty.</div>"
        end
        # --- END ADDED: Validate MCP JSON ---

        begin
          tools_json = selected_tools.to_json
          @redis.multi { |m|
            m.hset(key, 'description', agent_description);
            m.hset(key, 'tools', tools_json);
            m.hset(key, 'model', model_to_save);
            m.hset(key, 'fallback_mode', selected_fallback) # <-- Save fallback mode
            m.hset(key, 'mcp_servers_json', mcp_servers_json_to_save)
            m.sadd(REDIS_AGENTS_SET_KEY, agent_name)
          }
          logger.info("Agent '#{agent_name}' definition saved (Model: #{model_to_save}, Tools: #{selected_tools}, Fallback: #{selected_fallback}, MCP: #{!mcp_servers_json_to_save.empty? && mcp_servers_json_to_save != '[]'})") # Log MCP status
        rescue Redis::BaseError => e; logger.error("Redis error: #{e.message}"); halt 500, "DB Error";
        rescue JSON::GeneratorError => e; logger.error("JSON error: #{e.message}"); halt 500, "Internal Error"; end
        content_type :html
        # --- MODIFIED: Remove mcp_servers_json from hash passed to partial ---
        agent_data = { name: agent_name, description: agent_description, running: false,
                       configured_tools: selected_tools, model: model_to_save, fallback_mode: selected_fallback }
        # <------------------------------------------------------------------->
        # Pass available tools needed by the partial for rendering tool links/descriptions
        available_tools = ADK::GlobalToolManager.list_all_tools
        agent_row_html = slim(:_agent_row, layout: false,
                                           locals: { agent_info: agent_data, available_tools: available_tools })
        oob_remove_message_html = "<tr id='no-agents-row' hx-swap-oob='true'></tr>"
        agent_row_html + oob_remove_message_html
      end

      # DELETE /agents/:name - Delete an agent definition from Redis.
      # Stops the agent runtime instance if it's currently running.
      # Removes the agent's definition hash and its name from the set in Redis.
      # Returns an empty 200 OK response, triggering HTMX to remove the corresponding row.
      delete '/agents/:name' do |name|
        logger.info("Received request to delete agent '#{name}'")
        halt 503, "Redis unavailable." unless @redis
        agent_key = agent_redis_key(name)
        halt 404 unless @redis.exists?(agent_key)
        if @agents.key?(name)
          logger.info("Stopping running agent '#{name}' before deletion...")
          begin @agents[name].stop;
                @agents.delete(name);
                logger.info("Agent '#{name}' stopped.");
          rescue => e; logger.error("Error stopping agent: #{e.message}"); end
        end
        begin
          deleted_count = @redis.multi { |m| m.del(agent_key); m.srem(REDIS_AGENTS_SET_KEY, name); }
          logger.info("Agent '#{name}' definition deleted from Redis. Results: #{deleted_count.inspect}")
          status 200; body ''
        rescue Redis::BaseError => e;
          logger.error("Redis error deleting agent '#{name}': #{e.message}");
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
        halt 503, "Redis unavailable." unless @redis
        key = agent_redis_key(name)
        fields_to_fetch = ['description', 'tools', 'model', 'fallback_mode', 'mcp_servers_json']
        redis_agent_data = @redis.hmget(key, *fields_to_fetch)
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]
        loaded_model = redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL
        fallback_mode = redis_agent_data[3] || 'error'
        mcp_servers_json = redis_agent_data[4] || '[]'

        unless description
          halt 404,
               slim(:error_404, locals: { title: "Agent Not Found", message: "Definition for '#{name}' not found." })
        end

        is_running = @agents.key?(name)
        @view_agent_data = { name: name, description: description, running: is_running,
                             model: loaded_model, fallback_mode: fallback_mode,
                             mcp_servers_json: mcp_servers_json }

        # --- Get Configured Tool Names ---
        configured_tool_names = []
        begin
          configured_tool_names = JSON.parse(tools_json_string).map(&:to_sym) if tools_json_string && !tools_json_string.empty?
        rescue JSON::ParserError => e
          logger.error("Invalid JSON in configured tools for agent '#{name}': #{e.message}")
        end
        logger.debug("Agent '#{name}' configured tool names from Redis: #{configured_tool_names.inspect}")

        # --- Get All Available Native Tool Metadata ---
        all_native_tools_metadata = ADK::GlobalToolManager.list_all_tools.map do |tool_meta|
          tool_meta.merge(source: :native, source_detail: "Native")
        end

        # --- Fetch MCP Tools and Convert Parameters ---
        mcp_configs = []
        begin
          mcp_configs = JSON.parse(mcp_servers_json) if mcp_servers_json && !mcp_servers_json.empty? && mcp_servers_json != '[]'
        rescue JSON::ParserError => e
          logger.error("Invalid JSON in mcp_servers_json for agent '#{name}': #{e.message}")
          mcp_configs = []
        end
        @mcp_tool_results = fetch_mcp_tools(mcp_configs) # Keep this for displaying errors

        all_mcp_tools_metadata = []
        @mcp_tool_results.each do |result|
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
              logger.error("Error converting MCP schema for tool '#{mcp_tool_hash[:name]}' in agent '#{name}' detail: #{e.message}")
            end
            # Ensure name is a symbol for consistency
            tool_name_sym = mcp_tool_hash[:name].to_sym
            all_mcp_tools_metadata << {
              name: tool_name_sym,
              description: mcp_tool_hash[:description] || '',
              parameters: parameters,
              source: :mcp,
              source_detail: "MCP (#{result[:server]})" # Include server source
            }
          end
        end

        # --- Combine All Available Tools (Prefer Native on Name Clash) ---
        all_available_tools_metadata_map = {}
        (all_native_tools_metadata + all_mcp_tools_metadata).each do |tool_meta|
          # Native tools take precedence if name exists
          all_available_tools_metadata_map[tool_meta[:name]] ||= tool_meta
        end
        logger.debug("Combined available tools map (native+mcp): #{all_available_tools_metadata_map.keys.inspect}")

        # --- Filter Combined List by Configured Names ---
        @view_configured_tools = configured_tool_names.map do |tool_name|
          all_available_tools_metadata_map[tool_name]
        end.compact # Remove nil entries if a configured tool wasn't found

        # Add check_job_status tool if any configured tool is async (has check_workflow_status)
        # Check *actual* tool objects if agent running, or rely on GlobalToolManager otherwise
        should_add_status_tool = false
        if is_running
          agent_instance = @agents[name]
          should_add_status_tool = agent_instance && agent_instance.tools.any? { |t|
            t.respond_to?(:check_workflow_status)
          }
        else
          # Check if any of the configured *native* tools are async based on GlobalToolManager
          should_add_status_tool = @view_configured_tools.any? do |tool_meta|
            tool_meta[:source] == :native && ADK::GlobalToolManager.find_class(tool_meta[:name])&.ancestors&.include?(ADK::Tools::BaseAsyncJobTool)
          end
          # Note: We currently cannot reliably detect if a *configured* MCP tool is async without starting the agent
        end

        if should_add_status_tool && !configured_tool_names.include?(:check_job_status)
          status_tool_meta = all_available_tools_metadata_map[:check_job_status]
          if status_tool_meta && !@view_configured_tools.any? { |t| t[:name] == :check_job_status }
            @view_configured_tools << status_tool_meta
            logger.debug("Implicitly added check_job_status tool to view for agent '#{name}'")
          end
        end

        logger.debug("Final list of tools to display for agent '#{name}': #{@view_configured_tools.map { |t|
          t[:name]
        }.inspect}")

        # Note: We removed the logic that created a temporary agent instance here,
        # as we now derive the tool list directly from metadata and config.
        # The @agent variable is only set if is_running is true.
        @agent = @agents[name] if is_running

        # Pass the filtered/processed list and the raw MCP results (for errors)
        slim :agent, locals: {
          view_configured_tools: @view_configured_tools,
          mcp_tool_results: @mcp_tool_results # Still needed for error display
        }
      end

      # --- Agent Inline Editing Routes (HTMX) ---
      # These routes handle the display and update of agent definition fields inline
      # using HTMX, avoiding full page reloads.

      # GET /agents/:name/edit/:field - Display an inline edit form for a specific agent field.
      # Renders a partial (`_edit_agent_*.slim`) containing the form elements
      # for the specified field (description, model, tools, fallback, mcp).
      # Fetches the current value from Redis to populate the form.
      # For 'tools', it fetches all available native and MCP tools to populate the selector.
      get '/agents/:name/edit/:field' do |name, field|
        supported_fields = ['description', 'model', 'tools', 'fallback', 'mcp']
        halt 404, "Editing field '#{field}' not supported." unless supported_fields.include?(field)
        halt 503, "Redis unavailable." unless @redis
        key = agent_redis_key(name); halt 404 unless @redis.exists?(key)

        # --- Refactored: Fetch fields explicitly and build hash ---
        fields_to_fetch = ['description', 'model', 'tools', 'fallback_mode', 'mcp_servers_json']
        redis_values = @redis.hmget(key, *fields_to_fetch)
        agent_definition = Hash[fields_to_fetch.zip(redis_values)]

        agent_data = {
          name: name,
          description: agent_definition['description'],
          model: agent_definition['model'],
          fallback_mode: agent_definition['fallback_mode'] || 'error', # Default if nil
          mcp_servers_json: agent_definition['mcp_servers_json'] || '[]' # <-- Added, default to '[]'
        }
        # --- End Refactor ---

        locals = { agent_data: agent_data }

        # Add field-specific data needed by partials
        if field == 'model'
          locals[:available_models] = AVAILABLE_MODELS
        elsif field == 'tools'
          tools_json_string = agent_definition['tools'] # Get from fetched hash
          configured_tool_names = [];
          begin tools_json_string && configured_tool_names = JSON.parse(tools_json_string) rescue []; end
          locals[:configured_tool_names] = configured_tool_names

          # --- MODIFIED: Combine Native and Fetched MCP Tools for display ---
          # 1. Get Native Tools from Global Manager
          native_tools = ADK::GlobalToolManager.list_all_tools

          # 2. Fetch tools from this agent's MCP config
          mcp_servers_json = agent_definition['mcp_servers_json'] || '[]'
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
          # --- END MODIFICATION ---

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
        halt 503, "Redis unavailable." unless @redis
        key = agent_redis_key(name); halt 404 unless @redis.exists?(key)

        # Fetch all data needed by the _agent_tool_table partial
        fields_to_fetch = ['description', 'tools', 'model', 'fallback_mode', 'mcp_servers_json']
        redis_values = @redis.hmget(key, *fields_to_fetch)
        # --- Create a hash from fetched data ---
        agent_definition = Hash[fields_to_fetch.zip(redis_values)]

        # --- Use the definition hash ---
        agent_data = {
          name: name,
          description: agent_definition['description'],
          model: agent_definition['model'] || ADK::Agent::DEFAULT_MODEL,
          fallback_mode: agent_definition['fallback_mode'] || 'error',
          mcp_servers_json: agent_definition['mcp_servers_json'] || '[]'
        }
        agent_data[:running] = @agents.key?(name)

        # --- Get configured tool names string from the definition hash ---
        tools_json_string = agent_definition['tools']
        # logger.debug(\"[Display Tool Table] Raw tools JSON: \#{tools_json_string.inspect}\") # << DEBUG 1 REMOVED

        configured_tool_names_str = []
        begin tools_json_string && configured_tool_names_str = JSON.parse(tools_json_string) rescue [] end
        # logger.debug(\"[Display Tool Table] Parsed tool names (strings): \#{configured_tool_names_str.inspect}\") # << DEBUG 2 REMOVED

        # Get NATIVE tool info from registry for ALL tools
        all_native_tools = ADK::GlobalToolManager.list_all_tools
        # configured_tools_metadata = configured_tool_names_str.map { |tn| # This line seems unused now, removing
        #   all_native_tools.find { |t| t[:name].to_s == tn }
        # }.compact

        # --- Fetch MCP tool results and convert parameters ---
        mcp_servers_json = agent_data[:mcp_servers_json] # Use value from agent_data hash
        mcp_configs = []
        begin
          mcp_configs = JSON.parse(mcp_servers_json) if mcp_servers_json && !mcp_servers_json.empty? && mcp_servers_json != '[]'
        rescue JSON::ParserError => e
          logger.error("Invalid JSON in mcp_servers_json for agent '#{name}' tool table display: #{e.message}")
          mcp_configs = []
        end
        mcp_tool_results = fetch_mcp_tools(mcp_configs)

        # Process results to add :parameters and build MCP metadata list
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
              logger.error("Error converting MCP schema for tool '#{mcp_tool_hash[:name]}' in tool table display: #{e.message}")
            end
            tool_name_sym = mcp_tool_hash[:name].to_sym
            all_mcp_tools_metadata << {
              name: tool_name_sym,
              description: mcp_tool_hash[:description] || '',
              parameters: parameters,
              source: :mcp,
              source_detail: "MCP (#{result[:server]})"
            }
          end
        end

        # Add source info to native tools metadata
        all_native_tools_metadata = all_native_tools.map do |tool_meta|
          tool_meta.merge(source: :native, source_detail: "Native")
        end

        # Combine all available tools map
        all_available_tools_metadata_map = {}
        (all_native_tools_metadata + all_mcp_tools_metadata).each do |tool_meta|
          all_available_tools_metadata_map[tool_meta[:name]] ||= tool_meta
        end

        # Filter by configured names
        configured_tool_names = configured_tool_names_str.map(&:to_sym) # Convert strings to symbols
        # logger.debug(\"[Display Tool Table] Configured tool names (symbols): \#{configured_tool_names.inspect}\") # << DEBUG 4 REMOVED

        view_configured_tools_list = configured_tool_names.map do |tool_name| # Use the symbol list here
          all_available_tools_metadata_map[tool_name]
        end.compact
        # logger.debug(\"[Display Tool Table] Filtered tool list before status check: \#{view_configured_tools_list.map { |t| t[:name] }.inspect}\") # << DEBUG 5 REMOVED

        # Implicitly add check_job_status if needed (simplified check as agent not running)
        if view_configured_tools_list.any? { |tm|
          tm[:source] == :native && ADK::GlobalToolManager.find_class(tm[:name])&.ancestors&.include?(ADK::Tools::BaseAsyncJobTool)
        } && !configured_tool_names.include?(:check_job_status)
          status_tool_meta = all_available_tools_metadata_map[:check_job_status]
          if status_tool_meta && !view_configured_tools_list.any? { |t| t[:name] == :check_job_status }
            view_configured_tools_list << status_tool_meta
          end
        end

        # logger.debug(\"[Display Tool Table] Final tool list passed to view: \#{view_configured_tools_list.map { |t| t[:name] }.inspect}\") # << DEBUG 6 REMOVED

        # Render the full table partial
        slim :_agent_tool_table, layout: false,
                                 locals: {
                                   agent_data: agent_data,
                                   view_configured_tools: view_configured_tools_list,
                                   mcp_tool_results: mcp_tool_results
                                 }
      end

      # GET /agents/:name/display/:field - Render the display partial for a field.
      # Used by the "Cancel" button in most inline edit forms (except 'tools')
      # to swap the edit form back to the static display view (`_display_agent_*.slim`).
      get '/agents/:name/display/:field' do |name, field|
        supported_fields = ['description', 'model', 'tools', 'fallback', 'mcp']
        halt 404, "Displaying field '#{field}' not supported." unless supported_fields.include?(field)
        halt 503, "Redis unavailable." unless @redis
        key = agent_redis_key(name); halt 404 unless @redis.exists?(key)
        # ---> Fetch mcp_servers_json for display <---
        redis_data = @redis.hmget(key, 'description', 'model', 'tools', 'fallback_mode', 'mcp_servers_json')
        response_locals = {};
        response_locals[:agent_data] =
          { name: name, description: redis_data[0], model: redis_data[1], fallback_mode: redis_data[3] || 'error',
            mcp_servers_json: redis_data[4] || '[]' } # <-- Added
        # <-------------------------------------------->
        if field == 'tools'
          tools_json_string = redis_data[2];
          configured_tool_names_str = [];
          begin tools_json_string && configured_tool_names_str = JSON.parse(tools_json_string) rescue []; end
          all_tools = ADK::GlobalToolManager.list_all_tools
          response_locals[:configured_tools] = configured_tool_names_str.map { |tn|
            all_tools.find { |t| t[:name].to_s == tn }
          }.compact
          logger.debug("Local tools for agent '#{name}' during display: #{response_locals.inspect}")
        end
        slim :"_display_agent_#{field}", layout: false, locals: response_locals
      end

      # PUT /agents/:name/update/:field - Update a specific field in an agent's Redis definition.
      # Receives the new value from the inline edit form.
      # Validates the input (e.g., checks MCP JSON format, fallback mode value).
      # Updates the corresponding field in the agent's Redis hash.
      # **Crucially, if the agent was running, it automatically stops and restarts it**
      # to apply the configuration change to the runtime instance.
      # Returns the updated display partial (`_display_agent_*.slim` or `_agent_tool_table.slim`).
      # May include an `HX-Trigger-After-Swap` header to show a toast notification
      # on the frontend about the automatic restart (`showRestartToast` or `showRestartErrorToast`).
      put '/agents/:name/update/:field' do |name, field|
        # logger.debug("PUT /agents/#{name}/update/#{field} received. PARAMS: #{params.inspect}")
        supported_fields = ['description', 'model', 'tools', 'fallback', 'mcp']
        halt 404, "Updating field '#{field}' not supported." unless supported_fields.include?(field)
        halt 503, "Redis unavailable." unless @redis
        key = agent_redis_key(name); halt 404 unless @redis.exists?(key)

        redis_field_to_update = case field
                                when 'fallback' then 'fallback_mode'
                                when 'mcp' then 'mcp_servers_json'
                                else field
                                end

        new_value_to_save = nil
        response_locals = {} # Locals for rendering success partial
        agent_data_hash = { name: name } # Base hash for success partials

        # --- Handle specific field updates ---
        if field == 'tools'
          # 1. Get all available tool names (Native + MCP)
          native_tools_metadata = ADK::GlobalToolManager.list_all_tools
          native_tool_names = native_tools_metadata.map { |t| t[:name].to_s }
          mcp_servers_json = @redis.hget(key, 'mcp_servers_json') || '[]'
          mcp_configs = []
          begin
            mcp_configs = JSON.parse(mcp_servers_json) if mcp_servers_json && !mcp_servers_json.empty? && mcp_servers_json != '[]'
          rescue JSON::ParserError => e
            logger.error("Invalid JSON in mcp_servers_json during tool update validation for '#{name}': #{e.message}")
          end
          mcp_tool_results = fetch_mcp_tools(mcp_configs)
          mcp_tool_names = []
          mcp_tool_results.each do |result|
            if result[:status] == :success && result[:tools]
              mcp_tool_names.concat(result[:tools].map { |t| t[:name] }) # Assuming name is already string
            end
          end
          all_valid_tool_names = (native_tool_names + mcp_tool_names).uniq

          # 2. Validate submitted tools
          selected_tools = params['tools'] || []
          validated_tools = selected_tools.select { |st|
            if all_valid_tool_names.include?(st) then true
            else
              logger.warn("Invalid tool '#{st}' submitted for agent '#{name}'. Valid options: #{all_valid_tool_names.join(', ')}")
              false
            end
          }
          new_value_to_save = validated_tools.to_json

          # Prepare data for the _agent_tool_table partial (on success)
          response_locals[:mcp_tool_results] = mcp_tool_results # Pass fresh results
          # Rebuild full metadata map
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
          all_native_tools_metadata = native_tools_metadata.map { |tm|
            tm.merge(source: :native, source_detail: "Native")
          }
          all_tools_metadata_map = {}
          (all_native_tools_metadata + fetched_mcp_tools_metadata).each { |tm|
            all_tools_metadata_map[tm[:name]] ||= tm
          }
          # Filter map by validated tools
          response_locals[:view_configured_tools] = validated_tools.map { |tn|
            all_tools_metadata_map[tn.to_sym]
          }.compact

        elsif field == 'mcp'
          new_value_to_save = params['value']&.strip
          new_value_to_save = '[]' if new_value_to_save.nil? || new_value_to_save.empty?
          # Basic JSON validation
          begin
            parsed = JSON.parse(new_value_to_save)
            unless parsed.is_a?(Array)
              raise JSON::ParserError, "Input must be a valid JSON array."
            end
          rescue JSON::ParserError => e
            logger.warn("Update failed for '#{name}', field '#{field}': Invalid JSON - #{e.message}. Value: '#{new_value_to_save}'")
            edit_locals = {
              agent_data: { name: name, mcp_servers_json: new_value_to_save }, # Pass invalid JSON back
              error_message: "Invalid JSON format: #{e.message}"
            }
            # Return 200 OK with the edit form containing the error AND HALT
            halt 200, slim(:_edit_agent_mcp, layout: false, locals: edit_locals)
          end
          # Value is valid if we reach here
          agent_data_hash[:mcp_servers_json] = new_value_to_save

        elsif field == 'fallback'
          new_value_to_save = params['value']&.strip
          unless ['error', 'echo'].include?(new_value_to_save)
            logger.warn("Update failed for '#{name}', field '#{field}': Invalid value '#{new_value_to_save}'.")
            edit_locals = {
              agent_data: { name: name, fallback_mode: @redis.hget(key, 'fallback_mode') || 'error' }, # Pass current value back
              error_message: "Invalid fallback mode selected."
            }
            halt 400, slim(:_edit_agent_fallback, layout: false, locals: edit_locals) # Re-render edit form with error
          end
          agent_data_hash[:fallback_mode] = new_value_to_save

        else # description or model
          new_value_to_save = params['value']&.strip
          if new_value_to_save.nil? || new_value_to_save.empty?
            logger.warn("Update failed for '#{name}', field '#{field}': Value empty.")
            edit_locals = {
              agent_data: { name: name, description: @redis.hget(key, 'description'),
                            model: @redis.hget(key, 'model') },
              error_message: "#{field.capitalize} cannot be empty."
            }
            halt 400, slim(:"_edit_agent_#{field}", layout: false, locals: edit_locals) # Re-render edit form with error
          end
          agent_data_hash[field.to_sym] = new_value_to_save # Update the field in the hash for display partial
        end

        # --- Update Redis ---
        begin
          @redis.hset(key, redis_field_to_update, new_value_to_save)
          logger.info("Agent '#{name}' field '#{redis_field_to_update}' updated successfully.")

          # --- Automatic Restart Logic ---
          was_running = @agents.key?(name)
          if was_running
            logger.info("Agent '#{name}' config updated while running. Triggering automatic restart.")
            stop_success = _stop_agent(name)
            if stop_success
              newly_started_agent = _start_agent(name)
              agent_data_hash[:running] = !newly_started_agent.nil?
              logger.info("Automatic restart for '#{name}' completed. Running: #{agent_data_hash[:running]}")
              # --- Set header to trigger frontend notification ---
              headers 'HX-Trigger-After-Swap' => 'showRestartToast'
            else
              logger.error("Failed to stop running agent '#{name}' during automatic restart. State might be inconsistent.")
              agent_data_hash[:running] = true # Best guess: it might still be running
              # --- Set header to trigger frontend error notification ---
              headers 'HX-Trigger-After-Swap' => 'showRestartErrorToast'
            end
          else
            logger.info("Agent '#{name}' config updated while stopped.")
            agent_data_hash[:running] = false # Ensure status reflects stopped state
          end

          # --- Prepare Final Response ---
          # Update agent_data_hash with potentially changed running status and other current values
          agent_data_hash[:description] ||= @redis.hget(key, 'description')
          agent_data_hash[:model] ||= @redis.hget(key, 'model')
          agent_data_hash[:fallback_mode] ||= @redis.hget(key, 'fallback_mode') || 'error'
          agent_data_hash[:mcp_servers_json] ||= @redis.hget(key, 'mcp_servers_json') || '[]'
          response_locals[:agent_data] = agent_data_hash

          # --- Determine response partial based on updated field ---
          main_response_html = if field == 'tools'
                                 # If tools were updated, response_locals[:view_configured_tools] and [:mcp_tool_results] were already prepared
                                 slim(:_agent_tool_table, layout: false, locals: response_locals)
                               else
                                 # For other fields, render the corresponding DISPLAY partial
                                 slim(:"_display_agent_#{field}", layout: false,
                                                                  locals: { agent_data: response_locals[:agent_data] })
                               end

          # --- Return HTML ---
          main_response_html # HX headers are set automatically by Sinatra's `headers` call
        rescue Redis::BaseError => e
          logger.error("Redis error updating: #{e.message}"); halt 500, "Error updating definition.";
        rescue JSON::GeneratorError => e # Should not happen unless validated_tools is bad
          logger.error("JSON error saving tools: #{e.message}"); halt 500, "Error saving tool configuration.";
        end
      end
      # --- End Agent Inline Editing Routes ---

      # --- Agent Runtime Management Routes (In-Memory Instances) ---
      # These routes handle starting and stopping the *runtime* instances of agents,
      # which are stored in the @agents in-memory hash.

      # POST /agents/:name/start - Start a runtime instance (from main agent list view).
      # Calls the `_start_agent` helper method.
      # Returns HTML fragments (via `agent_status_fragments`) for HTMX OOB swap
      # to update the agent's status indicator and buttons in the main list.
      post '/agents/:name/start' do
        name = params[:name]
        agent = _start_agent(name) # <<< Use helper
        # Prepare data for view - need definition even if start failed or already running
        agent_data_for_view = if agent then agent # Use running instance if available
                              else # Fetch definition from Redis if start failed/not running
                                redis_data = @redis&.hmget(agent_redis_key(name), 'description', 'tools',
                                                           'model') || ["N/A", nil, nil]
                                tools = []; if redis_data[1] then tools = JSON.parse(redis_data[1]) rescue [] end
                                { name: name, description: redis_data[0], running: false, model: redis_data[2],
                                  configured_tools: tools }
                              end
        agent_status_fragments(agent_data_for_view)
      end

      # POST /agents/:name/start/detail - Start a runtime instance (from agent detail view).
      # Calls the `_start_agent` helper method.
      # Returns the `_agent_status_controls.slim` partial for the detail view's status section,
      # plus an OOB swap fragment to enable/update the "Execute Task" button.
      post '/agents/:name/start/detail' do
        name = params[:name]; content_type :html
        agent = _start_agent(name) # <<< Use helper
        # Prepare data for view
        is_running = !agent.nil?
        agent_data_for_view = if agent then agent
                              else # Fetch definition from Redis
                                redis_data = @redis&.hmget(agent_redis_key(name), 'description', 'tools',
                                                           'model') || ["N/A", nil, nil]
                                tools = []; if redis_data[1] then tools = JSON.parse(redis_data[1]) rescue [] end
                                { name: name, description: redis_data[0], running: false, model: redis_data[2],
                                  configured_tools: tools }
                              end
        # Render the status controls partial
        status_controls_html = slim(:_agent_status_controls, layout: false, locals: { agent_data: agent_data_for_view })
        # --- Manually construct the OOB button HTML ---
        execute_button_text = is_running ? 'Execute' : 'Execute (Requires Start)'
        disabled_attr_string = is_running ? '' : 'disabled' # Use standard boolean attribute presence
        execute_button_oob_html = %(
          <button class="button is-primary" id="execute-task-button" type="submit" #{disabled_attr_string} hx-swap-oob="true">
            <span class="icon is-small"><i class="fas fa-play-circle"></i></span>
            <span>#{execute_button_text}</span>
          </button>
        )
        # --- Return combined HTML ---
        status_controls_html + execute_button_oob_html
      end

      # POST /agents/:name/stop - Stop a running agent instance (from main agent list view).
      # Calls the `_stop_agent` helper method.
      # Returns HTML fragments (via `agent_status_fragments`) for HTMX OOB swap
      # to update the agent's status indicator and buttons in the main list.
      post '/agents/:name/stop' do
        name = params[:name]
        _stop_agent(name) # <<< Use helper
        # Fetch definition for display after stopping
        redis_data = @redis&.hmget(agent_redis_key(name), 'description', 'tools', 'model') || ["N/A", nil, nil]
        tools = []; if redis_data[1] then tools = JSON.parse(redis_data[1]) rescue [] end
        stopped_agent_data = { name: name, description: redis_data[0], running: false, model: redis_data[2],
                               configured_tools: tools }
        agent_status_fragments(stopped_agent_data)
      end

      # POST /agents/:name/stop/detail - Stop a running agent instance (from agent detail view).
      # Calls the `_stop_agent` helper method.
      # Returns the `_agent_status_controls.slim` partial for the detail view's status section,
      # plus an OOB swap fragment to disable/update the "Execute Task" button.
      post '/agents/:name/stop/detail' do
        name = params[:name]; content_type :html
        _stop_agent(name) # <<< Use helper
        # Fetch definition for display after stopping
        is_running = false # Agent is stopped
        redis_data = @redis&.hmget(agent_redis_key(name), 'description', 'tools', 'model') || ["N/A", nil, nil]
        tools = []; if redis_data[1] then tools = JSON.parse(redis_data[1]) rescue [] end
        stopped_agent_data = { name: name, description: redis_data[0], running: is_running, model: redis_data[2],
                               configured_tools: tools }
        # Render the status controls partial
        status_controls_html = slim(:_agent_status_controls, layout: false, locals: { agent_data: stopped_agent_data })
        # --- Manually construct the OOB button HTML ---
        execute_button_text = is_running ? 'Execute' : 'Execute (Requires Start)'
        disabled_attr_string = is_running ? '' : 'disabled' # Use standard boolean attribute presence
        execute_button_oob_html = %(
          <button class="button is-primary" id="execute-task-button" type="submit" #{disabled_attr_string} hx-swap-oob="true">
            <span class="icon is-small"><i class="fas fa-play-circle"></i></span>
            <span>#{execute_button_text}</span>
          </button>
        )
        # --- Return combined HTML ---
        status_controls_html + execute_button_oob_html
      end

      # --- Agent Interaction Routes ---
      # Routes for interacting with running agent instances (chat, direct execution).

      # GET /agents/:name/chat - Render the chat interface page.
      # Requires the agent to be running.
      # Retrieves or creates an ADK chat session using the `@session_service`.
      # The ADK session ID is stored in the user's Sinatra session cookie (`session[:adk_session_id]`).
      # Loads chat history from the ADK session and renders the `chat.slim` template.
      get '/agents/:name/chat' do |name|
        @agent = @agents[name] # Get running agent instance
        # Agent must be running to enter chat
        halt 404,
             slim(:error_404,
                  locals: { title: "Agent Not Running",
                            message: "Agent '#{name}' must be started to chat." }) unless @agent

        # --- Session Handling ---
        session_id = session[:adk_session_id] # Get ID from Sinatra session cookie
        adk_session = nil
        if session_id
          adk_session = @session_service.get_session(session_id: session_id)
          # --- Add check: Ensure session belongs to this agent/app? ---
          if adk_session && adk_session.app_name != name
            logger.warn("Session ID mismatch: Session #{session_id} belongs to app '#{adk_session.app_name}', not '#{name}'. Creating new session.")
            session.delete(:adk_session_id) # Clear wrong ID
            adk_session = nil # Force creation
          else
            logger.debug("Chat GET: Found existing session ID in Sinatra session: #{session_id}. Found in service: #{!adk_session.nil?}")
          end
        end

        # If session not found in service or no/wrong ID in Sinatra session, create a new one
        unless adk_session
          logger.info("Chat GET: Creating new session for agent '#{name}'")
          # Use agent name as app_name, generic user_id for web UI
          adk_session = @session_service.create_session(app_name: name, user_id: 'web_user')
          session[:adk_session_id] = adk_session.id # Store new ID in Sinatra session cookie
          logger.info("Chat GET: New session created and stored: #{adk_session.id}")
        end
        # --- End Session Handling ---

        # --- Prepare data for the view ---
        @adk_session = adk_session # Make session object available
        # Extract events for rendering history
        @chat_history_events = adk_session ? adk_session.events : [] # Pass events array
        # Pass agent runtime instance needed by the view title/status logic
        @view_agent_data = { name: @agent.name, running: @agent.running? }

        logger.debug("Rendering chat view with #{@chat_history_events.length} historical events.")
        slim :chat
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
        session_id = session[:adk_session_id] # Get session ID from Sinatra session

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

      # --- API Endpoints (JSON) ---
      # Provide simple JSON data about the system state.

      # GET /api/agents - List all defined agents and their status.
      # Returns JSON: `{"agents": [{"name": ..., "description": ..., "running": ..., "model": ...}, ...]}`
      get('/api/agents') {
        content_type :json;
        agents_data = [];
        if @redis; agent_names = @redis.smembers(REDIS_AGENTS_SET_KEY); redis_data = @redis.pipelined { |p|
          agent_names.each { |n|
            p.hmget(agent_redis_key(n), 'description', 'model')
          }
        }; agents_data = agent_names.zip(redis_data).map { |name, data|
             desc, model = data[0] || "N/A", data[1];
             is_running = @agents.key?(name);
             model = @agents[name].model_name if is_running && @agents[name];
             { name: name, description: desc, running: is_running,
               model: model || ADK::Agent::DEFAULT_MODEL }
           }; end; json agents: agents_data.sort_by { |a|
                     a[:name]
                   }
      }

      # GET /api/tools - List all available *native* tools known to the GlobalToolManager.
      # Does not include MCP tools.
      # Returns JSON: `{"tools": [{"name": ..., "description": ..., "parameters": [...]}, ...]}`
      get('/api/tools') { content_type :json; json tools: ADK::GlobalToolManager.list_all_tools }

      # --- Health Check Endpoint ---
      # Standard endpoint for monitoring systems.
      get '/healthz' do
        begin
          # Check connectivity to essential services (currently only Redis if available).
          if @redis
            @redis.ping
          end
          status 200
          body 'OK'
        rescue Redis::BaseError => e
          # Handle Redis connection error.
          logger.error("Health check failed: Redis ping error - #{e.message}")
          status 503
          body 'Service Unavailable (Redis)'
        rescue => e
          # Handle other unexpected errors.
          logger.error("Health check failed: Unexpected error - #{e.class}: #{e.message}")
          status 503
          body 'Service Unavailable (Internal)'
        end
      end

      # GET /agents/:name/generate_example_task - Generate example JSON task using Gemini.
      # Fetches the agent's configured tools (native + MCP metadata).
      # Constructs a prompt asking the Gemini API to generate a sample JSON task
      # in the direct execution format `{"tool_name": ..., "task": ..., "parameters": ...}`
      # based on the agent's available tools and their parameters.
      # Requires `GOOGLE_API_KEY` environment variable.
      # Returns:
      #   - Success (200 OK): JSON body containing the pretty-printed example task object.
      #   - Error (various codes): JSON body `{"error": "..."}`.
      get '/agents/:name/generate_example_task' do |name|
        content_type :json # Default response type
        logger.info("Received request to generate example task for agent: #{name}")

        # --- 1. Fetch Agent Config & Tools ---
        halt 503, json(error: "Redis unavailable.") unless @redis
        key = agent_redis_key(name)
        # --- Fetch model, tools, and MCP config ---
        fields_to_fetch = ['model', 'tools', 'mcp_servers_json']
        redis_values = @redis.hmget(key, *fields_to_fetch)
        agent_model = redis_values[0] || ADK::Agent::DEFAULT_MODEL
        tools_json_string = redis_values[1]
        mcp_servers_json = redis_values[2] || '[]'

        # --- Check if agent definition exists ---
        unless tools_json_string || redis_values[0] # Check if at least model or tools exist
          halt 404, json(error: "Agent definition not found for '#{name}'")
        end

        configured_tool_names = []
        begin
          configured_tool_names = JSON.parse(tools_json_string).map(&:to_sym) if tools_json_string && !tools_json_string.empty?
        rescue JSON::ParserError => e
          logger.error("Invalid JSON in configured tools for agent '#{name}': #{e.message}")
          # Continue, maybe it has MCP tools only
        end

        if configured_tool_names.empty? && mcp_servers_json == '[]'
          return json(example: { task: "Agent '#{name}' has no tools configured. Cannot generate example." })
        end

        # --- 2. Get All Available Tool Metadata (Native + MCP) ---
        # Native
        all_native_tools_metadata = ADK::GlobalToolManager.list_all_tools.map do |tool_meta|
          tool_meta.merge(source: :native, source_detail: "Native")
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

        # --- 3. Filter by Configured Tools ---
        configured_tools_metadata = configured_tool_names.map do |tool_name|
          all_available_tools_metadata_map[tool_name]
        end.compact

        # Also add any *selected* MCP tools not found in Global Manager
        mcp_configured_tools = all_mcp_tools_metadata.select { |mcp_meta|
          configured_tool_names.include?(mcp_meta[:name])
        }
        configured_tools_metadata.concat(mcp_configured_tools).uniq! { |t| t[:name] }

        if configured_tools_metadata.empty?
          return json(example: { task: "Agent '#{name}' has tools configured, but metadata couldn't be retrieved. Cannot generate example." })
        end

        logger.debug("Metadata for example generation: #{configured_tools_metadata.inspect}")

        # --- 4. Construct Prompt for Gemini ---
        tool_details = configured_tools_metadata.map do |metadata|
          # --- Check if parameters exist and are an array before mapping ---
          params_string = if metadata[:parameters].is_a?(Array) && !metadata[:parameters].empty?
                            metadata[:parameters].map { |p|
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

          Choose ONE tool from the list that has parameters (if possible) to demonstrate usage. Populate the "parameters" object with example values appropriate for the tool's parameter types and descriptions. If a tool has no parameters, the "parameters" object should be empty: {}. The "task" description should briefly explain the example. Include the chosen tool's name in the "tool_name" field.

          Return ONLY the raw JSON object string. Do not include any other text, explanations, markdown formatting like ```json, or anything else.

          Available Tools:
          ---
          #{tool_details}
          ---

          Generate the example JSON object now:
        PROMPT
        logger.debug("Prompt for Gemini Example Generation:\n#{prompt}")

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

          # Create a temporary client instance
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

          # Clean potential markdown fences ( Gemini sometimes adds them anyway )
          clean_json_string = generated_json_string.strip
          if clean_json_string.start_with?('```json') && clean_json_string.end_with?('```')
            clean_json_string = clean_json_string.delete_prefix('```json').delete_suffix('```').strip
          elsif clean_json_string.start_with?('```') && clean_json_string.end_with?('```')
            clean_json_string = clean_json_string.delete_prefix('```').delete_suffix('```').strip
          end

          # --- 6. Validate & Return Response ---
          begin
            parsed_json = JSON.parse(clean_json_string)
            # Ensure it has the expected keys
            unless parsed_json.is_a?(Hash) && parsed_json.key?('tool_name') && parsed_json.key?('task') && parsed_json.key?('parameters')
              raise JSON::ParserError, "Generated JSON missing required 'tool_name', 'task' or 'parameters' keys."
            end

            # Return the validated, cleaned JSON string, pretty-formatted
            return JSON.pretty_generate(parsed_json)
          rescue JSON::ParserError => e
            logger.error("Gemini generated invalid/unexpected JSON: #{e.message}. Cleaned Response: #{clean_json_string}")
            halt 500, json(error: "Failed to generate valid JSON example from AI.")
          end
        # --- MODIFIED Rescue block ---
        rescue StandardError => e # Catch other potential API or client errors
          logger.error("Error calling Gemini API: #{e.class} - #{e.message}")
          logger.error(e.backtrace.first(5).join("\n"))
          # Provide a slightly more specific message if it looks like auth error
          error_message = if e.message.downcase.include?('authenticat') || e.message.include?('API key')
                            "AI service authentication failed. Check API key."
                          else
                            "Error communicating with AI service."
                          end
          halt 503, json(error: error_message)
        end
      end
      # --- END NEW ROUTE ---

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

        halt 503, "Redis unavailable." unless @redis
        key = agent_redis_key(name)

        fields_to_fetch = [
          'description', 'tools', 'model', 'fallback_mode', 'mcp_servers_json'
        ]
        redis_agent_data = @redis.hmget(key, *fields_to_fetch)

        agent_description, tools_json, model_name, fallback_mode_str, mcp_servers_json = redis_agent_data[0],
                                                                                         redis_agent_data[1],
                                                                                         (redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL),
                                                                                         redis_agent_data[3],
                                                                                         redis_agent_data[4]

        unless agent_description
          logger.error("Agent definition not found for '#{name}'")
          return nil # Failed to start
        end

        fallback_mode_sym = (fallback_mode_str == 'echo') ? :echo : :error
        mcp_configs = []
        selected_tool_names = []
        begin
          if mcp_servers_json && !mcp_servers_json.empty?
            mcp_configs = JSON.parse(mcp_servers_json)
          end
          if tools_json && !tools_json.empty?
            selected_tool_names = JSON.parse(tools_json).map(&:to_sym) rescue []
          end
        rescue JSON::ParserError => e
          logger.error("Failed to parse config JSON for agent '#{name}' during start: #{e.message}")
          mcp_configs = []
          selected_tool_names = []
        end

        logger.info("Attempting to start agent '#{name}' (Model: #{model_name}, Fallback: #{fallback_mode_sym}, MCP: #{mcp_configs.count} servers)... Selected Tools: #{selected_tool_names.inspect}")
        agent = ADK::Agent.new(
          name: name, description: agent_description, model_name: model_name,
          fallback_mode: fallback_mode_sym,
          mcp_servers: mcp_configs,
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
