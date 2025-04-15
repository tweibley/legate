# File: lib/adk/web/app.rb
# frozen_string_literal: true

require 'sinatra/base'

# # Load development environment variables early
# if ENV['RACK_ENV'] == 'development' || Sinatra::Base.development?
#   begin
#     require 'dotenv/load'
#     puts "Dotenv loaded successfully for development." # Optional confirmation
#   rescue LoadError
#     puts "Warning: dotenv gem not found. Skipping .env file loading."
#   end
# end
# # --- END DOTENV LOADING ---
require 'sinatra/json'
require 'sinatra/reloader'
require 'slim'
require 'json'
require_relative 'sass_compiler'
require 'rack/utils' # For escape_html
require 'redis'

require_relative '../tool_registry'

# Removed
# STDOUT.sync = true # - not typically needed with standard logging

# Removed explicit require 'logger' - relying on Sinatra's logger

module ADK
  module Web
    # Web interface for ADK
    class App < Sinatra::Base
      configure :development do
        register Sinatra::Reloader
        # Set more verbose logging for development if desired
        set :logging, Logger::DEBUG
      end

      # Configure logger for all environments (can be adjusted)
      configure do
        set :logger, Logger.new($stdout) unless settings.respond_to?(:logger) && settings.logger # Ensure logger exists
        # Optionally set default level, e.g., Logger::INFO
        # settings.logger.level = Logger::INFO
      end

      set :root, File.expand_path('../../..', __dir__)
      set :views, File.expand_path('../views', __FILE__)
      set :public_folder, File.expand_path('../public', __FILE__)
      set :slim, pretty: true

      # Redis Keys Constants (Good Practice)
      REDIS_AGENT_HASH_PREFIX = "adk:agent:"
      REDIS_AGENTS_SET_KEY = "adk:agents:all_names"

      # Initialize agent registry (in-memory for running) and Redis client
      def initialize
        super
        @agents = {} # In-memory store for LIVE/RUNNING agents
        begin
          @redis = Redis.new # Assumes Redis running on localhost:6379
          @redis.ping # Check connection
          settings.logger.info("Successfully connected to Redis.")
        rescue Redis::CannotConnectError => e
          settings.logger.error("FATAL: Could not connect to Redis. Persistence disabled. #{e.message}")
          @redis = nil # Disable Redis features if connection fails
        end

        # Compile Sass files on startup
        SassCompiler.compile_all
      end

      # Helper to generate Redis key for an agent hash
      def agent_redis_key(name)
        "#{REDIS_AGENT_HASH_PREFIX}#{name}"
      end

      # --- Routes ---

      get '/' do
        slim :index
      end

      # --- Agent Routes ---

      # File: lib/adk/web/app.rb

      get '/agents' do
        # Load existing agent definitions for display
        @view_agents = []
        if @redis
          # ... (code to load agent definitions into @view_agents) ...
          agent_names = @redis.smembers(REDIS_AGENTS_SET_KEY)
          # Use PIPELINE for efficiency
          agent_data_list = @redis.pipelined do |pipe|
            agent_names.each do |name|
              pipe.hmget(agent_redis_key(name), 'description', 'tools')
            end
          end

          agent_names.zip(agent_data_list).each do |name, data|
            description = data[0] || "N/A"
            tools_json = data[1]
            configured_tools = []
            if tools_json && !tools_json.empty?
              begin
                configured_tools = JSON.parse(tools_json)
              rescue JSON::ParserError
                logger.error("Invalid tools JSON for agent '#{name}'")
              end
            end
            is_running = @agents.key?(name)
            @view_agents << { name: name, description: description, running: is_running,
                              configured_tools: configured_tools }
          end
          @view_agents.sort_by! { |a| a[:name] }
        else
          logger.error("Redis unavailable during GET /agents")
        end

        # --- ENSURE THIS PART IS PRESENT ---
        # Fetch available tools for the creation form checkboxes
        @available_tools = ADK::ToolRegistry.list_tools
        logger.debug("Available tools for form: #{@available_tools.inspect}") # Add debug log
        # --- END ENSURE ---

        slim :agents # Render the view
      end

      post '/agents' do
        # Handles creation via form post
        halt 503, "Redis connection unavailable. Cannot create agent." unless @redis

        agent_name = params['name']&.strip
        agent_description = params['description']&.strip

        # Get selected tool names - params['tools'] will be an array or nil
        selected_tools = params['tools'] || [] # Default to empty array if none selected

        # --- Validation ---
        if agent_name.nil? || agent_name.empty? || agent_description.nil? || agent_description.empty?
          status 400
          halt "<div class='notification is-danger'>Name and description are required.</div>"
        end
        # TODO: Validate that selected_tools actually exist in the registry?

        key = agent_redis_key(agent_name)

        # Check if agent name already exists in Redis SET
        if @redis.sismember(REDIS_AGENTS_SET_KEY, agent_name)
          status 409 # Conflict
          halt "<div class='notification is-warning'>Agent with name '#{agent_name}' already exists.</div>"
        end
        # --- End Validation ---

        # --- Agent Creation (in Redis) ---
        begin
          tools_json = selected_tools.to_json
          # key = agent_redis_key(agent_name) # Define key before multi

          @redis.multi do |multi|
            # --- Use separate HSET commands ---
            multi.hset(key, 'description', agent_description)
            multi.hset(key, 'tools', tools_json)
            # --- End separate HSET ---
            multi.sadd(REDIS_AGENTS_SET_KEY, agent_name)
          end
          logger.info("Agent '#{agent_name}' definition saved to Redis with tools: #{selected_tools}")
        rescue Redis::BaseError => e
          # ... (error handling) ...
          logger.error("Redis error creating agent '#{agent_name}': #{e.class} - #{e.message}")
          logger.error(e.backtrace.join("\n"))
          halt 500,
               "<div class='notification is-danger'>Failed to save agent definition due to database error. Check server logs for details.</div>"
        rescue JSON::GeneratorError => e
          # ... (error handling) ...
          logger.error("Error generating JSON for tools list: #{e.message}")
          halt 500, "<div class='notification is-danger'>Internal server error preparing tool data.</div>"
        end
        # --- End Agent Creation ---

        # --- Response ---
        # We return an HTML card, but it now represents a *stopped* agent by default
        content_type :html
        # Pass data hash, not live object, as it's not running yet
        agent_data = { name: agent_name, description: agent_description, running: false }
        slim :_agent_card, layout: false, locals: { agent_info: agent_data }
        # --- End Response ---
      end

      get '/agents/:name' do |name|
        halt 503, "Redis connection unavailable." unless @redis

        # 1. Fetch agent definition (description and tools) from Redis
        key = agent_redis_key(name)
        redis_agent_data = @redis.hmget(key, 'description', 'tools')
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]

        unless description
          logger.warn("Agent '#{name}' definition not found in Redis.")
          halt 404,
               slim(:error_404,
                    locals: { title: "Agent Not Found", message: "Agent definition for '#{name}' could not be found." })
        end

        # 2. Determine running state
        is_running = @agents.key?(name)
        @view_agent_data = { name: name, description: description, running: is_running } # For status controls etc.

        # 3. Set the @agent instance variable for the view
        configured_tool_names = [] # Store the names configured in Redis
        if tools_json_string && !tools_json_string.empty?
          begin
            configured_tool_names = JSON.parse(tools_json_string).map(&:to_sym)
          rescue JSON::ParserError => e
            logger.error("Invalid tools JSON for agent '#{name}' on detail page: #{e.message}")
          end
        end
        logger.debug("Agent '#{name}' configured tools from Redis: #{configured_tool_names}")

        if is_running
          # Use the live, running agent object (already has correct tools loaded during start)
          @agent = @agents[name]
          logger.info("Agent '#{name}' is running, using live object for view. Live Tools: #{@agent.tools.map(&:name)}")
        else
          # Create a temporary Agent object for display
          logger.info("Agent '#{name}' is stopped, creating temporary object for view.")
          @agent = ADK::Agent.new(name: name, description: description)

          # --- CORRECTED TOOL POPULATION for stopped agent ---
          # Add ONLY the tools configured for this agent from Redis
          added_tools = []
          configured_tool_names.each do |tool_name|
            tool_instance = ADK::ToolRegistry.create_instance(tool_name)
            if tool_instance
              @agent.add_tool(tool_instance)
              added_tools << tool_name
            else
              logger.warn("Configured tool '#{tool_name}' for stopped agent '#{name}' not found in registry.")
            end
          end
          logger.info("Added configured tools to temporary view object for '#{name}'. Tools: #{added_tools}")
          # --- END CORRECTION ---
        end # End if is_running

        # 4. Render the view (now @agent has correct tools whether running or stopped)
        slim :agent
      end

      # --- Routes requiring a RUNNING agent ---

      get '/agents/:name/chat' do |name|
        @agent = @agents[name] # Look in memory (only running agents are here)
        if @agent
          # Agent is running, proceed to chat
          if @agent.tools.empty? && defined?(ADK::Tools::Echo)
            @agent.add_tool(ADK::Tools::Echo.new)
          end
          slim :chat
        else
          # Agent not running or doesn't exist in memory
          logger.warn("Attempted to chat with agent '#{name}' which is not running.")
          # Just redirect to the detail page without the unsupported 'error:' hash
          redirect "/agents/#{name}" # <--- REMOVED , error: "..."
        end
      end

      post '/agents/:name/chat' do |name|
        # Chat only works with RUNNING agents from memory
        content_type :html
        @agent = @agents[name] # Look in memory
        user_message = params['message']&.strip

        # Use helper method for rendering chat error messages
        halt_chat_error = lambda do |status, error_msg, agent_name_fallback|
          halt status, slim(:_chat_message, layout: false, locals: {
                              user_message: user_message || "[Error]",
                              agent_result: error_msg,
                              agent_name: @agent ? @agent.name : agent_name_fallback
                            })
        end

        # Updated error checks to use the in-memory @agent
        unless @agent
          halt_chat_error.call(400, "[Error: Agent '#{name}' is not running or not found]", name)
          # Note: We already know it's not running if @agent is nil here.
        end
        # agent.running? check might be redundant now if only running agents are in @agents
        halt_chat_error.call(400, "[Error: Message cannot be empty]",
                             @agent.name) if user_message.nil? || user_message.empty?

        begin
          logger.info("Agent '#{name}' running task: #{user_message}")
          agent_result = @agent.run_task(user_message) # Use the live agent object
          logger.info("Agent '#{name}' task result: #{agent_result.inspect}")
          slim :_chat_message, layout: false, locals: {
            user_message: user_message, agent_result: agent_result, agent_name: @agent.name
          }
        rescue => e
          logger.error("Error running task for agent #{name}: #{e.class} - #{e.message}")
          logger.error(e.backtrace.join("\n"))
          halt_chat_error.call(500, "[Error executing task: #{e.message}]", @agent.name)
        end
      end

      post '/agents/:name/start' do |name|
        content_type :html
        if @agents.key?(name)
          logger.warn("Agent '#{name}' is already running. Start request completing.")
          @agent = @agents[name]
          agent_data_for_view = @agent
        else
          halt 503, "Redis connection unavailable." unless @redis
          key = agent_redis_key(name)
          # Fetch specific fields instead of HGETALL if only description & tools needed
          redis_agent_data = @redis.hmget(key, 'description', 'tools')
          agent_description = redis_agent_data[0]
          tools_json_string = redis_agent_data[1]

          unless agent_description
            logger.error("Attempted to start agent '#{name}' but its definition was not found in Redis.")
            halt 404, "<div class='has-text-danger'>Error: Agent definition not found. Cannot start.</div>"
          end

          begin
            logger.info("Instantiating and starting agent '#{name}'...")
            agent = ADK::Agent.new(name: name, description: agent_description)

            # --- TOOL LOADING BASED ON PERSISTED CONFIG ---
            tool_names_to_load = []
            if tools_json_string && !tools_json_string.empty?
              begin
                # Parse the stored JSON string of tool names
                tool_names_to_load = JSON.parse(tools_json_string).map(&:to_sym) # Ensure symbols
                logger.info("Found configured tools for '#{name}': #{tool_names_to_load}")
              rescue JSON::ParserError => e
                logger.error("Failed to parse stored tools JSON for agent '#{name}'. Loading no tools. JSON: #{tools_json_string.inspect}. Error: #{e.message}")
                tool_names_to_load = [] # Default to no tools on parsing error
              end
            else
              logger.warn("No tools configured or field missing for agent '#{name}'. Starting with no tools.")
              tool_names_to_load = []
            end

            added_tools_names = []
            tool_names_to_load.each do |tool_name|
              tool_instance = ADK::ToolRegistry.create_instance(tool_name)
              if tool_instance
                agent.add_tool(tool_instance)
                added_tools_names << tool_name
              else
                logger.warn("Configured tool '#{tool_name}' for agent '#{name}' could not be found or instantiated in the registry.")
              end
            end
            logger.info("Actually added tools to agent '#{name}': #{added_tools_names}")
            # --- END TOOL LOADING ---

            agent.start
            @agents[name] = agent
            agent_data_for_view = agent
            logger.info("Agent '#{name}' started successfully.")
          rescue StandardError => e
            logger.error("Failed to instantiate or start agent '#{name}': #{e.class} - #{e.message}")
            logger.error(e.backtrace.join("\n"))
            halt 500,
                 "<div class='notification is-danger'>Error starting agent: #{Rack::Utils.escape_html(e.message)}</div>"
          end
        end

        # --- Rendering logic (remains the same) ---
        status_controls_html = slim(:_agent_status_controls, layout: false, locals: { agent_data: agent_data_for_view })
        is_running = agent_data_for_view.is_a?(ADK::Agent) ? agent_data_for_view.running? : agent_data_for_view[:running]
        execute_button_html = %(
          <button class='button is-primary' type='submit' id='execute-task-button' #{is_running ? '' : 'disabled'} hx-swap-oob='outerHTML:#execute-task-button'>
            Execute (Requires Start)
          </button>
        )
        status_controls_html + execute_button_html
      end

      post '/agents/:name/stop' do |name|
        content_type :html
        agent = @agents[name] # Find the LIVE agent object
        stopped_agent_data = nil # Prepare variable

        if agent
          logger.info("Stopping agent '#{name}'...")
          description = agent.description # Get description before stopping/removing
          agent.stop
          @agents.delete(name)
          stopped_agent_data = { name: name, description: description, running: false } # Create data hash
          logger.info("Agent '#{name}' stopped and removed from in-memory store.")
        else
          logger.warn("Attempted to stop agent '#{name}' which is not currently running in memory.")
          # Agent not running, create data hash representing stopped state from Redis info
          description = @redis&.hget(agent_redis_key(name), 'description') || "N/A"
          stopped_agent_data = { name: name, description: description, running: false }
        end

        # Render the status controls fragment (main target)
        status_controls_html = slim(:_agent_status_controls, layout: false,
                                                             locals: { agent_data: stopped_agent_data })

        # Render the execute button fragment (OOB target)
        # Determine running state for the button's disabled attribute (will always be false here)
        # Render the execute button fragment (OOB target)
        is_running = stopped_agent_data[:running] # Should be false
        # Use explicit OOB syntax:
        execute_button_html = %(
    <button class='button is-primary' type='submit' id='execute-task-button' #{is_running ? '' : 'disabled'} hx-swap-oob='outerHTML:#execute-task-button'>
      Execute (Requires Start)
    </button>
  )

        # Return both fragments concatenated
        status_controls_html + execute_button_html
      end

      post '/agents/:name/execute' do |name|
        content_type :html # <-- CHANGE 1: Set content type to HTML
        agent = @agents[name] # Look in memory

        # Helper lambda for HTML error fragments
        html_error = lambda do |message, status_code = 400|
          halt status_code, "<div class='notification is-danger mt-4'>#{Rack::Utils.escape_html(message)}</div>"
        end

        html_error.call("Error: Agent '#{name}' not found or not running.", 400) unless agent

        json_string = params['task_json']
        html_error.call("Error: Missing 'task_json' data in request.",
                        400) unless json_string && !json_string.empty?

        begin
          data = JSON.parse(json_string)
          task = data['task']
          html_error.call("Error: Missing 'task' key within the provided JSON.", 400) unless task
        rescue JSON::ParserError => e
          logger.error "Invalid JSON submitted in 'task_json' parameter: #{e.message}"
          logger.error "Submitted string was: #{json_string.inspect}"
          html_error.call("Error: Invalid JSON format submitted.", 400)
        end

        begin
          logger.info("Agent '#{name}' executing task via direct endpoint: #{task}")
          result = agent.run_task(task)
          result_string = result.to_s # Ensure we have a string
          logger.info("Agent '#{name}' direct execution result: #{result_string.inspect}")

          # --- CHANGE 2: Format success response as HTML ---
          # Use <pre> to preserve newlines from the cat fact/tool output
          "<div class='notification is-success mt-4'><pre>#{Rack::Utils.escape_html(result_string)}</pre></div>"
        # --- End CHANGE 2 ---
        rescue => e
          logger.error "Error during direct agent execution for '#{name}': #{e.class} - #{e.message}"
          logger.error e.backtrace.join("\n")
          # Use the HTML error helper here too
          html_error.call("Error: Internal server error during task execution.", 500)
        end
      end

      # --- Tool Routes ---

      get '/tools' do
        # Use the registry to get the list
        @tools_list = ADK::ToolRegistry.list_tools
        logger.info("Displaying tools: #{@tools_list.map { |t| t[:name] }}")
        slim :tools
      end

      get '/tools/:name' do |name|
        tool_name_sym = name.to_sym
        # Use the registry to create an instance
        @tool = ADK::ToolRegistry.create_instance(tool_name_sym)

        if @tool
          slim :tool
        else
          logger.warn("Tool '#{name}' not found when accessing detail page.")
          halt 404, slim(:error_404, locals: { title: "Tool Not Found", message: "Tool '#{name}' could not be found." })
        end
      end

      post '/tools/:name/execute' do |name|
        content_type :html
        tool_name_sym = name.to_sym
        logger.info("--- Executing Tool '#{name}' via form ---")

        submitted_params = params.reject { |k, _| ['splat', 'captures', 'name'].include?(k) }
        logger.debug("Parameters sent to tool: #{submitted_params.inspect}")

        # Use the registry to create an instance
        tool = ADK::ToolRegistry.create_instance(tool_name_sym)

        unless tool
          logger.error("Tool definition '#{name}' not found in registry.")
          halt 404,
               "<div class='notification is-danger mt-4'>Error: Tool '#{Rack::Utils.escape_html(name)}' not found.</div>"
        end

        begin
          # Execute the specific instance
          logger.info("Attempting tool.execute for '#{name}' with params: #{submitted_params.inspect}")
          result = tool.execute(submitted_params)
          logger.info("Tool '#{name}' execution successful.")
          "<div class='notification is-success mt-4'><pre>#{Rack::Utils.escape_html(result.to_s)}</pre></div>"
        rescue ADK::Error, ArgumentError => e
          logger.warn("Validation/Argument Error executing tool '#{name}': #{e.message}. Params: #{submitted_params.inspect}")
          "<div class='notification is-danger mt-4'>Error: #{Rack::Utils.escape_html(e.message)}</div>"
        rescue StandardError => e
          logger.error("Unexpected error executing tool '#{name}': #{e.class} - #{e.message}. Params: #{submitted_params.inspect}")
          logger.error(e.backtrace.join("\n"))
          "<div class='notification is-danger mt-4'>An unexpected error occurred: #{Rack::Utils.escape_html(e.message)}</div>"
        end
      end

      # --- API Endpoints ---

      get '/api/agents' do
        # Combine Redis definitions with in-memory status
        content_type :json
        agents_data = []
        if @redis
          agent_names = @redis.smembers(REDIS_AGENTS_SET_KEY)
          agents_data = agent_names.map do |name|
            description = @redis.hget(agent_redis_key(name), 'description') || "N/A"
            is_running = @agents.key?(name)
            { name: name, description: description, running: is_running }
          end
        end
        json agents: agents_data
      end

      get '/api/tools' do
        content_type :json
        # Use the registry
        tools_data = ADK::ToolRegistry.list_tools
        json tools: tools_data
      end
    end # End App class
  end # End Web module
end # End ADK module
