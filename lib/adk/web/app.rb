# File: lib/adk/web/app.rb
# frozen_string_literal: true

require 'sinatra/base'

require 'sinatra/json'
require 'sinatra/reloader'
require 'slim'
require 'json'
require_relative 'sass_compiler'
require 'rack/utils' # For escape_html
require 'redis'

# --- ADD/MOVE Requires for ADK Components Used Here ---
# Load core ADK classes needed by the App routes directly
require_relative '../agent'
require_relative '../tool' # Base class might be needed implicitly
require_relative '../tool_registry'
require_relative '../tools/echo' # Require specific tools if used
require_relative '../tools/calculator' # e.g. in default lists or checks
# --- End Requires ---

# Load dotenv for development AFTER other requires if needed
if ENV['RACK_ENV'] == 'development' || Sinatra::Base.development?
  begin; require 'dotenv/load'; rescue LoadError; end
  # Removed puts message here
end

module ADK
  module Web
    # Web interface for ADK
    class App < Sinatra::Base
      configure :development do
        register Sinatra::Reloader
        # Set more verbose logging for development if desired
        # set :logging, Logger::DEBUG
      end

      # Configure logger for all environments (can be adjusted)
      configure do
        set :logger, ADK.logger unless settings.respond_to?(:logger) && settings.logger # Ensure logger exists
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

      helpers do
        def agent_status_fragments(agent_data_or_obj)
          agent_name = agent_data_or_obj.is_a?(Hash) ? agent_data_or_obj[:name] : agent_data_or_obj.name
          is_running = agent_data_or_obj.is_a?(Hash) ? agent_data_or_obj[:running] : agent_data_or_obj.running?

          # IDs
          # status_cell_id = "agent-status-cell-#{agent_name}" # No longer primary target
          status_content_id = "agent-status-content-#{agent_name}" # Inner span ID
          start_button_id = "agent-start-button-#{agent_name}"
          stop_button_id = "agent-stop-button-#{agent_name}"

          # --- Fragment 1: Status CONTENT (Primary Target for innerHTML swap) ---
          status_tag_class = is_running ? 'is-success' : 'is-light'
          status_text = is_running ? 'Running' : 'Stopped'
          status_content_html = %(
            <span class='tag #{status_tag_class}'>#{status_text}</span>
          ) # Just the inner span tag

          # Fragment 2: Start Button (OOB) - Keep OOB logic
          start_button_html = %(
            <button class='button is-success is-light is-small' type='button' id='#{start_button_id}'
                    hx-post='/agents/#{agent_name}/start' hx-target='##{status_content_id}' hx-swap='innerHTML'
                    #{is_running ? 'disabled' : ''} hx-swap-oob='outerHTML:##{start_button_id}'>Start</button>
          ) # Note: Button hx-target also updated to status_content_id

          # Fragment 3: Stop Button (OOB) - Keep OOB logic
          stop_button_html = %(
            <button class='button is-warning is-light is-small' type='button' id='#{stop_button_id}'
                    hx-post='/agents/#{agent_name}/stop' hx-target='##{status_content_id}' hx-swap='innerHTML'
                    #{is_running ? '' : 'disabled'} hx-swap-oob='outerHTML:##{stop_button_id}'>Stop</button>
          ) # Note: Button hx-target also updated to status_content_id

          # Concatenate fragments
          status_content_html + start_button_html + stop_button_html
        end
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
        # ... (parameter handling, validation, Redis check) ...
        halt 503, "Redis connection unavailable. Cannot create agent." unless @redis
        agent_name = params['name']&.strip
        agent_description = params['description']&.strip
        selected_tools = params['tools'] || []

        # ... (validation checks) ...
        if agent_name.nil? || agent_name.empty? || agent_description.nil? || agent_description.empty?
          status 400; halt "<div class='notification is-danger'>Name and description required.</div>"
        end
        key = agent_redis_key(agent_name)
        if @redis.sismember(REDIS_AGENTS_SET_KEY, agent_name)
          status 409; halt "<div class='notification is-warning'>Agent '#{agent_name}' exists.</div>"
        end

        # --- Agent Creation (in Redis) ---
        begin
          tools_json = selected_tools.to_json
          @redis.multi do |multi|
            multi.hset(key, 'description', agent_description)
            multi.hset(key, 'tools', tools_json)
            multi.sadd(REDIS_AGENTS_SET_KEY, agent_name)
          end
          logger.info("Agent '#{agent_name}' definition saved to Redis with tools: #{selected_tools}")
        rescue Redis::BaseError => e
          # ... (error handling) ...
          logger.error("Redis error creating agent '#{agent_name}': #{e.class} - #{e.message}")
          halt 500, "DB Error" # Return simple error for halt
        rescue JSON::GeneratorError => e
          # ... (error handling) ...
          logger.error("JSON generation error for tools: #{e.message}")
          halt 500, "Internal Error" # Return simple error for halt
        end
        # --- End Agent Creation ---

        # --- Response ---
        content_type :html
        # Create data hash for the new row (stopped initially)
        agent_data = {
          name: agent_name,
          description: agent_description,
          running: false,
          configured_tools: selected_tools # Use the selected tools
        }
        # Render the new agent table row HTML
        agent_row_html = slim(:_agent_row, layout: false, locals: { agent_info: agent_data }) # <-- Use _agent_row

        # OOB fragment to remove the "No agents" row (if it exists)
        # Use an empty TR with the ID and oob swap attribute
        oob_remove_message_html = "<tr id='no-agents-row' hx-swap-oob='true'></tr>"

        # Return the agent row HTML concatenated with the OOB removal instruction
        agent_row_html + oob_remove_message_html
        # --- End Response ---
      end

      delete '/agents/:name' do |name|
        logger.info("Received request to delete agent '#{name}'")
        halt 503, "Redis connection unavailable. Cannot delete agent." unless @redis

        agent_key = agent_redis_key(name)

        # 1. Check if agent definition exists in Redis
        unless @redis.exists?(agent_key)
          logger.warn("Attempted to delete non-existent agent definition '#{name}'")
          # Return 404 - htmx usually ignores 4xx/5xx for swapping by default
          # A 200 empty response might be better if we want the card removed even on error?
          # Let's stick with 404 for now, meaning card stays if delete fails early.
          halt 404
        end

        # 2. Stop the agent if it's running in memory
        if @agents.key?(name)
          logger.info("Agent '#{name}' is running, stopping before deletion...")
          begin
            agent = @agents[name]
            agent.stop # Call stop method if it does anything important
            @agents.delete(name)
            logger.info("Agent '#{name}' stopped and removed from memory.")
          rescue StandardError => e
            logger.error("Error stopping running agent '#{name}' during deletion: #{e.message}")
            # Proceed with Redis deletion anyway, but log the error
          end
        end

        # 3. Delete from Redis within a transaction
        begin
          deleted_count = @redis.multi do |multi|
            multi.del(agent_key) # Delete the agent's hash
            multi.srem(REDIS_AGENTS_SET_KEY, name) # Remove from the set
          end
          # deleted_count[0] is result of DEL, deleted_count[1] is result of SREM
          if deleted_count[0] >= 1 && deleted_count[1] >= 1
            logger.info("Agent '#{name}' definition successfully deleted from Redis.")
          else
            logger.warn("Agent '#{name}' deletion from Redis reported unexpected results: #{deleted_count.inspect}")
            # Potential inconsistency if one command failed but transaction didn't error
          end

          # 4. Success: Return empty 200 OK response
          # htmx with hx-swap="outerHTML" will remove the target element
          status 200
          body '' # Empty body
        rescue Redis::BaseError => e
          logger.error("Redis error deleting agent '#{name}': #{e.class} - #{e.message}")
          logger.error(e.backtrace.join("\n"))
          # Return an error status - card won't be removed by default htmx behaviour
          halt 500, "Database error during deletion." # User won't see this directly
        end
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
        # Removed content_type :html - helper handles fragments

        # --- Logic to find or start agent (remains mostly the same) ---
        agent_data_for_view = nil
        if @agents.key?(name)
          # ... (handle already running) ...
          logger.warn("Agent '#{name}' is already running. Start request completing.")
          agent_data_for_view = @agents[name] # Use existing live agent
        else
          # ... (handle creating/starting new instance) ...
          halt 503, "Redis unavailable." unless @redis
          key = agent_redis_key(name)
          redis_agent_data = @redis.hmget(key, 'description', 'tools') # Fetch specific fields
          agent_description = redis_agent_data[0]
          tools_json_string = redis_agent_data[1]
          unless agent_description
            logger.error("Agent '#{name}' definition not found."); halt 404 # Simple halt
          end

          begin
            logger.info("Instantiating and starting agent '#{name}'...")
            agent = ADK::Agent.new(name: name, description: agent_description)
            # Load specific tools
            tool_names_to_load = []
            if tools_json_string && !tools_json_string.empty?
              tool_names_to_load = JSON.parse(tools_json_string).map(&:to_sym) rescue []
            end
            added_tools_names = []
            tool_names_to_load.each do |tool_name|
              tool_instance = ADK::ToolRegistry.create_instance(tool_name)
              if tool_instance then agent.add_tool(tool_instance); added_tools_names << tool_name; end
            end
            logger.info("Added tools to agent '#{name}': #{added_tools_names}")

            agent.start
            @agents[name] = agent
            agent_data_for_view = agent # Newly started agent
            logger.info("Agent '#{name}' started successfully.")
          rescue StandardError => e
            logger.error("Failed to start agent '#{name}': #{e.class} - #{e.message}")
            logger.error(e.backtrace.join("\n"))
            halt 500 # Simple halt on error
          end
        end
        # --- End agent start logic ---

        # Return combined fragments using helper
        agent_status_fragments(agent_data_for_view) # agent_data_for_view will be the running agent object
      end

      # --- Detail Page Specific Start ---
      post '/agents/:name/start/detail' do |name|
        content_type :html
        agent_data_for_view = nil
        # --- Perform the SAME start logic as the main /start route ---
        if @agents.key?(name)
          # ... (handle already running) ...
          agent_data_for_view = @agents[name]
        else
          # ... (handle creating/starting new instance, load tools etc.) ...
          halt 503, "Redis unavailable." unless @redis
          key = agent_redis_key(name)
          redis_agent_data = @redis.hmget(key, 'description', 'tools')
          agent_description = redis_agent_data[0]
          tools_json_string = redis_agent_data[1]
          unless agent_description then halt 404; end

          begin
            agent = ADK::Agent.new(name: name, description: agent_description)
            # Load specific tools (copy logic from main /start)
            tool_names_to_load = []
            if tools_json_string && !tools_json_string.empty?
              tool_names_to_load = JSON.parse(tools_json_string).map(&:to_sym) rescue []
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
            halt 500 # Or render an error partial
          end
        end
        # --- End start logic ---

        # --- Return the CORRECT partial for the detail page ---
        slim :_agent_status_controls, layout: false, locals: { agent_data: agent_data_for_view }
      end

      post '/agents/:name/stop' do |name|
        # Removed content_type :html - helper handles fragments
        agent = @agents[name]
        stopped_agent_data = nil

        if agent
          logger.info("Stopping agent '#{name}'...")
          description = agent.description
          agent.stop
          @agents.delete(name)
          stopped_agent_data = { name: name, description: description, running: false, configured_tools: agent.tools.map(&:name) } # Include tools for potential future use
          logger.info("Agent '#{name}' stopped and removed from memory.")
        else
          logger.warn("Attempted to stop agent '#{name}' which is not running.")
          # Agent not running, create data hash from Redis
          description = @redis&.hget(agent_redis_key(name), 'description') || "N/A"
          tools_json = @redis&.hget(agent_redis_key(name), 'tools')
          configured_tools = []
          if tools_json then configured_tools = JSON.parse(tools_json) rescue []; end
          stopped_agent_data = { name: name, description: description, running: false,
                                 configured_tools: configured_tools }
        end

        # Return combined fragments using helper
        agent_status_fragments(stopped_agent_data) # Pass the hash representing stopped state
      end

      # --- Detail Page Specific Stop ---
      post '/agents/:name/stop/detail' do |name|
        content_type :html
        stopped_agent_data = nil
        # --- Perform the SAME stop logic as the main /stop route ---
        agent = @agents[name]
        if agent
          # ... (stop agent, remove from @agents) ...
          description = agent.description
          tools = agent.tools.map(&:name) # Get tools before deleting
          agent.stop
          @agents.delete(name)
          stopped_agent_data = { name: name, description: description, running: false, configured_tools: tools }
        else
          # ... (create stopped data hash from Redis) ...
          description = @redis&.hget(agent_redis_key(name), 'description') || "N/A"
          tools_json = @redis&.hget(agent_redis_key(name), 'tools')
          configured_tools = []
          if tools_json then configured_tools = JSON.parse(tools_json) rescue []; end
          stopped_agent_data = { name: name, description: description, running: false,
                                 configured_tools: configured_tools }
        end
        # --- End stop logic ---

        # --- Return the CORRECT partial for the detail page ---
        slim :_agent_status_controls, layout: false, locals: { agent_data: stopped_agent_data }
      end

      # --- REMOVED OOB logic from Agent Detail Page Start/Stop Handlers ---
      # POST /agents/:name/start (Original OOB logic - now handled by table logic)
      # POST /agents/:name/stop (Original OOB logic - now handled by table logic)
      # The /start and /stop routes accessible from the detail page
      # should now likely just return the updated _agent_status_controls partial
      # or redirect back to the detail page. The table versions handle the table updates.
      # Let's simplify them for now to just update the agent state and redirect.

      # Example simplification (apply similarly to the stop route if needed)
      # post '/agents/:name/start/from_detail' do |name| # Maybe use a different route?
      #    # ... (perform start logic as before) ...
      #    redirect "/agents/#{name}" # Redirect back after action
      # end

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
