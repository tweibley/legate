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
require 'set' # Needed for Mermaid helper

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
# --- Load Authentication System ---
require_relative '../auth/manager' # Authentication manager for handling authentication schemes and credentials
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
require_relative 'routes/documentation_routes'
require_relative 'routes/authentication_routes'

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

      # --- NEW: Before filter for Web User ID ---
      before do
        session[:web_user_id] ||= SecureRandom.uuid
        # Optional: Log the web_user_id for debugging purposes during development
        # logger.debug "Current web_user_id: #{session[:web_user_id]}"
      end
      # --- END NEW ---

      # --- Sinatra Settings ---
      set :root, File.expand_path('../../..', __dir__) # Project root directory
      set :views, File.expand_path('../views', __FILE__) # Views directory for Slim templates
      set :public_folder, File.expand_path('../public', __FILE__) # Directory for static assets (CSS, JS, images)
      set :slim, pretty: true # Configure Slim for readable HTML output

      # --- Constants ---
      # Prefix for Redis keys storing agent definition hashes.
      REDIS_AGENT_HASH_PREFIX = 'adk:agent:'
      # Redis key for the set containing all defined agent names.
      REDIS_AGENTS_SET_KEY = 'adk:agents:all_names'
      # List of available Gemini models selectable in the UI.
      AVAILABLE_MODELS = ['gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-1.5-pro', 'gemini-1.0-pro'].freeze

      # --- Register Route Modules ---
      register ADK::Web::CoreRoutes
      register ADK::Web::ApiRoutes
      register ADK::Web::ToolsUIRoutes
      register ADK::Web::AgentRuntimeRoutes
      register ADK::Web::AgentDefinitionRoutes
      register ADK::Web::AgentInteractionRoutes
      register ADK::Web::DocumentationRoutes
      register ADK::Web::AuthenticationRoutes

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
          redis_client = Redis.new(ADK.redis_options || {}) # Reverted to use ADK.redis_options

          # 2. Check connection explicitly before creating store
          redis_client.ping
          @logger.info('Successfully connected to Redis for Definition Store.')

          # 3. Instantiate the definition store
          @definition_store = ADK::DefinitionStore::RedisStore.new(redis_client: redis_client)
          @logger.info('Agent Definition Store initialized.')

          # 4. Attempt to synchronize running agents based on persistent_status
          synchronize_persistent_agents
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
                  if symbolized_config[:type] == 'stdio'
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
          start_action_id = "agent-start-action-#{agent_name}"
          stop_action_id = "agent-stop-action-#{agent_name}"
          dropdown_id = "agent-actions-dropdown-#{agent_name}"

          status_html = <<~HTML
            <span id="#{status_content_id}" hx-swap-oob="outerHTML">
              <span class="tag is-medium #{is_running ? 'is-success' : 'is-danger'}">
                <span class="icon is-small"><i class="fas #{is_running ? 'fa-check-circle' : 'fa-stop-circle'}"></i></span>
                <span class="ml-1">#{is_running ? 'Running' : 'Stopped'}</span>
              </span>
            </span>
          HTML
          start_action_html = <<~HTML
            <a class="dropdown-item #{is_running ? 'is-disabled' : ''}" href="#"#{' '}
               id="#{start_action_id}"#{' '}
               hx-post="/agents/#{agent_name}/start"#{' '}
               hx-indicator="##{dropdown_id} .dropdown-trigger button"
               hx-swap-oob="outerHTML"#{' '}
               onclick="if(this.classList.contains('is-disabled')) event.preventDefault();">
              <span class="icon has-text-success"><i class="fas fa-play"></i></span>
              <span>Start</span>
            </a>
          HTML
          stop_action_html = <<~HTML
            <a class="dropdown-item #{!is_running ? 'is-disabled' : ''}" href="#"#{' '}
               id="#{stop_action_id}"#{' '}
               hx-post="/agents/#{agent_name}/stop"#{' '}
               hx-indicator="##{dropdown_id} .dropdown-trigger button"
               hx-swap-oob="outerHTML"#{' '}
               onclick="if(this.classList.contains('is-disabled')) event.preventDefault();">
              <span class="icon has-text-danger"><i class="fas fa-stop"></i></span>
              <span>Stop</span>
            </a>
          HTML
          status_html.strip + start_action_html.strip + stop_action_html.strip
        end # end agent_status_fragments

        # Helper for formatting tool/agent execution results into HTML
        def format_execution_result_html(result_data)
          html_parts = []
          notification_class = 'is-info' # Default
          overall_status = :unknown # Default

          # --- Determine overall status ---
          # Handle ADK::Event first
          if result_data.is_a?(ADK::Event)
            result_data = result_data.content # Extract content hash
          end

          # Now work with the hash
          if result_data.is_a?(Hash) && result_data.key?(:status)
            overall_status = result_data[:status]
          elsif result_data.is_a?(Array) && result_data.all? { |h| h.is_a?(Hash) && h.key?(:status) }
            # Multi-step array - determine overall status
            if result_data.any? { |h| h[:status] == :error }
              overall_status = :error
            elsif result_data.any? { |h| h[:status] == :pending }
              overall_status = :pending
            elsif result_data.empty? # Empty plan result
              overall_status = :warning # Or treat as error?
            else # All success
              overall_status = :success
            end
          else # Unexpected format, treat as error
            overall_status = :error
            # Wrap the unexpected data into a standard error hash for consistent handling below
            result_data = { status: :error, error_message: "Unexpected result format: #{result_data.inspect}" }
          end
          # --- End determine overall status ---

          # Set notification class based on status
          notification_class = case overall_status
                               when :success then 'is-success'
                               when :error then 'is-danger'
                               when :pending then 'is-warning' # Use warning for pending
                               else 'is-info' # includes :unknown, :warning (empty plan)
                               end

          # --- Generate HTML content ---
          if result_data.is_a?(Array) # Multi-step result array
            html_parts << '<p><strong>Multi-step Result:</strong></p><ol>'
            result_data.each_with_index do |step_hash, index|
              html_parts << '<li>'
              if step_hash.is_a?(Hash) # Ensure it's a hash before checking status
                case step_hash[:status]
                when :success
                  step_result_content = step_hash[:result]
                  # Handle potential nested result from AgentTool for display
                  if step_result_content.is_a?(Hash) && step_result_content.key?(:status)
                    html_parts << "<strong>Step #{index + 1} (Success - Delegated):</strong>"
                    html_parts << "<blockquote style='margin-left: 1em; border-left: 3px solid #dbdbdb; padding-left: 1em;'>"
                    html_parts << format_execution_result_html(step_result_content) # Recursive call
                    html_parts << '</blockquote>'
                  else
                    html_parts << "<strong>Step #{index + 1} (Success):</strong> <pre>#{Rack::Utils.escape_html(step_result_content.to_s)}</pre>"
                  end
                when :pending # <-- ADDED Pending Case for Multi-step
                  html_parts << "<strong>Step #{index + 1} (Pending):</strong>"
                  html_parts << "<pre>Job ID: #{Rack::Utils.escape_html(step_hash[:job_id].to_s)}" # Changed workflow_id to job_id
                  html_parts << "\nMessage: #{Rack::Utils.escape_html(step_hash[:message].to_s)}" if step_hash[:message]
                  html_parts << '</pre>'
                when :error
                  html_parts << "<strong>Step #{index + 1} (Error):</strong> <pre class='has-text-danger'>#{Rack::Utils.escape_html(step_hash[:error_message].to_s)}</pre>"
                else # Unknown status
                  html_parts << "<strong>Step #{index + 1} (Unknown Status):</strong> <pre>#{Rack::Utils.escape_html(step_hash.inspect)}</pre>"
                end
              else
                # Handle case where an element in the array isn't a hash
                html_parts << "<strong>Step #{index + 1} (Invalid format):</strong> <pre>#{Rack::Utils.escape_html(step_hash.inspect)}</pre>"
              end
              html_parts << '</li>'
            end
            html_parts << '</ol>'

          elsif result_data.is_a?(Hash) # Single result/error/pending hash
            case result_data[:status]
            when :success
              result_content = result_data[:result]
              # Handle potential nested result from AgentTool
              if result_content.is_a?(Hash) && result_content.key?(:status)
                html_parts << '<p><strong>Result (from delegated agent):</strong></p>'
                html_parts << "<blockquote style='margin-left: 1em; border-left: 3px solid #dbdbdb; padding-left: 1em;'>"
                html_parts << format_execution_result_html(result_content) # Recursive call
                html_parts << '</blockquote>'
              else
                html_parts << "<p><strong>Result:</strong></p><pre>#{Rack::Utils.escape_html(result_content.to_s)}</pre>"
              end
            when :pending # <-- ADDED Pending Case for Single Step
              html_parts << '<p><strong>Status: Pending</strong></p>'
              html_parts << "<pre>Job ID: #{Rack::Utils.escape_html(result_data[:job_id].to_s)}" # Changed workflow_id to job_id
              html_parts << "\nMessage: #{Rack::Utils.escape_html(result_data[:message].to_s)}" if result_data[:message]
              html_parts << "\n(Use tool 'check_job_status' with this ID to get the final result)</pre>"
            when :error
              html_parts << "<p><strong>Error:</strong></p><pre class='has-text-danger'>#{Rack::Utils.escape_html(result_data[:error_message].to_s)}</pre>"
            else # Unknown status within hash
              html_parts << "<p><strong>Result (Unknown Status):</strong></p><pre>#{Rack::Utils.escape_html(result_data.inspect)}</pre>"
            end
          end # End if result_data.is_a?(Hash)
          # --- End Generate HTML ---

          # Return final HTML structure
          "<div class='notification #{notification_class} mt-4'>#{html_parts.join}</div>"
        end # end format_execution_result_html

        def process_agent_response(agent_result)
          response_data = {
            msg_class: 'is-warning',
            display_content: '',
            raw_json_content: '',
            event_id: SecureRandom.hex(4)
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
                  response_data[:display_content] = content[:result].to_s
                when :error
                  response_data[:msg_class] = 'is-danger'
                  original_error = content[:error_message] || 'Agent error (no message)'
                  if original_error == 'I cannot fulfill this request with the available tools (empty plan).'
                    response_data[:display_content] =
                      "Sorry, I couldn't determine how to handle that request with the tools I have available."
                  else
                    response_data[:display_content] = original_error
                  end
                when :pending
                  response_data[:msg_class] = 'is-warning'
                  response_data[:display_content] = "Task pending... Job ID: #{content[:job_id]}" # Changed workflow_id to job_id
                  if content[:message] then response_data[:display_content] << " - #{content[:message]}"; end
                else
                  response_data[:display_content] = "Agent response has unknown status: #{content[:status]}"
                end
              else
                response_data[:display_content] = "Agent event content format unexpected: #{content.inspect}"
              end
            elsif agent_result.role == :tool_request
              response_data[:msg_class] = 'is-info is-light'
              content = agent_result.content
              response_data[:raw_json_content] = content.inspect
              if content.is_a?(Hash) && content[:tool_name]
                tool_name = content[:tool_name]
                params_preview = content[:params] && !content[:params].empty? ? ' with parameters' : ' (no parameters)'
                response_data[:display_content] = "Tool Request: #{tool_name}#{params_preview}"
              else
                response_data[:display_content] = "Tool Request: #{content.inspect}"
              end
            elsif agent_result.role == :tool_result
              content = agent_result.content
              response_data[:raw_json_content] = content.inspect
              if content.is_a?(Hash)
                if content[:status] == :error || content[:error]
                  response_data[:msg_class] = 'is-danger is-light'
                  response_data[:display_content] =
                    "Tool Error: #{content[:error] || content[:error_message] || 'Unknown error'}"
                else
                  response_data[:msg_class] = 'is-success is-light'
                  if content[:result]
                    result_str = content[:result].is_a?(String) ? content[:result] : content[:result].inspect
                    response_data[:display_content] = "Tool Result: #{result_str}"
                  else
                    response_data[:display_content] = "Tool Result: #{content.inspect}"
                  end
                end
              else
                response_data[:display_content] = "Tool Result: #{content.inspect}"
                response_data[:msg_class] = 'is-success is-light'
              end
            else
              response_data[:display_content] = "Received event with unknown role: #{agent_result.role}"
              response_data[:raw_json_content] = agent_result.inspect
            end
          when Hash
            response_data[:raw_json_content] = agent_result.inspect
            if agent_result[:status] == :error
              response_data[:msg_class] = 'is-danger'
              response_data[:display_content] = agent_result[:error_message] || 'An unspecified error occurred.'
            else
              response_data[:display_content] = "Unexpected hash format from server: #{agent_result.inspect}"
            end
          else
            response_data[:raw_json_content] = agent_result.inspect
            response_data[:display_content] = "Unexpected response type from server: #{agent_result.class}"
          end
          response_data
        end

        def format_historical_agent_content(content)
          display_content = ''
          if content.is_a?(Hash) && content.key?(:status)
            case content[:status]
            when :success
              display_content = content[:result]
            when :error
              original_error = content[:error_message] || 'Agent error (no message)'
              if original_error == 'I cannot fulfill this request with the available tools (empty plan).'
                display_content = "Sorry, I couldn't determine how to handle that request with the tools I have available."
              else
                display_content = original_error
              end
            when :pending
              display_content = "Task pending... Job ID: #{content[:job_id]}" # Changed workflow_id to job_id
              if content[:message] then display_content << " - #{content[:message]}"; end
            else
              display_content = "Agent response (unknown status): #{content.inspect}"
            end
          elsif content.is_a?(Hash) && content.key?(:tool_name)
            display_content = "Tool request: #{content[:tool_name]}"
            if content[:params] && !content[:params].empty?
              display_content += ' with parameters'
            end
          elsif content.is_a?(Hash) && (content.key?(:result) || content.key?(:error))
            if content[:error]
              display_content = "Tool error: #{content[:error]}"
            elsif content[:result]
              result_str = content[:result].is_a?(String) ? content[:result] : content[:result].inspect
              display_content = "Tool result: #{result_str}"
            else
              display_content = "Tool response: #{content.inspect}"
            end
          elsif content.is_a?(Array)
            display_content = "Agent response (array): #{content.inspect}"
          else
            display_content = content.to_s
          end
          display_content.to_s
        end

        def summarize_session(session_object)
          return 'Invalid session object' unless session_object.is_a?(ADK::Session)

          created_at_formatted = session_object.created_at.strftime('%b %d, %Y %H:%M')
          updated_at_formatted = session_object.updated_at.strftime('%b %d, %Y %H:%M')
          event_count = session_object.events&.count || 0
          messages_text = event_count == 1 ? 'message' : 'messages'
          preview_text = 'Session started'
          if event_count.zero?
            preview_text = "Empty session (created #{created_at_formatted})"
          else
            first_user_text_event = session_object.events.find do |event|
              event.role == :user && event.content.is_a?(String) && !event.content.strip.empty?
            end
            if first_user_text_event
              words = first_user_text_event.content.strip.split(/\s+/)
              preview = words.take(10).join(' ')
              preview_text = "#{preview}#{words.size > 10 ? '...' : ''}"
            elsif session_object.events.any? { |e| e.role == :user }
              preview_text = 'Contains non-text user messages'
            else
              preview_text = 'Agent-initiated session'
            end
          end
          "Chat from #{created_at_formatted} (Last active: #{updated_at_formatted}) (#{event_count} #{messages_text}): #{preview_text}"
        end

        def pretty_json(object)
          begin
            JSON.pretty_generate(object)
          rescue => e
            object.inspect
          end
        end

        # --- START: MERMAID HELPERS (Corrected for delegate_task rich result) ---
        def generate_mermaid_sequence_diagram(final_agent_event_content, original_user_input)
          return '' unless final_agent_event_content.is_a?(Hash)

          mermaid_def = ['sequenceDiagram']
          participants = Set.new
          # Initial call: current_agent_name is just "Agent"
          collect_participants_recursive(final_agent_event_content, participants, 'Agent')

          participants.each { |p| mermaid_def << "  participant #{p}" }

          mermaid_def << "  User->>Agent: #{escape_mermaid_label(original_user_input)}"
          # Initial call: current_agent_is "Agent", final_recipient_is "User"
          append_plan_to_mermaid_recursive(final_agent_event_content, 'Agent', 'User', mermaid_def)

          mermaid_def.join("\n")
        end

        def collect_participants_recursive(event_content, participants_set, current_agent_alias = 'Agent')
          participants_set.add('User')
          participants_set.add(current_agent_alias)

          plan_details = event_content[:plan_details]
          return unless plan_details.is_a?(Array)

          plan_details.each do |step_in_plan|
            tool_name_str = step_in_plan[:tool_name]&.to_s
            participants_set.add("Tool(#{tool_name_str})") if tool_name_str && !tool_name_str.empty?

            if step_in_plan[:tool_name]&.to_sym == :delegate_task &&
               step_in_plan == plan_details.last &&
               event_content.dig(:result, :status) == :success &&
               event_content.dig(:result, :result).is_a?(Hash) &&
               event_content.dig(:result, :result, :plan_details)

              delegated_agent_full_content = event_content.dig(:result, :result)
              target_agent_name_param = step_in_plan.dig(:params,
                                                         :target_agent_name) || step_in_plan.dig(:params,
                                                                                                 'target_agent_name')
              delegated_agent_actual_name = delegated_agent_full_content.dig(:name)&.to_s || target_agent_name_param || 'DelegatedAgent'
              delegated_agent_participant_alias = "Agent(#{delegated_agent_actual_name})"

              participants_set.add(delegated_agent_participant_alias)
              collect_participants_recursive(delegated_agent_full_content, participants_set,
                                             delegated_agent_participant_alias)
            end
          end
        end

        def append_plan_to_mermaid_recursive(event_content, current_agent_participant_name, final_recipient_name,
                                             mermaid_def_array)
          plan_details = event_content[:plan_details]
          return unless plan_details.is_a?(Array)

          plan_details.each_with_index do |step_in_plan, index|
            tool_name_str = step_in_plan[:tool_name]&.to_s || 'UnknownTool'
            tool_participant = "Tool(#{tool_name_str})"

            params_summary = summarize_for_mermaid(step_in_plan[:params]) # Removed max_length override
            mermaid_def_array << "  #{current_agent_participant_name}->>#{tool_participant}: Call #{tool_name_str} with #{params_summary}"

            original_tool_output_for_this_step = step_in_plan[:result]

            if step_in_plan == plan_details.last &&
               step_in_plan[:tool_name]&.to_sym == :delegate_task &&
               event_content.dig(:result, :status) == :success &&
               event_content.dig(:result, :result).is_a?(Hash) &&
               event_content.dig(:result, :result, :plan_details)

              original_tool_output_for_this_step = event_content[:result][:result]
            end

            if original_tool_output_for_this_step.is_a?(Hash) &&
               original_tool_output_for_this_step.key?(:plan_details) &&
               step_in_plan[:tool_name]&.to_sym == :delegate_task

              delegated_agent_content = original_tool_output_for_this_step
              target_agent_name_param = step_in_plan.dig(:params,
                                                         :target_agent_name) || step_in_plan.dig(:params,
                                                                                                 'target_agent_name')
              effective_delegated_name = delegated_agent_content[:name]&.to_s || target_agent_name_param&.to_s || 'DelegatedAgent'
              delegated_agent_participant = "Agent(#{effective_delegated_name})"
              task_for_delegated = summarize_for_mermaid(step_in_plan.dig(:params,
                                                                          :task) || step_in_plan.dig(:params, 'task'))
              mermaid_def_array << "  #{tool_participant}->>#{delegated_agent_participant}: Run task: #{task_for_delegated || 'Delegated Task'}"
              append_plan_to_mermaid_recursive(delegated_agent_content, delegated_agent_participant, tool_participant,
                                               mermaid_def_array)
              delegated_outcome_summary = if delegated_agent_content[:status] == :success
                                            "Delegated success: #{summarize_for_mermaid(delegated_agent_content[:result])}"
                                          elsif delegated_agent_content[:status] == :error
                                            "Delegated error: #{summarize_for_mermaid(delegated_agent_content[:error_message])}"
                                          else
                                            "Delegated status: #{delegated_agent_content[:status]}"
                                          end
              mermaid_def_array << "  #{tool_participant}-->>#{current_agent_participant_name}: #{delegated_outcome_summary}"
            elsif original_tool_output_for_this_step.is_a?(Hash)
              status = original_tool_output_for_this_step[:status]&.to_s || 'unknown'
              case status.to_sym
              when :success
                result_value = original_tool_output_for_this_step[:result]
                if result_value.is_a?(String) && result_value == '[Complex Result Structure]'
                  actual_result = event_content[:result][:result]
                  if actual_result.is_a?(String)
                    mermaid_def_array << "  #{tool_participant}-->>#{current_agent_participant_name}: Result: \"#{actual_result}\""
                  else
                    mermaid_def_array << "  #{tool_participant}-->>#{current_agent_participant_name}: Result: [Complex Result Structure]"
                  end
                else
                  result_summary = summarize_for_mermaid(original_tool_output_for_this_step[:result])
                  mermaid_def_array << "  #{tool_participant}-->>#{current_agent_participant_name}: Result: #{result_summary}"
                end
              when :error
                error_summary = summarize_for_mermaid(original_tool_output_for_this_step[:error_message] || 'Unknown Error')
                mermaid_def_array << "  #{tool_participant}-->>#{current_agent_participant_name}: Error: #{error_summary}"
              when :pending
                job_id_summary = summarize_for_mermaid(original_tool_output_for_this_step[:job_id] || 'N/A') # Changed from workflow_id
                message_summary = original_tool_output_for_this_step[:message] ? " (#{summarize_for_mermaid(original_tool_output_for_this_step[:message])})" : ''
                mermaid_def_array << "  #{tool_participant}-->>#{current_agent_participant_name}: Pending (Job ID: #{job_id_summary})#{message_summary}"
              else
                mermaid_def_array << "  #{tool_participant}-->>#{current_agent_participant_name}: Result (Status: #{status}): #{summarize_for_mermaid(original_tool_output_for_this_step)}"
              end
            else
              mermaid_def_array << "  #{tool_participant}-->>#{current_agent_participant_name}: Malformed Result: #{summarize_for_mermaid(original_tool_output_for_this_step)}"
            end
          end

          final_response_summary = ''
          if event_content[:status] == :success
            core_result = if event_content[:result].is_a?(Hash) && event_content[:result][:status] == :success && event_content[:result].key?(:result)
                            event_content[:result][:result]
                          else
                            event_content[:result]
                          end
            if core_result.is_a?(String) && core_result == '[Complex Result Structure]'
              actual_result = event_content[:result][:result]
              if actual_result.is_a?(String)
                final_response_summary = "Final Result: \"#{actual_result}\""
              else
                final_response_summary = 'Final Result: [Complex Result Structure]'
              end
            else
              final_response_summary = "Final Result: #{summarize_for_mermaid(core_result)}"
            end
          elsif event_content[:status] == :error
            final_response_summary = "Final Error: #{summarize_for_mermaid(event_content[:error_message])}"
          elsif event_content[:status] == :pending
            job_id_summary = summarize_for_mermaid(event_content[:job_id]) # Changed from workflow_id
            message_summary = event_content[:message] ? " - #{summarize_for_mermaid(event_content[:message])}" : ''
            final_response_summary = "Task Pending: Job ID #{job_id_summary}#{message_summary}"
          else
            final_response_summary = "Final Response (Status: #{event_content[:status]}): #{summarize_for_mermaid(event_content)}"
          end
          mermaid_def_array << "  #{current_agent_participant_name}-->>#{final_recipient_name}: #{final_response_summary}"
        end

        def summarize_for_mermaid(data, max_length = 700)
          return 'nil' if data.nil?

          raw_summary_str = ''
          if data.is_a?(Hash)
            if data.key?(:result) && data[:result].is_a?(Hash) && data[:result].key?(:content)
              content_str = data[:result][:content].to_s
              content_preview = content_str.length > 50 ? "#{content_str[0..50]}..." : content_str
              raw_summary_str = "{status: #{data[:status]}, result: {content: \"#{content_preview}\"}}"
            else
              items = data.map do |k, v_raw|
                v_str = if v_raw.is_a?(Hash)
                          "{#{v_raw.keys.take(3).join(', ')}#{v_raw.keys.size > 3 ? ', ...' : ''}}"
                        elsif v_raw.is_a?(String) && v_raw.length <= 30 && !v_raw.match?(/[:;()`"'\n\\]/)
                          v_raw
                        elsif v_raw.is_a?(Array) && v_raw.size <= 3
                          v_raw.inspect
                        elsif v_raw.is_a?(Array)
                          "[#{v_raw.size} items]"
                        else
                          v_raw.inspect
                        end
                "#{k}: #{v_str}"
              end
              raw_summary_str = "{#{items.join(', ')}}"
            end
          elsif data.is_a?(Array)
            if data.size <= 5
              items_str = data.map do |item|
                if item.is_a?(Hash)
                  "{#{item.keys.take(2).join(', ')}#{item.keys.size > 2 ? ', ...' : ''}}"
                else
                  item.inspect
                end
              end.join(', ')
              raw_summary_str = "[#{items_str}]"
            else
              items_str = data.take(3).map do |item|
                if item.is_a?(Hash)
                  "{#{item.keys.take(2).join(', ')}#{item.keys.size > 2 ? ', ...' : ''}}"
                else
                  item.inspect
                end
              end.join(', ')
              raw_summary_str = "[#{items_str}, ... (#{data.size} total items)]"
            end
          else
            raw_summary_str = data.to_s
          end
          escaped_summary = escape_mermaid_label(raw_summary_str)
          if escaped_summary.length > max_length
            final_summary = escaped_summary[0...(max_length - 3)] + '...'
          else
            final_summary = escaped_summary
          end
          final_summary
        end

        # MODIFIED: Simplified escape_mermaid_label
        def escape_mermaid_label(text)
          return '' if text.nil?

          s = text.to_s
          s = s.gsub(/#/, '#hash;') # Escape # to prevent it being a comment/directive
          s = s.gsub(/"/, '#quot;') # For quoted strings within messages; Mermaid prefers this over "
          s = s.gsub(/;/, '#semi;') # Semicolons can end Mermaid statements

          # Replace newlines with <br> for explicit line breaks in Mermaid labels
          s = s.gsub(/\n/, '<br>')

          # Escape sequences that might be misinterpreted as Mermaid diagram arrows/lines
          s = s.gsub(/->>/, '->>')
          s = s.gsub(/-->>/, '-->>')
          s = s.gsub(/->/, '->')
          s = s.gsub(/--/, '- -') # also to prevent '--' being parsed as start of solid line in some contexts

          # Parentheses and backticks are often fine in message text, remove aggressive escaping for them for now.
          # Colons are fine.
          s
        end
        # --- END MERMAID HELPERS ---
      end # end helpers

      # --- Private Helper Methods ---
      private

      def synchronize_persistent_agents
        return unless @definition_store&.check_connection

        @logger.info('Synchronizing persistent agent statuses on startup...')
        begin
          definitions = @definition_store.list_definitions
          definitions.each do |definition|
            agent_name = definition[:name]
            if definition[:persistent_status] == 'running'
              if @agents.key?(agent_name)
                logger.info("Agent '#{agent_name}' is already running (in @agents), no action needed for sync.")
              else
                logger.info("Agent '#{agent_name}' has persistent_status='running', attempting to start it...")
                started_agent = _start_agent(agent_name)
                unless started_agent
                  logger.error("Failed to auto-start agent '#{agent_name}' during sync. Its persistent_status remains 'running'.")
                end
              end
            elsif definition[:persistent_status] == 'stopped' && @agents.key?(agent_name)
              logger.warn("Agent '#{agent_name}' has persistent_status='stopped' but was found in @agents. Stopping it now.")
              _stop_agent(agent_name)
            end
          end
          @logger.info('Finished synchronizing persistent agent statuses.')
        rescue ADK::DefinitionStore::StoreError => e
          @logger.error("Store error during persistent agent synchronization: #{e.message}")
        rescue => e
          @logger.error("Unexpected error during persistent agent synchronization: #{e.class} - #{e.message}")
          @logger.error(e.backtrace.first(5).join("\n"))
        end
      end

      def _stop_agent(name)
        agent = @agents[name]
        if agent
          logger.info("Stopping agent '#{name}'...")
          begin
            agent.stop
            @agents.delete(name)
            if @definition_store
              @definition_store.update_definition(name, { persistent_status: 'stopped' })
              logger.info("Agent '#{name}' persistent_status updated to 'stopped' in store.")
            else
              logger.warn("Definition store not available, cannot update persistent_status for agent '#{name}'.")
            end
            logger.info("Agent '#{name}' stopped.")
            true
          rescue => e
            logger.error("Error stopping agent '#{name}': #{e.message}")
            false
          end
        else
          logger.warn("Attempted to stop non-running agent: '#{name}'. Ensuring persistent_status is 'stopped'.")
          if @definition_store
            begin
              definition = @definition_store.get_definition(name)
              if definition && definition[:persistent_status] != 'stopped'
                @definition_store.update_definition(name, { persistent_status: 'stopped' })
                logger.info("Agent '#{name}' was not running in memory, persistent_status ensured as 'stopped' in store.")
              elsif !definition
                logger.warn("Agent definition for '#{name}' not found in store while trying to ensure stopped status.")
              end
            rescue ADK::DefinitionStore::StoreError => e
              logger.error("Store error while ensuring agent '#{name}' persistent_status is 'stopped': #{e.message}")
            end
          else
            logger.warn("Definition store not available, cannot ensure persistent_status for agent '#{name}'.")
          end
          true
        end
      end

      def _start_agent(name)
        return @agents[name] if @agents.key?(name)

        halt 503, 'Definition Store unavailable.' unless @definition_store
        agent_definition = nil
        begin
          agent_definition = @definition_store.get_definition(name)
        rescue ADK::DefinitionStore::StoreError => e
          logger.error("Store error fetching definition for starting agent '#{name}': #{e.message}")
          return nil
        end

        unless agent_definition
          logger.error("Agent definition not found for '#{name}', cannot start.")
          return nil
        end

        agent_description = agent_definition[:description]
        selected_tool_names = agent_definition[:tools].map(&:to_sym)
        model_name = agent_definition[:model]
        fallback_mode_sym = agent_definition[:fallback_mode]
        mcp_servers_json = agent_definition[:mcp_servers_json]
        agent_instruction = agent_definition[:instruction]

        mcp_server_count = 0
        begin
          parsed_mcp = JSON.parse(mcp_servers_json)
          mcp_server_count = parsed_mcp.is_a?(Array) ? parsed_mcp.count : 0
        rescue JSON::ParserError
        end
        logger.info("Attempting to start agent '#{name}' (Model: #{model_name}, Fallback: #{fallback_mode_sym}, MCP: #{mcp_server_count} servers)... Selected Tools: #{selected_tool_names.inspect}")

        # Convert hash to ADK::AgentDefinition object
        definition_obj = ADK::AgentDefinition.from_hash(agent_definition)
        unless definition_obj
          logger.error("Failed to convert agent definition hash to ADK::AgentDefinition object for '#{name}'")
          return nil
        end

        agent = ADK::Agent.new(
          definition: definition_obj,
          session_service: @session_service
        )

        selected_tool_names.each do |tn|
          inst = ADK::GlobalToolManager.create_instance(tn)
          if inst
            logger.debug("Adding selected native tool: #{tn}")
            agent.add_tool(inst)
          else
            logger.debug("Tool '#{tn}' selected but not found in GlobalToolManager (assuming MCP tool).")
          end
        end

        agent.start
        @agents[name] = agent
        if @definition_store
          @definition_store.update_definition(name, { persistent_status: 'running' })
          logger.info("Agent '#{name}' persistent_status updated to 'running' in store.")
        else
          logger.warn("Definition store not available, cannot update persistent_status for agent '#{name}'.")
        end
        logger.info("Agent '#{name}' started successfully.")
        agent
      rescue StandardError => e
        logger.error("Failed to start agent '#{name}': #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        @agents.delete(name)
        if @definition_store
          begin
            @definition_store.update_definition(name, { persistent_status: 'stopped' })
            logger.info("Agent '#{name}' failed to start, persistent_status set to 'stopped' in store.")
          rescue ADK::DefinitionStore::StoreError => se
            logger.error("Store error while setting persistent_status to 'stopped' for failed agent '#{name}': #{se.message}")
          end
        end
        nil
      end
    end # End App class
  end # End Web module
end # End ADK module
