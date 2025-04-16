# File: lib/adk/web/app.rb
# frozen_string_literal: true

# STDOUT.sync = true
require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/custom_logger'
require 'sinatra/reloader'
require 'slim'
require 'json'
require_relative 'sass_compiler'
require 'rack/utils' # For escape_html
require 'redis'

# --- Load ADK Components ---
# Ensure Agent is loaded first to get DEFAULT_MODEL constant
require_relative '../agent'
require_relative '../tool'
require_relative '../tool_registry'
# Explicitly require tools needed for default settings or direct use
require_relative '../tools/echo'
require_relative '../tools/calculator'
require_relative '../tools/cat_facts'
require_relative '../tools/random_number_tool'

# Load dotenv for development AFTER other requires if needed
if ENV['RACK_ENV'] == 'development' || Sinatra::Base.development?
  begin; require 'dotenv/load'; rescue LoadError; end
end

module ADK
  module Web
    # Web interface for ADK
    class App < Sinatra::Base
      helpers Sinatra::CustomLogger

      configure :development do
        register Sinatra::Reloader
      end

      # Configure the logger for Sinatra
      configure do
        # Set the logger for Sinatra
        set :logger, ADK.logger
      end

      set :root, File.expand_path('../../..', __dir__)
      set :views, File.expand_path('../views', __FILE__)
      set :public_folder, File.expand_path('../public', __FILE__)
      set :slim, pretty: true

      # Redis Keys Constants
      REDIS_AGENT_HASH_PREFIX = "adk:agent:"
      REDIS_AGENTS_SET_KEY = "adk:agents:all_names"

      # --- List of models for UI dropdown ---
      # TODO: Make this dynamically configurable if needed
      AVAILABLE_MODELS = ['gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-1.5-pro', 'gemini-1.0-pro'].freeze

      # Initialize agent registry (in-memory for running) and Redis client
      def initialize
        super
        @agents = {} # In-memory store for LIVE/RUNNING agents
        begin
          @redis = Redis.new # Assumes Redis running on localhost:6379
          @redis.ping # Check connection
          logger.info("Successfully connected to Redis.")
        rescue Redis::CannotConnectError => e
          logger.error("Could not connect to Redis. Persistence disabled. #{e.message}")
          @redis = nil # Disable Redis features if connection fails
        end

        # Compile Sass files on startup
        SassCompiler.compile_all
      end

      # Helper to generate Redis key for an agent hash
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

        # Helper for formatting tool/agent execution results into HTML
        def format_execution_result_html(result_data)
          html_parts = []
          notification_class = 'is-info' # Default

          overall_status = :success # Assume success initially
          if result_data.is_a?(Array)
            if result_data.any? { |h| h.is_a?(Hash) && h[:status] == :error }
              overall_status = :error
            elsif result_data.empty?
              overall_status = :warning
            end
          elsif result_data.is_a?(Hash)
            overall_status = result_data[:status] || :error
          else
            overall_status = :error
            result_data = { status: :error, error_message: "Unexpected result format: #{result_data.inspect}" } # Wrap it
          end

          notification_class = case overall_status
                               when :success then 'is-success'
                               when :error then 'is-danger'
                               else 'is-warning'
                               end

          if result_data.is_a?(Array)
            html_parts << "<p><strong>Multi-step Result:</strong></p><ol>"
            result_data.each_with_index do |step_hash, index|
              html_parts << "<li>"
              if step_hash.is_a?(Hash) && step_hash[:status] == :success
                html_parts << "<strong>Step #{index + 1} (Success):</strong> <pre>#{Rack::Utils.escape_html(step_hash[:result].to_s)}</pre>"
              elsif step_hash.is_a?(Hash) && step_hash[:status] == :error
                html_parts << "<strong>Step #{index + 1} (Error):</strong> <pre class='has-text-danger'>#{Rack::Utils.escape_html(step_hash[:error_message].to_s)}</pre>"
              else
                html_parts << "<strong>Step #{index + 1} (Unknown format):</strong> <pre>#{Rack::Utils.escape_html(step_hash.inspect)}</pre>"
              end
              html_parts << "</li>"
            end
            html_parts << "</ol>"
          elsif result_data.is_a?(Hash)
            if result_data[:status] == :success
              html_parts << "<p><strong>Result:</strong></p><pre>#{Rack::Utils.escape_html(result_data[:result].to_s)}</pre>"
            elsif result_data[:status] == :error
              html_parts << "<p><strong>Error:</strong></p><pre class='has-text-danger'>#{Rack::Utils.escape_html(result_data[:error_message].to_s)}</pre>"
            else
              html_parts << "<p><strong>Result (Unknown Status):</strong></p><pre>#{Rack::Utils.escape_html(result_data.inspect)}</pre>"
            end
          else # Should have been wrapped already
            html_parts << "<p><strong>Error:</strong> Unexpected result format.</p><pre>#{Rack::Utils.escape_html(result_data.inspect)}</pre>"
          end

          "<div class='notification #{notification_class} mt-4'>#{html_parts.join}</div>"
        end # end format_execution_result_html
      end # end helpers

      # --- Routes ---

      get '/' do
        logger.debug("GET / route handler entered")
        slim :index
      end

      # --- Agent Routes ---

      # List Agents Page
      get '/agents' do
        @view_agents = []
        if @redis
          agent_names = @redis.smembers(REDIS_AGENTS_SET_KEY)
          agent_data_list = @redis.pipelined do |pipe|
            agent_names.each do |name|
              # Fetch model along with other fields
              pipe.hmget(agent_redis_key(name), 'description', 'tools', 'model')
            end
          end

          agent_names.zip(agent_data_list).each do |name, data|
            description = data[0] || "N/A"
            tools_json = data[1]
            model = data[2] # Keep nil if not set in Redis
            configured_tools = []
            begin tools_json && configured_tools = JSON.parse(tools_json) rescue []; end
            is_running = @agents.key?(name)
            @view_agents << { name: name, description: description, running: is_running,
                              configured_tools: configured_tools, model: model } # Add model
          end
          @view_agents.sort_by! { |a| a[:name] }
        else
          logger.error("Redis unavailable during GET /agents")
        end

        @available_tools = ADK::ToolRegistry.list_tools
        @available_models = AVAILABLE_MODELS # Pass models for the form
        logger.debug("Available models for form: #{@available_models.inspect}")

        slim :agents
      end

      # Create Agent Definition
      post '/agents' do
        halt 503, "Redis connection unavailable. Cannot create agent." unless @redis
        agent_name = params['name']&.strip
        agent_description = params['description']&.strip
        selected_tools = params['tools'] || []
        selected_model = params['model']&.strip
        model_to_save = selected_model && !selected_model.empty? ? selected_model : ADK::Agent::DEFAULT_MODEL

        # Validations
        if agent_name.nil? || agent_name.empty? || agent_description.nil? || agent_description.empty?
          status 400; halt "<div class='notification is-danger'>Name and description required.</div>"
        end
        key = agent_redis_key(agent_name)
        if @redis.sismember(REDIS_AGENTS_SET_KEY, agent_name)
          status 409; halt "<div class='notification is-warning'>Agent '#{agent_name}' already exists.</div>"
        end

        # Save to Redis
        begin
          tools_json = selected_tools.to_json
          @redis.multi do |multi|
            multi.hset(key, 'description', agent_description)
            multi.hset(key, 'tools', tools_json)
            multi.hset(key, 'model', model_to_save) # Save model
            multi.sadd(REDIS_AGENTS_SET_KEY, agent_name)
          end
          logger.info("Agent '#{agent_name}' definition saved (Model: #{model_to_save}, Tools: #{selected_tools})")
        rescue Redis::BaseError => e
          logger.error("Redis error creating agent '#{agent_name}': #{e.message}")
          halt 500, "DB Error"
        rescue JSON::GeneratorError => e
          logger.error("JSON generation error for tools: #{e.message}")
          halt 500, "Internal Error"
        end

        # Respond with new table row HTML
        content_type :html
        agent_data = {
          name: agent_name, description: agent_description, running: false,
          configured_tools: selected_tools, model: model_to_save # Include model
        }
        agent_row_html = slim(:_agent_row, layout: false, locals: { agent_info: agent_data })
        oob_remove_message_html = "<tr id='no-agents-row' hx-swap-oob='true'></tr>"
        agent_row_html + oob_remove_message_html
      end

      # Delete Agent Definition
      delete '/agents/:name' do |name|
        logger.info("Received request to delete agent '#{name}'")
        halt 503, "Redis connection unavailable. Cannot delete agent." unless @redis
        agent_key = agent_redis_key(name)

        halt 404 unless @redis.exists?(agent_key) # Check if definition exists

        # Stop running instance if any
        if @agents.key?(name)
          logger.info("Stopping running agent '#{name}' before deletion...")
          begin @agents[name].stop;
                @agents.delete(name);
                logger.info("Agent '#{name}' stopped.");
          rescue => e; logger.error("Error stopping agent: #{e.message}"); end
        end

        # Delete from Redis
        begin
          deleted_count = @redis.multi { |multi| multi.del(agent_key); multi.srem(REDIS_AGENTS_SET_KEY, name); }
          logger.info("Agent '#{name}' definition deleted from Redis. Results: #{deleted_count.inspect}")
          status 200; body '' # Success for HTMX swap
        rescue Redis::BaseError => e
          logger.error("Redis error deleting agent '#{name}': #{e.message}")
          halt 500, "Database error during deletion."
        end
      end

      # Agent Detail Page
      get '/agents/:name' do |name|
        halt 503, "Redis unavailable." unless @redis
        key = agent_redis_key(name)
        redis_agent_data = @redis.hmget(key, 'description', 'tools', 'model')
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]
        loaded_model = redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL

        unless description
          halt 404, slim(:error_404, locals: { title: "Agent Not Found", message: "..." })
        end

        is_running = @agents.key?(name)
        @view_agent_data = { name: name, description: description, running: is_running, model: loaded_model }

        # --- Prepare Tool Info for Display ---
        configured_tool_names_str = []
        begin tools_json_string && configured_tool_names_str = JSON.parse(tools_json_string) rescue []; end
        # Fetch full info for configured tools from registry for the display partial
        @configured_tool_info = configured_tool_names_str.map do |tool_name|
          ADK::ToolRegistry.list_tools.find { |t| t[:name].to_s == tool_name }
        end.compact # Use compact to remove nil if a configured tool is no longer registered
        logger.debug("Agent '#{name}' configured tool info: #{@configured_tool_info.inspect}")
        # --- End Tool Info Prep ---

        # --- Agent Object Instantiation (Remains the same) ---
        configured_tool_names_sym = configured_tool_names_str.map(&:to_sym) # Use symbols for agent instance
        if is_running
          @agent = @agents[name]
          @view_agent_data[:model] = @agent.model_name
        else
          @agent = ADK::Agent.new(name: name, description: description, model_name: loaded_model)
          configured_tool_names_sym.each do |tool_name|
            tool_instance = ADK::ToolRegistry.create_instance(tool_name)
            if tool_instance then @agent.add_tool(tool_instance);
            else logger.warn("Tool '#{tool_name}' not found."); end
          end
        end
        # --- End Agent Object Instantiation ---

        # Pass @configured_tool_info to the main agent view
        slim :agent # agent.slim includes _display_agent_tools using this variable
      end # end agent details page

      # --- Agent Inline Editing Routes ---

      # GET /agents/:name/edit/:field - Serves the edit partial for a field
      get '/agents/:name/edit/:field' do |name, field|
        # --- Add 'tools' to supported fields ---
        supported_fields = ['description', 'model', 'tools']
        halt 404, "Editing field '#{field}' not supported." unless supported_fields.include?(field)
        halt 503, "Redis unavailable." unless @redis

        key = agent_redis_key(name)
        halt 404, "Agent definition '#{name}' not found." unless @redis.exists?(key)

        # Fetch necessary data
        redis_data = @redis.hmget(key, 'description', 'model', 'tools')
        agent_data = { name: name, description: redis_data[0], model: redis_data[1] }
        tools_json_string = redis_data[2]
        configured_tool_names = []
        begin tools_json_string && configured_tool_names = JSON.parse(tools_json_string) rescue []; end

        locals = { agent_data: agent_data }
        if field == 'model'
          locals[:available_models] = AVAILABLE_MODELS
        elsif field == 'tools'
          # For editing tools, need configured names and all available tools
          locals[:configured_tool_names] = configured_tool_names
          locals[:all_available_tools] = ADK::ToolRegistry.list_tools
        end

        slim :"_edit_agent_#{field}", layout: false, locals: locals
      end

      # GET /agents/:name/display/:field - Serves the display partial (for Cancel button)
      get '/agents/:name/display/:field' do |name, field|
        supported_fields = ['description', 'model', 'tools']
        halt 404, "Displaying field '#{field}' not supported." unless supported_fields.include?(field)
        halt 503, "Redis unavailable." unless @redis

        key = agent_redis_key(name)
        halt 404, "Agent definition '#{name}' not found." unless @redis.exists?(key)

        # Fetch necessary data
        redis_data = @redis.hmget(key, 'description', 'model', 'tools')

        # --- Set Instance Variables Consistently ---
        @view_agent_data = { name: name, description: redis_data[0], model: redis_data[1] } # Always set base data

        if field == 'tools'
          tools_json_string = redis_data[2]
          configured_tool_names_str = []
          begin tools_json_string && configured_tool_names_str = JSON.parse(tools_json_string) rescue []; end
          @configured_tool_info = configured_tool_names_str.map do |tool_name| # Set tools instance var
            ADK::ToolRegistry.list_tools.find { |t| t[:name].to_s == tool_name }
          end.compact
        end
        # --- End Set Instance Variables ---

        # Render using instance variables
        slim :"_display_agent_#{field}", layout: false
      end

      # PUT /agents/:name/update/:field - Handles the update from the edit form
      put '/agents/:name/update/:field' do |name, field|
        supported_fields = ['description', 'model', 'tools']
        halt 404, "Updating field '#{field}' not supported." unless supported_fields.include?(field)
        halt 503, "Redis unavailable." unless @redis

        key = agent_redis_key(name)
        halt 404, "Agent definition '#{name}' not found." unless @redis.exists?(key)

        redis_field_to_update = field
        new_value_to_save = nil

        # --- Initialize @view_agent_data early ---
        @view_agent_data = { name: name } # Ensure name is always available

        if field == 'tools'
          selected_tools = params['tools'] || []
          valid_available_tools = ADK::ToolRegistry.list_tools.map { |t| t[:name].to_s }
          validated_tools = selected_tools.select do |submitted_tool|
            if valid_available_tools.include?(submitted_tool)
              true
            else
              logger.warn("Invalid tool '#{submitted_tool}' submitted for agent '#{name}'. Ignoring.")
              false
            end
          end
          new_value_to_save = validated_tools.to_json

          # Set instance variable for configured tools
          @configured_tool_info = validated_tools.map do |tool_name| # Use the same name as GET route
            ADK::ToolRegistry.list_tools.find { |t| t[:name].to_s == tool_name }
          end.compact
          # No need to fetch desc/model here for _display_agent_tools

        else # Handling description or model
          new_value_to_save = params['value']&.strip
          if new_value_to_save.nil? || new_value_to_save.empty?
            logger.warn("Update failed for agent '#{name}', field '#{field}': Value cannot be empty.")
            redis_data = @redis.hmget(key, 'description', 'model')
            # Set instance variables for display partial before halting
            @view_agent_data[:description] = redis_data[0]
            @view_agent_data[:model] = redis_data[1]
            halt 400, slim(:"_display_agent_#{field}", layout: false)
          end
          # Set instance variables for display partial (description or model)
          @view_agent_data[:description] =
            (field == 'description' ? new_value_to_save : @redis.hget(key, 'description'))
          @view_agent_data[:model] = (field == 'model' ? new_value_to_save : @redis.hget(key, 'model'))
        end

        # Update Redis
        begin
          @redis.hset(key, redis_field_to_update, new_value_to_save)
          logger.info("Updated agent '#{name}', field '#{redis_field_to_update}'")

          # Render display partial using instance variables
          # _display_agent_tools uses @view_agent_data and @configured_tool_info
          # _display_agent_description/_model use @view_agent_data
          slim :"_display_agent_#{field}", layout: false
        rescue Redis::BaseError => e
          logger.error("Redis error updating agent '#{name}': #{e.message}")
          halt 500, "Error updating agent definition."
        rescue JSON::GeneratorError => e # Catch error converting tool list to JSON
          logger.error("JSON generation error updating tools for agent '#{name}': #{e.message}")
          halt 500, "Error saving tool configuration."
        end
      end

      # --- End Agent Inline Editing Routes ---

      # --- Routes requiring a RUNNING agent ---

      # Agent Chat Page
      get '/agents/:name/chat' do |name|
        @agent = @agents[name] # Look in memory
        if @agent
          # Ensure agent has at least Echo tool for basic chat if none configured
          if @agent.tools.empty? && defined?(ADK::Tools::Echo)
            echo_tool = ADK::ToolRegistry.create_instance(:echo)
            @agent.add_tool(echo_tool) if echo_tool
          end

          # Set the view agent data for the template
          @view_agent_data = {
            name: @agent.name,
            description: @agent.description,
            model: @agent.model_name,
            running: true
          }

          slim :chat
        else
          logger.warn("Attempted to chat with non-running agent '#{name}'")
          redirect "/agents/#{name}" # Redirect back to detail page
        end
      end

      # Process Chat Message
      post '/agents/:name/chat' do |name|
        content_type :html
        @agent = @agents[name] # Look in memory
        user_message = params['message']&.strip

        # Set @view_agent_data here in case we need it for any partials
        if @agent
          @view_agent_data = {
            name: @agent.name,
            description: @agent.description,
            model: @agent.model_name,
            running: true
          }
        end

        # Helper lambda remains the same (renders _chat_message)
        halt_chat_error = lambda do |status, error_msg, agent_name_fallback|
          halt status, slim(:_chat_message, layout: false, locals: {
                              user_message: user_message || "[Error]",
                              # Wrap plain error strings in standard hash format for partial
                              agent_result: error_msg.is_a?(String) ? { status: :error,
                                                                        error_message: error_msg } : error_msg,
                              agent_name: @agent ? @agent.name : agent_name_fallback
                            })
        end

        unless @agent then halt_chat_error.call(400, "[Error: Agent '#{name}' is not running.]", name); end
        if user_message.nil? || user_message.empty? then halt_chat_error.call(400, "[Error: Message cannot be empty.]",
                                                                              @agent.name);
        end

        begin
          logger.info("Agent '#{name}' (Model: #{@agent.model_name}) running task: #{user_message}")
          agent_result = @agent.run_task(user_message) # Returns Hash or Array<Hash>
          logger.info("Agent '#{name}' task result: #{agent_result.inspect}")
          # Pass result directly to partial, which now handles hash/array format
          slim :_chat_message, layout: false, locals: {
            user_message: user_message, agent_result: agent_result, agent_name: @agent.name
          }
        rescue => e # Errors during run_task itself
          logger.error("Error running task for agent #{name}: #{e.class} - #{e.message}")
          logger.error(e.backtrace.join("\n"))
          halt_chat_error.call(500, "[Error executing task: #{e.message}]", @agent.name)
        end
      end

      # Start Agent (for Table View)
      post '/agents/:name/start' do
        name = params[:name] # Get name from params
        agent_data_for_view = nil
        if @agents.key?(name)
          logger.warn("Agent '#{name}' is already running.")
          agent_data_for_view = @agents[name]
        else
          halt 503, "Redis unavailable." unless @redis
          key = agent_redis_key(name)
          redis_agent_data = @redis.hmget(key, 'description', 'tools', 'model') # Fetch model
          agent_description = redis_agent_data[0]
          tools_json_string = redis_agent_data[1]
          model_name = redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL # Apply default

          unless agent_description then logger.error("Agent '#{name}' definition not found."); halt 404; end

          begin
            logger.info("Instantiating and starting agent '#{name}' with model '#{model_name}'...")
            agent = ADK::Agent.new(name: name, description: agent_description, model_name: model_name) # Pass model
            tool_names_to_load = []
            if tools_json_string && !tools_json_string.empty? then tool_names_to_load = JSON.parse(tools_json_string).map(&:to_sym) rescue [];
            end
            tool_names_to_load.each do |tool_name|
              tool_instance = ADK::ToolRegistry.create_instance(tool_name)
              agent.add_tool(tool_instance) if tool_instance
            end
            agent.start
            @agents[name] = agent
            agent_data_for_view = agent
            logger.info("Agent '#{name}' started successfully.")
          rescue StandardError => e
            logger.error("Failed to start agent '#{name}': #{e.message}")
            halt 500 # Simple halt on error
          end
        end
        # Return start/stop button fragments using helper
        agent_status_fragments(agent_data_for_view)
      end

      # Start Agent (for Detail View)
      post '/agents/:name/start/detail' do
        name = params[:name]
        agent_data_for_view = nil
        # --- Perform the SAME start logic as the main /start route (including fetching/passing model) ---
        if @agents.key?(name)
          agent_data_for_view = @agents[name]
        else
          halt 503, "Redis unavailable." unless @redis
          key = agent_redis_key(name)
          redis_agent_data = @redis.hmget(key, 'description', 'tools', 'model')
          agent_description = redis_agent_data[0]
          tools_json_string = redis_agent_data[1]
          model_name = redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL
          unless agent_description then halt 404; end

          begin
            agent = ADK::Agent.new(name: name, description: agent_description, model_name: model_name)
            # Load tools...
            tool_names_to_load = []
            if tools_json_string && !tools_json_string.empty? then tool_names_to_load = JSON.parse(tools_json_string).map(&:to_sym) rescue [];
            end
            tool_names_to_load.each do |tool_name|
              tool_instance = ADK::ToolRegistry.create_instance(tool_name)
              agent.add_tool(tool_instance) if tool_instance
            end
            agent.start
            @agents[name] = agent
            agent_data_for_view = agent
          rescue => e
            logger.error("Failed start from detail: #{e.message}")
            halt 500
          end
        end
        # --- Return the status controls partial ---
        # Pass the live agent object which includes model_name implicitly
        slim :_agent_status_controls, layout: false, locals: { agent_data: agent_data_for_view }
      end

      # Stop Agent (for Table View)
      post '/agents/:name/stop' do
        name = params[:name]
        agent = @agents[name]
        stopped_agent_data = nil
        if agent
          description = agent.description
          model = agent.model_name # Capture model
          tools = agent.tools.map(&:name)
          agent.stop
          @agents.delete(name)
          stopped_agent_data = { name: name, description: description, running: false, model: model, configured_tools: tools } # Include model
          logger.info("Agent '#{name}' stopped.")
        else
          logger.warn("Attempted to stop non-running agent '#{name}'.")
          key = agent_redis_key(name)
          redis_data = @redis&.hmget(key, 'description', 'tools', 'model') || ["N/A", nil, nil]
          description = redis_data[0] || "N/A"
          tools_json = redis_data[1]
          model = redis_data[2] # Fetch model from Redis
          configured_tools = []
          if tools_json then configured_tools = JSON.parse(tools_json) rescue []; end
          stopped_agent_data = { name: name, description: description, running: false, model: model, configured_tools: configured_tools } # Include model
        end
        # Return start/stop button fragments
        agent_status_fragments(stopped_agent_data)
      end

      # Stop Agent (for Detail View)
      post '/agents/:name/stop/detail' do
        name = params[:name]
        stopped_agent_data = nil
        # --- Perform the SAME stop logic (capture model etc) ---
        agent = @agents[name]
        if agent
          description = agent.description
          model = agent.model_name
          tools = agent.tools.map(&:name)
          agent.stop
          @agents.delete(name)
          stopped_agent_data = { name: name, description: description, running: false, model: model,
                                 configured_tools: tools }
        else
          key = agent_redis_key(name)
          redis_data = @redis&.hmget(key, 'description', 'tools', 'model') || ["N/A", nil, nil]
          description = redis_data[0] || "N/A"
          tools_json = redis_data[1]
          model = redis_data[2]
          configured_tools = []
          if tools_json then configured_tools = JSON.parse(tools_json) rescue []; end
          stopped_agent_data = { name: name, description: description, running: false, model: model,
                                 configured_tools: configured_tools }
        end
        # --- Return the status controls partial ---
        # Pass hash which now includes model
        slim :_agent_status_controls, layout: false, locals: { agent_data: stopped_agent_data }
      end

      # Execute Agent Task Directly (via JSON input)
      post '/agents/:name/execute' do
        name = params[:name]
        content_type :html
        agent = @agents[name]

        # Set @view_agent_data for any partials that might use it
        if agent
          @view_agent_data = {
            name: agent.name,
            description: agent.description,
            model: agent.model_name,
            running: true
          }
        end

        html_error = lambda do |message, status_code = 400|
          error_hash = { status: :error, error_message: message }
          halt status_code, format_execution_result_html(error_hash) # Use helper
        end

        html_error.call("Error: Agent '#{name}' not found or not running.", 400) unless agent

        json_string = params['task_json']
        html_error.call("Error: Missing 'task_json' data.", 400) unless json_string && !json_string.empty?

        begin
          data = JSON.parse(json_string)
          task = data['task']
          html_error.call("Error: Missing 'task' key in JSON.", 400) unless task
        rescue JSON::ParserError => e
          logger.error "Invalid JSON submitted: #{e.message}"
          html_error.call("Error: Invalid JSON format.", 400)
        end

        begin
          logger.info("Agent '#{name}' executing task via direct endpoint: #{task}")
          result_data = agent.run_task(task) # Returns Hash or Array<Hash>
          logger.info("Agent '#{name}' direct execution result data: #{result_data.inspect}")
          format_execution_result_html(result_data) # Use helper to format
        rescue => e
          logger.error "Error during direct agent execution for '#{name}': #{e.message}"
          logger.error e.backtrace.join("\n")
          html_error.call("Error: Internal server error during task execution: #{e.message}", 500)
        end
      end

      # --- Tool Routes ---

      # List Tools Page
      get '/tools' do
        @tools_list = ADK::ToolRegistry.list_tools
        logger.info("Displaying tools: #{@tools_list.map { |t| t[:name] }}")
        slim :tools
      end

      # Tool Detail Page
      get '/tools/:name' do |name|
        tool_name_sym = name.to_sym
        @tool = ADK::ToolRegistry.create_instance(tool_name_sym)
        if @tool then slim :tool
        else halt 404,
                  slim(:error_404, locals: { title: "Tool Not Found", message: "Tool '#{name}' could not be found." });
        end
      end

      # Execute Tool Directly (via form)
      post '/tools/:name/execute' do
        name = params[:name]
        content_type :html
        tool_name_sym = name.to_sym
        logger.info("--- Executing Tool '#{name}' via form ---")

        submitted_params = params.reject { |k, _| ['splat', 'captures', 'name'].include?(k) }
        logger.debug("Parameters sent to tool: #{submitted_params.inspect}")

        tool = ADK::ToolRegistry.create_instance(tool_name_sym)

        unless tool
          err_msg = "Error: Tool '#{Rack::Utils.escape_html(name)}' not found."
          halt 404, format_execution_result_html({ status: :error, error_message: err_msg }) # Format error
        end

        begin
          logger.info("Attempting tool.execute for '#{name}' with params: #{submitted_params.inspect}")
          result_hash = tool.execute(submitted_params) # Returns hash
          logger.info("Tool '#{name}' execution returned: #{result_hash.inspect}")
          format_execution_result_html(result_hash) # Use helper to format
        rescue ADK::Error, ArgumentError => e # Catch errors during execute call
          logger.warn("Error executing tool '#{name}': #{e.message}")
          format_execution_result_html({ status: :error, error_message: e.message })
        rescue StandardError => e
          logger.error("Unexpected error executing tool '#{name}': #{e.class} - #{e.message}")
          logger.error(e.backtrace.join("\n"))
          format_execution_result_html({ status: :error, error_message: "An unexpected error occurred: #{e.message}" })
        end
      end

      # --- NEW: Agent Inline Editing Routes ---

      # GET /agents/:name/edit/:field - Serves the edit partial for a field
      # get '/agents/:name/edit/:field' do |name, field|
      #   halt 404, "Editing field '#{field}' not supported." unless ['name', 'description', 'model'].include?(field)
      #   halt 503, "Redis unavailable." unless @redis

      #   key = agent_redis_key(name)
      #   # Fetch only necessary data for the form
      #   redis_data = @redis.hmget(key, 'description', 'model') # Fetch description and model
      #   halt 404, "Agent definition '#{name}' not found." unless redis_data[0] || field == 'name' # Name is part of the key

      #   agent_data = { name: name, description: redis_data[0], model: redis_data[1] }

      #   locals = { agent_data: agent_data }
      #   # Pass available models specifically for the model editor
      #   locals[:available_models] = AVAILABLE_MODELS if field == 'model'

      #   slim :"_edit_agent_#{field}", layout: false, locals: locals
      # end

      # GET /agents/:name/display/:field - Serves the display partial (for Cancel button)
      get '/agents/:name/display/:field' do |name, field|
        supported_fields = ['description', 'model', 'tools']
        halt 404, "Displaying field '#{field}' not supported." unless supported_fields.include?(field)
        halt 503, "Redis unavailable." unless @redis

        key = agent_redis_key(name)
        halt 404, "Agent definition '#{name}' not found." unless @redis.exists?(key)

        # Fetch necessary data
        redis_data = @redis.hmget(key, 'description', 'model', 'tools')

        # --- Prepare locals hash ---
        response_locals = {}
        response_locals[:agent_data] = { name: name, description: redis_data[0], model: redis_data[1] }

        if field == 'tools'
          tools_json_string = redis_data[2]
          configured_tool_names_str = []
          begin tools_json_string && configured_tool_names_str = JSON.parse(tools_json_string) rescue []; end
          # Add :configured_tools to locals hash
          response_locals[:configured_tools] = configured_tool_names_str.map do |tool_name|
            ADK::ToolRegistry.list_tools.find { |t| t[:name].to_s == tool_name }
          end.compact
        end
        # --- End Prepare locals hash ---

        # Render using locals
        slim :"_display_agent_#{field}", layout: false, locals: response_locals
      end

      # PUT /agents/:name/update/:field - Handles the update from the edit form
      put '/agents/:name/update/:field' do |name, field|
        # ... (halts and checks) ...
        key = agent_redis_key(name)
        halt 404 unless @redis.exists?(key)

        redis_field_to_update = field
        new_value_to_save = nil

        # Prepare instance variables for response partial render
        @view_agent_data = { name: name } # Need name for URLs in the partial

        if field == 'tools'
          # ... (tool validation logic) ...
          validated_tools = selected_tools.select { |t| valid_available_tools.include?(t) } # Simplified
          new_value_to_save = validated_tools.to_json

          # Set instance variable for the display partial
          @configured_tool_info = validated_tools.map do |tool_name|
            ADK::ToolRegistry.list_tools.find { |t| t[:name].to_s == tool_name }
          end.compact

        else # Handling description or model
          new_value_to_save = params['value']&.strip
          if new_value_to_save.nil? || new_value_to_save.empty?
            # Set instance variables for display partial before halting
            redis_data = @redis.hmget(key, 'description', 'model')
            @view_agent_data[:description] = redis_data[0]
            @view_agent_data[:model] = redis_data[1]
            halt 400, slim(:"_display_agent_#{field}", layout: false)
          end
          # Set instance variables for display partial
          @view_agent_data[:description] =
            (field == 'description' ? new_value_to_save : @redis.hget(key, 'description'))
          @view_agent_data[:model] = (field == 'model' ? new_value_to_save : @redis.hget(key, 'model'))
        end

        # Update Redis
        begin
          @redis.hset(key, redis_field_to_update, new_value_to_save)
          logger.info("Updated agent '#{name}', field '#{redis_field_to_update}'")

          # Render display partial using instance variables
          slim :"_display_agent_#{field}", layout: false
        rescue Redis::BaseError => e
          logger.error("Redis error updating agent '#{name}': #{e.message}")
          halt 500, "Error updating agent definition."
        rescue JSON::GeneratorError => e # Catch error converting tool list to JSON
          logger.error("JSON generation error updating tools for agent '#{name}': #{e.message}")
          halt 500, "Error saving tool configuration."
        end
      end

      # --- End Agent Inline Editing Routes ---

      # --- API Endpoints ---

      # Get Agent List (API)
      get '/api/agents' do
        content_type :json
        agents_data = []
        if @redis
          agent_names = @redis.smembers(REDIS_AGENTS_SET_KEY)
          redis_agent_data = @redis.pipelined do |pipe|
            agent_names.each { |n| pipe.hmget(agent_redis_key(n), 'description', 'model') } # Fetch model
          end
          agents_data = agent_names.zip(redis_agent_data).map do |name, data|
            description = data[0] || "N/A"
            model = data[1] # Get model from Redis
            is_running = @agents.key?(name)
            # If running, override with live agent's model name
            model = @agents[name].model_name if is_running && @agents[name]
            { name: name, description: description, running: is_running, model: model || ADK::Agent::DEFAULT_MODEL } # Add model, ensure default
          end
        end
        json agents: agents_data.sort_by { |a| a[:name] }
      end

      # Get Tool List (API)
      get '/api/tools' do
        content_type :json
        tools_data = ADK::ToolRegistry.list_tools
        json tools: tools_data
      end
    end # End App class
  end # End Web module
end # End ADK module
