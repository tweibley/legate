# File: lib/adk/web/app.rb
# frozen_string_literal: true

# STDOUT.sync = true # Uncomment for immediate output flushing if needed
require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/custom_logger' # For using helpers Sinatra::CustomLogger
require 'sinatra/reloader'
require 'slim'
require 'json'
require_relative 'sass_compiler'
require 'rack/utils' # For escape_html
require 'redis'
require 'securerandom' # For session secret
require 'sidekiq/api'

# --- Load ADK Components ---
# Load dependencies in a sensible order
require_relative '../event'   # Load Event first as Session uses it
require_relative '../session' # Load Session next
require_relative '../tool_context' # <--- ADDED
require_relative '../agent' # Agent needs default model constant
require_relative '../tool'
require_relative '../tool_registry'
require_relative '../session_service/in_memory' # Load Service
require_relative '../session_service/redis' # Load Redis Service
require_relative '../global_tool_manager' # <-- ADDED
# Explicitly require all tools
require_relative '../tools/echo'
require_relative '../tools/calculator'
require_relative '../tools/cat_facts'
require_relative '../tools/random_number_tool'
require_relative '../tools/agent_tool' # Load AgentTool
require_relative '../tools/base_async_job_tool' # <--- ADDED
require_relative '../tools/check_job_status_tool' # <--- ADDED
require_relative '../tools/sleepy_tool' # <--- ADDED for SleepyTool

# Load dotenv for development AFTER other requires if needed
if ENV['RACK_ENV'] == 'development' || Sinatra::Base.development?
  begin; require 'dotenv/load'; rescue LoadError; end
end

module ADK
  module Web
    # Web interface for ADK
    class App < Sinatra::Base
      helpers Sinatra::CustomLogger # Use ADK.logger via 'logger' helper

      configure :development do
        register Sinatra::Reloader
        # Optional: Increase logging level specifically for development web server
        # ADK.logger.level = Logger::DEBUG if ADK.logger
      end

      # Configure the logger and session support for all environments
      configure do
        set :logger, ADK.logger # Use the central ADK logger for Sinatra's logging
        # --- Enable Sinatra Sessions ---
        enable :sessions
        # IMPORTANT: Set a strong secret key in production (e.g., via ENV variable)
        set :session_secret, ENV['SESSION_SECRET'] || SecureRandom.hex(64)
      end

      # --- Sinatra Settings ---
      set :root, File.expand_path('../../..', __dir__)
      set :views, File.expand_path('../views', __FILE__)
      set :public_folder, File.expand_path('../public', __FILE__)
      set :slim, pretty: true

      # --- Constants ---
      REDIS_AGENT_HASH_PREFIX = "adk:agent:"
      REDIS_AGENTS_SET_KEY = "adk:agents:all_names"
      AVAILABLE_MODELS = ['gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-1.5-pro', 'gemini-1.0-pro'].freeze

      # --- Instance Variables ---
      # Initialize agent registry, Redis client, AND Session Service
      def initialize
        super
        # In-memory store for LIVE/RUNNING agent *runtime* instances
        @agents = {}
        # Session service to manage conversation state
        @session_service = ADK::SessionService::InMemory.new
        # Redis client for persistent agent *definitions*
        begin
          @redis = Redis.new # Assumes default connection
          @redis.ping
          logger.info("Successfully connected to Redis.")
        rescue Redis::CannotConnectError => e
          logger.error("Could not connect to Redis. Persistence disabled. #{e.message}")
          @redis = nil
        end
        # Compile Sass on startup
        SassCompiler.compile_all
      end

      # Helper to generate Redis key for an agent definition hash
      def agent_redis_key(name)
        "#{REDIS_AGENT_HASH_PREFIX}#{name}"
      end

      # --- Sinatra Helpers ---
      helpers do
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
      end # end helpers

      # --- Routes ---

      get '/' do
        logger.debug("GET / route handler entered")
        slim :index
      end

      # --- Agent Definition Management Routes ---
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

      post '/agents' do
        halt 503, "Redis unavailable." unless @redis
        agent_name = params['name']&.strip; agent_description = params['description']&.strip
        selected_tools = params['tools'] || []; selected_model = params['model']&.strip
        selected_fallback = params['fallback_mode'] || 'error' # <-- Get fallback mode, default to error
        model_to_save = selected_model && !selected_model.empty? ? selected_model : ADK::Agent::DEFAULT_MODEL

        if agent_name.nil? || agent_name.empty? || agent_description.nil? || agent_description.empty?
          status 400; halt "<div class='notification is-danger'>Name and description required.</div>"; end
        key = agent_redis_key(agent_name)
        if @redis.sismember(REDIS_AGENTS_SET_KEY, agent_name)
          status 409; halt "<div class='notification is-warning'>Agent '#{agent_name}' already exists.</div>"; end
        begin
          tools_json = selected_tools.to_json
          @redis.multi { |m|
            m.hset(key, 'description', agent_description);
            m.hset(key, 'tools', tools_json);
            m.hset(key, 'model', model_to_save);
            m.hset(key, 'fallback_mode', selected_fallback) # <-- Save fallback mode
            m.sadd(REDIS_AGENTS_SET_KEY, agent_name)
          }
          logger.info("Agent '#{agent_name}' definition saved (Model: #{model_to_save}, Tools: #{selected_tools}, Fallback: #{selected_fallback})") # <-- Log fallback
        rescue Redis::BaseError => e; logger.error("Redis error: #{e.message}"); halt 500, "DB Error";
        rescue JSON::GeneratorError => e; logger.error("JSON error: #{e.message}"); halt 500, "Internal Error"; end
        content_type :html
        agent_data = { name: agent_name, description: agent_description, running: false,
                       configured_tools: selected_tools, model: model_to_save, fallback_mode: selected_fallback } # <-- Pass to partial
        # Pass available tools needed by the partial for rendering tool links/descriptions
        available_tools = ADK::GlobalToolManager.list_all_tools
        agent_row_html = slim(:_agent_row, layout: false,
                                           locals: { agent_info: agent_data, available_tools: available_tools })
        oob_remove_message_html = "<tr id='no-agents-row' hx-swap-oob='true'></tr>"
        agent_row_html + oob_remove_message_html
      end

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

      # Agent Detail Page
      get '/agents/:name' do |name|
        halt 503, "Redis unavailable." unless @redis
        key = agent_redis_key(name)
        # --- Fetch fallback_mode along with other fields ---
        redis_agent_data = @redis.hmget(key, 'description', 'tools', 'model', 'fallback_mode')
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]
        loaded_model = redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL
        fallback_mode = redis_agent_data[3] || 'error' # <-- Get fallback, default to 'error'

        unless description then halt 404,
                                     slim(:error_404,
                                          locals: { title: "Agent Not Found",
                                                    message: "Definition for '#{name}' not found." });
        end

        is_running = @agents.key?(name)
        # --- Include fallback_mode in view data ---
        @view_agent_data = { name: name, description: description, running: is_running,
                             model: loaded_model, fallback_mode: fallback_mode }
        configured_tool_names_str = [];
        begin tools_json_string && configured_tool_names_str = JSON.parse(tools_json_string) rescue []; end

        # --- Get tool info from registry for configured tools ---
        all_available_tools_list = ADK::GlobalToolManager.list_all_tools
        @configured_tool_info = configured_tool_names_str.map { |tn|
          all_available_tools_list.find { |t| t[:name].to_s == tn }
        }.compact
        logger.debug("Agent '#{name}' configured tool info: #{@configured_tool_info.inspect}")

        if is_running
          @agent = @agents[name]
          @view_agent_data[:model] = @agent.model_name
          # --- Get fallback mode from running agent instance if available ---
          @view_agent_data[:fallback_mode] = @agent.fallback_mode.to_s if @agent.respond_to?(:fallback_mode)

          # Ensure the live agent's tools are used for display if running
          live_agent_tool_names = @agent.tools.map(&:name)
          @configured_tool_info = live_agent_tool_names.map { |tn|
            all_available_tools_list.find { |t| t[:name] == tn }
          }.compact
          logger.debug("Agent '#{name}' live tool info: #{@configured_tool_info.inspect}")
        else
          # Create a temporary agent instance just for displaying configured tools
          # --- Pass fallback_mode to temp agent initializer ---
          temp_agent_for_view = ADK::Agent.new(name: name, description: description,
                                               model_name: loaded_model, fallback_mode: fallback_mode.to_sym)
          configured_tool_names_str.map(&:to_sym).each { |tool_name|
            inst = ADK::GlobalToolManager.create_instance(tool_name);
            if inst then temp_agent_for_view.add_tool(inst);
            else logger.warn("Tool '#{tool_name}' not found for display."); end
          }
          # Also include implicitly added check_workflow_status if applicable
          if temp_agent_for_view.tools.any? { |t| t.name == :check_workflow_status }
            status_tool_info = all_available_tools_list.find { |t| t[:name] == :check_workflow_status }
            @configured_tool_info << status_tool_info if status_tool_info && !@configured_tool_info.include?(status_tool_info)
          end
          @agent = temp_agent_for_view # For view, not in @agents
        end
        slim :agent
      end

      # --- Agent Inline Editing Routes ---
      get '/agents/:name/edit/:field' do |name, field|
        supported_fields = ['description', 'model', 'tools', 'fallback']
        halt 404, "Editing field '#{field}' not supported." unless supported_fields.include?(field)
        halt 503, "Redis unavailable." unless @redis
        key = agent_redis_key(name); halt 404 unless @redis.exists?(key)

        # --- Refactored: Fetch fields explicitly and build hash ---
        fields_to_fetch = ['description', 'model', 'tools', 'fallback_mode']
        redis_values = @redis.hmget(key, *fields_to_fetch)
        agent_definition = Hash[fields_to_fetch.zip(redis_values)]

        agent_data = {
          name: name,
          description: agent_definition['description'],
          model: agent_definition['model'],
          fallback_mode: agent_definition['fallback_mode'] || 'error' # Default if nil
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
          locals[:all_available_tools] = ADK::GlobalToolManager.list_all_tools
        end

        # Render the correct partial
        slim :"_edit_agent_#{field}", layout: false, locals: locals
      end

      get '/agents/:name/display/:field' do |name, field|
        supported_fields = ['description', 'model', 'tools', 'fallback']
        halt 404, "Displaying field '#{field}' not supported." unless supported_fields.include?(field)
        halt 503, "Redis unavailable." unless @redis
        key = agent_redis_key(name); halt 404 unless @redis.exists?(key)
        redis_data = @redis.hmget(key, 'description', 'model', 'tools', 'fallback_mode')
        response_locals = {};
        response_locals[:agent_data] =
          { name: name, description: redis_data[0], model: redis_data[1], fallback_mode: redis_data[3] || 'error' }
        if field == 'tools'
          tools_json_string = redis_data[2];
          configured_tool_names_str = [];
          begin tools_json_string && configured_tool_names_str = JSON.parse(tools_json_string) rescue []; end
          all_tools = ADK::GlobalToolManager.list_all_tools
          response_locals[:configured_tools] = configured_tool_names_str.map { |tn|
            all_tools.find { |t| t[:name].to_s == tn }
          }.compact
        end
        slim :"_display_agent_#{field}", layout: false, locals: response_locals
      end

      put '/agents/:name/update/:field' do |name, field|
        supported_fields = ['description', 'model', 'tools', 'fallback']
        halt 404, "Updating field '#{field}' not supported." unless supported_fields.include?(field)
        halt 503, "Redis unavailable." unless @redis
        key = agent_redis_key(name); halt 404 unless @redis.exists?(key)
        redis_field_to_update = field == 'fallback' ? 'fallback_mode' : field
        new_value_to_save = nil; response_locals = {}
        agent_data_hash = { name: name } # Needed for display partial URLs

        if field == 'tools'
          all_available_tools_list = ADK::GlobalToolManager.list_all_tools
          selected_tools = params['tools'] || []; valid_available_tools = all_available_tools_list.map { |t|
            t[:name].to_s
          }
          validated_tools = selected_tools.select { |st|
            if valid_available_tools.include?(st) then true else logger.warn("Invalid tool '#{st}' submitted.");
                                                                 false; end
          }
          new_value_to_save = validated_tools.to_json
          # Prepare locals for _display_agent_tools
          agent_data_hash[:description] = @redis.hget(key, 'description')
          agent_data_hash[:model] = @redis.hget(key, 'model')
          response_locals[:agent_data] = agent_data_hash
          response_locals[:configured_tools] = validated_tools.map { |tn|
            all_available_tools_list.find { |t| t[:name].to_s == tn }
          }.compact
        elsif field == 'fallback'
          new_value_to_save = params['value']&.strip
          logger.debug("Received fallback update for '#{name}'. Value: '#{new_value_to_save}'") # <-- LOGGING
          unless ['error', 'echo'].include?(new_value_to_save)
            logger.warn("Update failed for '#{name}', field '#{field}': Invalid value '#{new_value_to_save}'.")
            redis_data = @redis.hmget(key, 'description', 'model', 'fallback_mode')
            response_locals[:agent_data] =
              { name: name, description: redis_data[0], model: redis_data[1], fallback_mode: redis_data[2] || 'error' }
            halt 400, slim(:"_display_agent_#{field}", layout: false, locals: response_locals)
          end
          agent_data_hash[:description] = @redis.hget(key, 'description')
          agent_data_hash[:model] = @redis.hget(key, 'model')
          agent_data_hash[:fallback_mode] = new_value_to_save
          response_locals[:agent_data] = agent_data_hash
          logger.debug("Prepared response_locals for display: #{response_locals.inspect}") # <-- LOGGING
        else # description or model
          new_value_to_save = params['value']&.strip
          if new_value_to_save.nil? || new_value_to_save.empty?
            logger.warn("Update failed for '#{name}', field '#{field}': Value empty.")
            redis_data = @redis.hmget(key, 'description', 'model', 'fallback_mode')
            response_locals[:agent_data] =
              { name: name, description: redis_data[0], model: redis_data[1], fallback_mode: redis_data[2] || 'error' }
            halt 400, slim(:"_display_agent_#{field}", layout: false, locals: response_locals)
          end
          agent_data_hash[:description] = (field == 'description' ? new_value_to_save : @redis.hget(key, 'description'))
          agent_data_hash[:model] = (field == 'model' ? new_value_to_save : @redis.hget(key, 'model'))
          agent_data_hash[:fallback_mode] = @redis.hget(key, 'fallback_mode') || 'error'
          response_locals[:agent_data] = agent_data_hash
        end

        begin # Update Redis
          @redis.hset(key, redis_field_to_update, new_value_to_save)
          logger.info("Updated agent '#{name}', field '#{redis_field_to_update}' to '#{new_value_to_save}'") # <-- LOGGING
          slim :"_display_agent_#{field}", layout: false, locals: response_locals # Render display partial
        rescue Redis::BaseError => e;
          logger.error("Redis error updating: #{e.message}"); halt 500, "Error updating definition.";
        rescue JSON::GeneratorError => e;
          logger.error("JSON error updating tools: #{e.message}"); halt 500, "Error saving configuration."; end
      end
      # --- End Agent Inline Editing Routes ---

      # --- Agent Runtime Routes ---
      post '/agents/:name/start' do
        # ... (existing start logic - unchanged by session refactor) ...
        name = params[:name]; agent_data_for_view = nil
        if @agents.key?(name) then logger.warn("Agent '#{name}' running."); agent_data_for_view = @agents[name]; else
                                                                                                                   halt 503,
                                                                                                                        "Redis unavailable." unless @redis;
                                                                                                                   key = agent_redis_key(name)
                                                                                                                   # --- Fetch fallback_mode when starting ---
                                                                                                                   redis_agent_data = @redis.hmget(
                                                                                                                     key, 'description', 'tools', 'model', 'fallback_mode'
                                                                                                                   );
                                                                                                                   agent_description, tools_json, model_name, fallback_mode_str = redis_agent_data[0], redis_agent_data[1],
                                                                                                                                                                                   (redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL),
                                                                                                                                                                                   redis_agent_data[3]
                                                                                                                   fallback_mode_sym = (fallback_mode_str == 'echo') ? :echo : :error # Convert to symbol, default error

                                                                                                                   unless agent_description then logger.error("Def not found: '#{name}'");
                                                                                                                                                 halt 404;
                                                                                                                   end
                                                                                                                   begin logger.info("Starting agent '#{name}' (Model: #{model_name}, Fallback: #{fallback_mode_sym})...");
                                                                                                                         # --- Pass fallback_mode to initializer ---
                                                                                                                         agent = ADK::Agent.new(
                                                                                                                           name: name, description: agent_description, model_name: model_name, fallback_mode: fallback_mode_sym
                                                                                                                         );
                                                                                                                         tool_names = [];
                                                                                                                         if tools_json && !tools_json.empty? then tool_names = JSON.parse(tools_json).map(&:to_sym) rescue [];
                                                                                                                         end;
                                                                                                                         tool_names.each { |tn|
                                                                                                                           inst = ADK::GlobalToolManager.create_instance(tn);
                                                                                                                           agent.add_tool(inst) if inst
                                                                                                                         };
                                                                                                                         agent.start;
                                                                                                                         @agents[name] =
                                                                                                                           agent;
                                                                                                                         agent_data_for_view = agent;
                                                                                                                         logger.info("Agent '#{name}' started.");
                                                                                                                   rescue StandardError => e;
                                                                                                                     logger.error("Failed start: #{e.message}");
                                                                                                                     halt 500;
                                                                                                                   end
        end; agent_status_fragments(agent_data_for_view)
      end

      post '/agents/:name/start/detail' do
        # ... (existing start logic - unchanged by session refactor) ...
        name = params[:name]; content_type :html; agent_data_for_view = nil
        if @agents.key?(name) then agent_data_for_view = @agents[name]; else
                                                                          halt 503, "Redis unavailable." unless @redis;
                                                                          key = agent_redis_key(name)
                                                                          # --- Fetch fallback_mode when starting (detail view) ---
                                                                          redis_agent_data = @redis.hmget(key,
                                                                                                          'description', 'tools', 'model', 'fallback_mode');
                                                                          agent_description, tools_json, model_name, fallback_mode_str = redis_agent_data[0], redis_agent_data[1],
                                                                                                                                         (redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL),
                                                                                                                                         redis_agent_data[3]
                                                                          fallback_mode_sym = (fallback_mode_str == 'echo') ? :echo : :error # Convert to symbol, default error

                                                                          unless agent_description then halt 404; end
                                                                          begin
                                                                            # --- Pass fallback_mode to initializer ---
                                                                            agent = ADK::Agent.new(name: name, description: agent_description, model_name: model_name,
                                                                                                   fallback_mode: fallback_mode_sym);
                                                                            tool_names = [];
                                                                            if tools_json && !tools_json.empty? then tool_names = JSON.parse(tools_json).map(&:to_sym) rescue [];
                                                                            end; tool_names.each { |tn|
                                                                              inst = ADK::GlobalToolManager.create_instance(tn);
                                                                              agent.add_tool(inst) if inst
                                                                            };
                                                                            agent.start;
                                                                            @agents[name] = agent;
                                                                            agent_data_for_view = agent
                                                                          rescue => e;
                                                                            logger.error("Failed start detail: #{e.message}");
                                                                            halt 500; end
        end; slim :_agent_status_controls, layout: false, locals: { agent_data: agent_data_for_view }
      end

      post '/agents/:name/stop' do
        # ... (existing stop logic - unchanged by session refactor) ...
        name = params[:name]; agent = @agents[name]; stopped_agent_data = nil
        if agent;
          description = agent.description;
          model = agent.model_name;
          tools = agent.tools.map(&:name);
          agent.stop;
          @agents.delete(name);
          stopped_agent_data = { name: name, description: description, running: false, model: model,
                                 configured_tools: tools };
          logger.info("Agent '#{name}' stopped.");
        else logger.warn("Stop non-running agent: '#{name}'.");
             key = agent_redis_key(name);
             redis_data = @redis&.hmget(key, 'description', 'tools', 'model') || ["N/A", nil, nil];
             description, tools_json, model = redis_data[0] || "N/A", redis_data[1], redis_data[2];
             configured_tools = [];
             if tools_json then configured_tools = JSON.parse(tools_json) rescue [];
             end;
             stopped_agent_data = { name: name, description: description, running: false, model: model,
                                    configured_tools: configured_tools };
        end
        agent_status_fragments(stopped_agent_data)
      end

      post '/agents/:name/stop/detail' do
        # ... (existing stop logic - unchanged by session refactor) ...
        name = params[:name]; content_type :html; stopped_agent_data = nil; agent = @agents[name]
        if agent;
          description = agent.description;
          model = agent.model_name;
          tools = agent.tools.map(&:name);
          agent.stop;
          @agents.delete(name);
          stopped_agent_data = { name: name, description: description, running: false, model: model,
                                 configured_tools: tools };
        else key = agent_redis_key(name);
             redis_data = @redis&.hmget(key, 'description', 'tools', 'model') || ["N/A", nil, nil];
             description, tools_json, model = redis_data[0] || "N/A", redis_data[1], redis_data[2];
             configured_tools = [];
             if tools_json then configured_tools = JSON.parse(tools_json) rescue [];
             end;
             stopped_agent_data = { name: name, description: description, running: false, model: model,
                                    configured_tools: configured_tools };
        end
        slim :_agent_status_controls, layout: false, locals: { agent_data: stopped_agent_data }
      end

      # --- Agent Interaction Routes (REFACTORED for Session) ---

      # Agent Chat Page (Manages Session)
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

      # Process Chat Message (Uses Session)
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

      # Execute Agent Task Directly (via JSON input) - REFACTORED for Context <-- MODIFIED
      post '/agents/:name/execute' do
        name = params[:name]; content_type :html
        agent = @agents[name]

        html_error = lambda do |message, code = 400|
                       halt code, format_execution_result_html({ status: :error, error_message: message }); end

        html_error.call("Error: Agent '#{name}' not found or not running.", 400) unless agent
        json_string = params['task_json'];
        html_error.call("Error: Missing 'task_json' data.", 400) unless json_string && !json_string.empty?
        task = nil;
        begin data = JSON.parse(json_string); task = data['task'];
              html_error.call("Error: Missing 'task' key in JSON.", 400) unless task;
        rescue JSON::ParserError => e;
          logger.error("Invalid JSON: #{e.message}"); html_error.call("Error: Invalid JSON format.", 400); end

        temp_session = nil
        begin
          logger.info("Agent '#{name}' executing direct task: #{task}")
          # Create temporary session using IN-MEMORY service
          temp_session = @session_service.create_session(app_name: name, user_id: 'direct_execute')
          # Call run_task with session context
          final_event_or_error = agent.run_task(session_id: temp_session.id, user_input: task,
                                                session_service: @session_service)
          logger.info("Agent '#{name}' direct execution result: #{final_event_or_error.inspect}")

          content_to_display = final_event_or_error.is_a?(ADK::Event) ? final_event_or_error.content : final_event_or_error
          format_execution_result_html(content_to_display)
        rescue => e
          logger.error "Error during direct agent execution for '#{name}': #{e.message}\n#{e.backtrace.join("\n")}"
          html_error.call("Error: Internal server error during task execution: #{e.message}", 500)
        ensure
          @session_service.delete_session(session_id: temp_session.id) if temp_session
        end
      end

      # --- Tool Routes (Unchanged) ---
      get('/tools') { @tools_list = ADK::GlobalToolManager.list_all_tools; slim :tools }
      get('/tools/:name') { |n|
        @tool = ADK::GlobalToolManager.create_instance(n.to_sym);
        if @tool then slim :tool else halt 404,
                                           slim(:error_404,
                                                locals: { title: "Tool Not Found", message: "Tool '#{n}' not found." });
        end
      }
      post '/tools/:name/execute' do |n|
        content_type :html; tool_name_sym = n.to_sym; logger.info("Executing Tool '#{n}' via form")
        submitted_params = params.reject { |k, _| ['splat', 'captures', 'name'].include?(k) }
        logger.debug("Params: #{submitted_params.inspect}")
        tool = ADK::GlobalToolManager.create_instance(tool_name_sym)
        unless tool;
          err_msg = "Tool '#{Rack::Utils.escape_html(n)}' not found.";
          halt 404, format_execution_result_html({ status: :error, error_message: err_msg }); end

        # --- Create dummy context for direct execution --- << ADDED >>
        dummy_context = ADK::ToolContext.new(session_id: "web_direct_#{SecureRandom.hex(4)}", user_id: 'web_user',
                                             app_name: 'web_tool_exec')

        begin
          symbolized_params = submitted_params.transform_keys(&:to_sym)
          logger.info("Attempting tool.execute: #{symbolized_params.inspect} with context: #{dummy_context.to_h.inspect}")
          # --- Pass context --- << MODIFIED >>
          result_hash = tool.execute(symbolized_params, dummy_context)

          logger.info("Tool execute returned: #{result_hash.inspect}")
          format_execution_result_html(result_hash)
        rescue ADK::Error, ArgumentError => e;
          logger.warn("Tool Error: #{e.message}");
          format_execution_result_html({ status: :error, error_message: e.message });
        rescue StandardError => e;
          logger.error("Unexpected Tool Error: #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}");
          format_execution_result_html({ status: :error, error_message: "Unexpected error: #{e.message}" }); end
      end

      # --- API Endpoints (Unchanged) ---
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
      get('/api/tools') { content_type :json; json tools: ADK::GlobalToolManager.list_all_tools }
    end # End App class
  end # End Web module
end # End ADK module
