# File: lib/adk/web/app.rb
# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/reloader'
require 'slim'
require 'json'
require_relative 'sass_compiler'
require 'rack/utils' # For escape_html
# Removed STDOUT.sync = true - not typically needed with standard logging

# Removed explicit require 'logger' - relying on Sinatra's logger

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
        set :logger, Logger.new($stdout) unless settings.respond_to?(:logger) && settings.logger # Ensure logger exists
        # Optionally set default level, e.g., Logger::INFO
        # settings.logger.level = Logger::INFO
      end

      set :root, File.expand_path('../../..', __dir__)
      set :views, File.expand_path('../views', __FILE__)
      set :public_folder, File.expand_path('../public', __FILE__)
      set :slim, pretty: true

      # Initialize agent registry
      def initialize
        super
        @agents = {} # Simple in-memory store

        # Compile Sass files on startup
        SassCompiler.compile_all
      end

      # --- Routes ---

      get '/' do
        slim :index
      end

      # --- Agent Routes ---

      get '/agents' do
        @agents_list = @agents.values
        slim :agents
      end

      post '/agents' do
        # Handles creation via form post
        agent_name = params['name']&.strip
        agent_description = params['description']&.strip

        if agent_name.nil? || agent_name.empty? || agent_description.nil? || agent_description.empty?
          status 400
          halt "<div class='notification is-danger'>Name and description are required.</div>"
        end

        if @agents.key?(agent_name)
          status 409
          halt "<div class='notification is-warning'>Agent with name '#{agent_name}' already exists.</div>"
        end

        agent = ADK::Agent.new(
          name: agent_name,
          description: agent_description
          # Pass logger to agent if desired: logger: settings.logger
        )
        @agents[agent.name] = agent

        content_type :html
        slim :_agent_card, layout: false, locals: { agent: agent }
      end

      get '/agents/:name' do |name|
        @agent = @agents[name]
        if @agent
          slim :agent
        else
          logger.warn("Agent '#{name}' not found when accessing detail page.")
          halt 404, slim(:error_404, locals: { title: "Agent Not Found", message: "Agent '#{name}' could not be found." })
        end
      end

      get '/agents/:name/chat' do |name|
        @agent = @agents[name]
        if @agent
          # Ensure the agent has the default echo tool if needed for testing
          if @agent.tools.empty? && defined?(ADK::Tools::Echo)
            @agent.add_tool(ADK::Tools::Echo.new)
          end
          slim :chat
        else
          # Agent not found, maybe redirect?
          logger.warn("Agent '#{name}' not found when trying to chat.")
          redirect '/agents' # Or show an error
        end
      end

      post '/agents/:name/chat' do |name|
        # Handles chat message submission
        content_type :html
        @agent = @agents[name]
        user_message = params['message']&.strip

        # Use helper method for rendering chat error messages
        halt_chat_error = lambda do |status, error_msg, agent_name_fallback|
          halt status, slim(:_chat_message, layout: false, locals: {
            user_message: user_message || "[Error]",
            agent_result: error_msg,
            agent_name: @agent ? @agent.name : agent_name_fallback
          })
        end

        halt_chat_error.call(404, "[Error: Agent '#{name}' not found]", name) if @agent.nil?
        halt_chat_error.call(400, "[Error: Agent '#{@agent.name}' is not running. Please start it first.]", @agent.name) unless @agent.running?
        halt_chat_error.call(400, "[Error: Message cannot be empty]", @agent.name) if user_message.nil? || user_message.empty?

        begin
          # Execute the task using the agent
          logger.info("Agent '#{name}' running task: #{user_message}")
          agent_result = @agent.run_task(user_message)
          logger.info("Agent '#{name}' task result: #{agent_result.inspect}")

          # Render the partial with the message and result
          slim :_chat_message, layout: false, locals: {
            user_message: user_message,
            agent_result: agent_result,
            agent_name: @agent.name
          }
        rescue => e
          # Handle errors during task execution
          logger.error("Error running task for agent #{name}: #{e.class} - #{e.message}")
          logger.error(e.backtrace.join("\n"))
          halt_chat_error.call(500, "[Error executing task: #{e.message}]", @agent.name)
        end
      end

      post '/agents/:name/start' do |name|
        # Handles agent start request
        content_type :html
        @agent = @agents[name]
        if @agent
          logger.info("Starting agent '#{name}'")
          @agent.start
          slim :_agent_status_controls, layout: false, locals: { agent: @agent }
        else
          logger.warn("Attempted to start non-existent agent '#{name}'")
          halt 404, "<div class='has-text-danger'>Error: Agent not found</div>"
        end
      end

      post '/agents/:name/stop' do |name|
        # Handles agent stop request
        content_type :html
        @agent = @agents[name]
        if @agent
          logger.info("Stopping agent '#{name}'")
          @agent.stop
          slim :_agent_status_controls, layout: false, locals: { agent: @agent }
        else
          logger.warn("Attempted to stop non-existent agent '#{name}'")
          halt 404, "<div class='has-text-danger'>Error: Agent not found</div>"
        end
      end

      post '/agents/:name/execute' do |name|
        # Handles direct task execution (expects JSON input)
        content_type :json
        agent = @agents[name]

        unless agent
          logger.warn "Agent '#{name}' not found for execution."
          halt 400, json(result: "Error: Agent '#{name}' not found.")
        end
        unless agent.running?
           logger.warn "Agent '#{name}' is not running for execution."
           halt 400, json(result: "Error: Agent '#{name}' is not running.")
        end

        begin
           data = JSON.parse(request.body.read)
           task = data['task']
           unless task
              logger.error "No 'task' field in JSON body for agent execution."
              halt 400, json(result: "Error: Missing 'task' in JSON request body.")
           end
           logger.info("Agent '#{name}' executing task via direct endpoint: #{task}")
           result = agent.run_task(task)
           json result: result
        rescue JSON::ParserError
           logger.error "Invalid JSON received for agent execution."
           halt 400, json(result: "Error: Invalid JSON in request body.")
        rescue => e
           logger.error "Error during direct agent execution for '#{name}': #{e.class} - #{e.message}"
           logger.error e.backtrace.join("\n")
           halt 500, json(result: "Error: Internal server error during task execution.")
        end
      end

      # --- Tool Routes ---

      get '/tools' do
        # TODO: Implement dynamic tool discovery/registry
        logger.warn("Tool list is currently hardcoded in GET /tools route.")
        @tools_list = [
          ADK::Tools::Echo.new # Instantiate the tool to get its current info
          # Example: ADK::Tools::Calculator.new
        ].map do |tool|
          { name: tool.name, description: tool.description }
        end
        slim :tools
      end

      get '/tools/:name' do |name|
        # TODO: Implement dynamic tool discovery/registry
        tool_instance = case name.to_sym
                       when :echo
                         ADK::Tools::Echo.new
                       # Add other tools here
                       else
                         nil
                       end

        if tool_instance
          @tool = tool_instance # Pass the instance to the view
          slim :tool
        else
          logger.warn("Tool '#{name}' not found when accessing detail page.")
          halt 404, slim(:error_404, locals: { title: "Tool Not Found", message: "Tool '#{name}' could not be found." })
        end
      end

      post '/tools/:name/execute' do |name|
        # Handles execution via tool detail page form
        content_type :html
        logger.info("--- Executing Tool '#{name}' via form ---")
        # logger.debug("Raw params received: #{params.inspect}") # Debug logging (optional)

        # Parameters are expected with STRING keys from the form now
        # Removed .transform_keys(&:to_sym) as validation expects strings
        submitted_params = params.reject { |k, _| ['splat', 'captures', 'name'].include?(k) }
        logger.debug("Parameters sent to tool: #{submitted_params.inspect}")

        # TODO: Implement dynamic tool discovery/registry
        tool = case name.to_sym
               when :echo
                 ADK::Tools::Echo.new
               # Add other tools here
               else
                 nil
               end

        unless tool
          logger.error("Tool definition '#{name}' not found.")
          halt 404, "<div class='notification is-danger mt-4'>Error: Tool definition '#{Rack::Utils.escape_html(name)}' not found on server.</div>"
        end

        begin
          logger.info("Attempting tool.execute for '#{name}' with params: #{submitted_params.inspect}")
          result = tool.execute(submitted_params) # Assumes tool validation/execution expects string keys now
          logger.info("Tool '#{name}' execution successful.")
          # Render success result
          "<div class='notification is-success mt-4'><pre>#{Rack::Utils.escape_html(result.to_s)}</pre></div>"
        rescue ADK::Error, ArgumentError => e
          # Catch specific validation/argument errors
          logger.warn("Validation/Argument Error executing tool '#{name}': #{e.message}. Params: #{submitted_params.inspect}")
          # Render specific error result
          "<div class='notification is-danger mt-4'>Error: #{Rack::Utils.escape_html(e.message)}</div>"
        rescue StandardError => e
          # Catch unexpected errors within the tool's execution
          logger.error("Unexpected error executing tool '#{name}': #{e.class} - #{e.message}. Params: #{submitted_params.inspect}")
          logger.error(e.backtrace.join("\n"))
          # Render generic error result
          "<div class='notification is-danger mt-4'>An unexpected error occurred: #{Rack::Utils.escape_html(e.message)}</div>"
        end
      end

      # --- API Endpoints ---

      get '/api/agents' do
        content_type :json
        json agents: @agents.values.map { |agent| # Use .values here
          {
            name: agent.name,
            description: agent.description,
            running: agent.running?
          }
        }
      end

      get '/api/tools' do
        content_type :json
        # TODO: Implement dynamic tool discovery/registry
        logger.warn("Tool API endpoint is currently hardcoded.")
        echo_tool = ADK::Tools::Echo.new
        json tools: [
          {
            name: echo_tool.name,
            description: echo_tool.description
          }
          # Add other registered tools here
        ]
      end

    end # End App class
  end # End Web module
end # End ADK module