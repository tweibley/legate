# File: lib/adk/cli/deployment_commands.rb
# frozen_string_literal: true

require 'thor'
require 'fileutils'
require 'json'
require 'yaml'
require 'logger' # Needed for sample entrypoint
require 'securerandom' # Needed for suggested project ID
require 'shellwords'
require 'open3'

module ADK
  module CLI
    # CLI commands for generating deployment assets
    class DeploymentCommands < Thor
      # Default Ruby image if not specified
      DEFAULT_RUBY_IMAGE = 'ruby:3.2-slim'
      # Default output directory name
      DEFAULT_DEPLOYMENT_DIR_NAME = 'deployment'
      # Default sample entrypoint path
      DEFAULT_SAMPLE_ENTRYPOINT_PATH = 'bin/adk_web_entrypoint.rb'

      # --- Generic Options ---
      desc 'generate', 'Generate deployment assets (Dockerfile, .dockerignore, cloud-specific configs)'
      method_option :cloud, type: :string, aliases: '-c', default: 'none', required: true,
                            enum: %w[gcp aws azure none], desc: 'Target cloud provider (gcp, aws, azure, none)'
      method_option :entry_point, type: :string, aliases: '-e', required: false,
                                  desc: 'Entry point script for the main application/web process (e.g., bin/web). Required unless --generate-sample-entrypoint is used.'
      method_option :agent_entry_points, type: :array, aliases: '-a',
                                         desc: 'Entry points for user agents (comma separated)'
      method_option :name, type: :string, aliases: '-n', default: DEFAULT_DEPLOYMENT_DIR_NAME,
                           desc: 'Base name for the output directory and potentially generated resources'
      method_option :base_image, type: :string, default: DEFAULT_RUBY_IMAGE, desc: 'Base Ruby Docker image to use'
      method_option :generate_sample_entrypoint, type: :boolean, default: false,
                                                 desc: "Generate a sample web entrypoint script (#{DEFAULT_SAMPLE_ENTRYPOINT_PATH}) with a /healthz check."

      # --- GCP Specific Options (Only relevant if --cloud gcp) ---
      class_option :gcp_project_id, type: :string, group: 'GCP', desc: 'GCP Project ID (required for GCP deployment)'
      class_option :gcp_region, type: :string, default: 'us-central1', group: 'GCP', desc: 'GCP Region'
      class_option :gcp_redis_instance_name, type: :string, default: 'adk-redis', group: 'GCP',
                                             desc: 'GCP Memorystore Redis instance name'
      class_option :gcp_service_name, type: :string, default: 'adk-agent-service', group: 'GCP',
                                      desc: 'GCP Cloud Run service name for the main process'
      class_option :gcp_memory, type: :string, default: '512Mi', group: 'GCP',
                                desc: 'GCP Cloud Run memory allocation (e.g., 512Mi, 1Gi)'
      class_option :gcp_cpu, type: :string, default: '1', group: 'GCP', desc: 'GCP Cloud Run CPU allocation'
      # We might add options for agent service names, memory, cpu later.

      def generate(_directory = '.')
        # Determine the effective entry point
        effective_entry_point = if options[:generate_sample_entrypoint]
                                  options[:entry_point] || DEFAULT_SAMPLE_ENTRYPOINT_PATH
                                else
                                  options[:entry_point]
                                end

        # Validate entry_point is provided if sample isn't generated
        unless effective_entry_point
          say 'Error: --entry-point is required unless --generate-sample-entrypoint is used.', :red
          exit 1
        end

        deployment_dir = File.expand_path(options[:name])
        deployment_dir_basename = File.basename(deployment_dir)
        gcp_config_name = nil # Store generated config name for final message
        FileUtils.mkdir_p(deployment_dir)

        say "Generating deployment assets in #{deployment_dir}...", :green

        # 0. Generate sample entrypoint if requested (BEFORE generating Dockerfiles)
        generate_sample_entrypoint_script(effective_entry_point) if options[:generate_sample_entrypoint]

        # 1. Generate Generic Assets (Dockerfile(s), .dockerignore, config.ru)
        generate_dockerfiles(deployment_dir, effective_entry_point, deployment_dir_basename)
        generate_dockerignore(deployment_dir)
        generate_config_ru(deployment_dir, effective_entry_point)

        # 2. Generate Cloud-Specific Assets
        case options[:cloud]
        when 'gcp'
          gcp_config_name = generate_gcp_assets(deployment_dir)
        when 'aws'
          generate_aws_assets(deployment_dir)
        when 'azure'
          generate_azure_assets(deployment_dir)
        when 'none'
          say 'Generated generic Docker assets only.', :yellow
        else
          # Should not happen due to Thor's enum check, but good practice
          say "Unsupported cloud provider: #{options[:cloud]}", :red
          exit 1
        end

        say 'Deployment asset generation complete!', :green
        say "NOTE: Sample entrypoint generated at '#{effective_entry_point}'.", :yellow if options[:generate_sample_entrypoint]
        if gcp_config_name
          say "NOTE: A gcloud configuration named '#{gcp_config_name}' was created/updated.", :yellow
          say '      Activate it using:', :yellow
          say "        gcloud config configurations activate #{gcp_config_name}", :cyan
          say '      Before running the deployment script.', :yellow
        end
        return unless options[:cloud] == 'gcp'

        say "Review the generated files in #{deployment_dir} and the deployment guide:"
        say "  #{File.join(deployment_dir, 'README-GCP-DEPLOYMENT.md')}", :cyan
      end

      private

      def generate_dockerfiles(directory, main_entry_point, deployment_dir_basename)
        # Main Dockerfile
        main_dockerfile_path = File.join(directory, 'Dockerfile')
        generate_dockerfile_content(main_dockerfile_path, main_entry_point, options[:base_image],
                                    deployment_dir_basename)
        say "Created main Dockerfile at #{main_dockerfile_path}", :cyan

        # Agent Dockerfiles (if specified)
        options[:agent_entry_points]&.each_with_index do |agent_entry, index|
          agent_name = File.basename(agent_entry, '.rb').gsub(/[^0-9a-z_.-]/i, '_')
          agent_dockerfile_path = File.join(directory, "Dockerfile.agent.#{agent_name}.#{index}")
          generate_dockerfile_content(agent_dockerfile_path, agent_entry, options[:base_image], '')
          say "Created agent Dockerfile for '#{agent_entry}' at #{agent_dockerfile_path}", :cyan
        end
      end

      def generate_dockerfile_content(path, entry_point, base_image, deployment_dir_basename)
        # Basic validation for entry point format (crude check)
        say "Warning: Entry point '#{entry_point}' does not look like a path. Ensure it's correct.", :yellow unless entry_point&.include?('/') || entry_point&.start_with?('bin/')

        # Determine the path to config.ru relative to the build context (project root)
        # config.ru is generated inside the deployment directory
        config_ru_build_context_path = File.join(deployment_dir_basename, 'config.ru')

        # Apply changes based on user provided diff
        content = <<~DOCKERFILE
          # syntax=docker/dockerfile:1

          # Dockerfile generated by ADK CLI
          ARG RUBY_VERSION=#{base_image.split(':').last || '3.2-slim'} # Extract tag if possible
          FROM #{base_image}

          WORKDIR /app

          # Install essential dependencies
          # You may need to add more depending on your Gemfile (e.g., libpq-dev for pg gem)
          RUN apt-get update -qq && \
              apt-get install -y --no-install-recommends \
                build-essential \
                git \
                libcurl4 \
              && apt-get clean && \
              rm -rf /var/lib/apt/lists/*

          # Install Bundler
          RUN gem install bundler --no-document

          # Copy dependency definition files
          COPY Gemfile Gemfile.lock ./

          # Install ADK gem if present locally, then bundle install
          COPY adk-ruby-*.gem ./
          # Use wildcard and ignore errors if no gem file exists
          RUN gem install adk-ruby-*.gem || echo "No local adk-ruby gem found, assuming it is in Gemfile."
          RUN bundle config set without 'development test'
          RUN bundle install --jobs $(nproc) --retry 3

          # Copy the rest of the application code
          # Ensure .dockerignore is properly configured
          COPY . .
          # Copy the generated config.ru from the deployment dir in the build context
          COPY #{config_ru_build_context_path} ./

          # --- Runtime Environment Variables ---
          # Set sensible defaults, overrideable at runtime (e.g., via Cloud Run)
          ENV RACK_ENV="production"

          # Port (Required by Cloud Run)
          ENV PORT="8080"

          # Log Level
          ENV ADK_LOG_LEVEL="INFO"

          # Required for ADK session state, override with actual Redis URL
          ENV REDIS_URL="redis://localhost:6379"
          ENV ADK_SESSION_SERVICE="redis"

          # Required by ADK for Gemini access, override with secret injection
          ENV GOOGLE_API_KEY=""

          # Expose the port the application listens on
          EXPOSE ${PORT}

          # --- Entry Point ---
          # Runs the specified application or agent script using rackup
          # Assumes a config.ru file exists in the root directory
          # The config.ru should load the entrypoint script (e.g., bin/adk_web_entrypoint.rb)
          # and run the defined Rack application (e.g., AdkWebApp).
          CMD ["bundle", "exec", "rackup", "-p", "${PORT}", "-o", "0.0.0.0"]
        DOCKERFILE

        File.write(path, content)
      end

      def generate_dockerignore(directory)
        dockerignore_path = File.join(directory, '.dockerignore')
        # Avoid overwriting if it exists, maybe merge or warn later?
        if File.exist?(dockerignore_path)
          say "Skipping .dockerignore generation, file already exists: #{dockerignore_path}", :yellow
          return
        end

        content = <<~IGNORE
          # Dockerignore generated by ADK CLI
          # Add files/directories here that are not needed in the final image

          # Git files
          .git
          .gitignore

          # Docker artifacts
          .dockerignore
          Dockerfile*

          # ADK / Ruby specific
          *.gem
          .bundle/
          vendor/bundle/
          coverage/
          spec/
          tmp/
          logs/
          *.log

          # Local config / secrets
          .env*

          # IDE / Editor specific
          .vscode/
          .idea/
          .ruby-mine/
          .project
          *~ # Backup files

          # OS specific
          .DS_Store
          Thumbs.db

          # Deployment directory itself (if it's inside the project)
          #{File.basename(directory)}/

        IGNORE

        File.write(dockerignore_path, content)
        say "Created .dockerignore at #{dockerignore_path}", :cyan
      end

      # --- Generate config.ru (Generic) ---
      def generate_config_ru(directory, entry_point_script)
        config_ru_path = File.join(directory, 'config.ru')

        if File.exist?(config_ru_path)
          say "Skipping config.ru generation, file already exists: #{config_ru_path}", :yellow
          return
        end

        # Determine the relative path from config.ru (in deployment dir) to the entry_point
        # This assumes entry_point_script is relative to the project root.
        # We need the path *inside* the container (relative to /app)
        relative_entry_point = entry_point_script # Use the path as provided (e.g., 'bin/adk_web_entrypoint.rb')

        # Basic validation
        unless relative_entry_point&.include?('/')
          say "Warning: Entry point '#{relative_entry_point}' for config.ru doesn't look like a relative path. Ensure it's correct.",
              :yellow
        end

        content = <<~RACKUP
          # File: config.ru (Generated by ADK CLI)
          # This file is used by 'rackup' to start the web application.

          # Load the environment and application defined in the entrypoint script.
          # Ensure the path is correct relative to the application root inside the container.
          require_relative '#{relative_entry_point}'

          # Tell rackup which Rack application class to run.
          # This should match the class name defined in your entrypoint script (e.g., AdkWebApp).
          run AdkWebApp

        RACKUP

        File.write(config_ru_path, content)
        say "Created config.ru at #{config_ru_path}", :cyan
        say "Ensure the entrypoint path in config.ru ('#{relative_entry_point}') is correct for your project structure.",
            :yellow
      end

      # --- Sample Entrypoint Generation (Optional, generic) ---
      def generate_sample_entrypoint_script(sample_path)
        sample_path = File.expand_path(sample_path) # Ensure absolute path
        sample_dir = File.dirname(sample_path)

        unless Dir.exist?(sample_dir)
          say "Creating directory: #{sample_dir}", :green
          FileUtils.mkdir_p(sample_dir)
        end

        if File.exist?(sample_path)
          say "Sample entrypoint already exists, skipping: #{sample_path}", :yellow
          return
        end

        say "Generating sample entrypoint script at #{sample_path}", :cyan

        content = <<-'RUBYCONTENT'
          #!/usr/bin/env ruby
          # frozen_string_literal: true

          # --- Generated Sample ADK Web Entrypoint ---
          # This script provides a basic starting point for running ADK with a web server
          # and includes a /healthz endpoint suitable for Cloud Run health checks.

          require 'sinatra/base'
          require 'sinatra/json'
          require 'adk'
          require 'adk/agent'
          require 'adk/session_service/base'
          require 'adk/tools/echo'

          # --- Configuration ---
          # ADK components will often rely on environment variables for configuration
          # (e.g., REDIS_URL, ADK_SESSION_SERVICE, GOOGLE_API_KEY, PORT).
          # Ensure these are set correctly in your deployment environment (e.g., Cloud Run).

          # Configure ADK settings if needed
          # Example: Set the default model
          # config.default_model_name = 'gemini-1.5-pro'

          # Example: Configure webhooks if you plan to use them
          # config.webhooks.listener_enabled = true
          # config.webhooks.listen_address = '0.0.0.0' # Important for Cloud Run
          # config.webhooks.listen_port = ENV.fetch('PORT', 8080).to_i
          # config.webhooks.base_path = '/webhooks'
          # config.webhooks.global_secret = ENV['WEBHOOK_SECRET'] # Load from env

          # Set session service based on environment variable
          # Defaults to :memory if not set
          session_service_type = ENV.fetch('ADK_SESSION_SERVICE', 'memory').to_sym
          ADK.configure do |config|
            # Configure ADK settings if needed
            # Example: Set the default model
            # config.default_model_name = 'gemini-1.5-pro'

            # Example: Configure webhooks if you plan to use them
            # config.webhooks.listener_enabled = true
            # config.webhooks.listen_address = '0.0.0.0' # Important for Cloud Run
            # config.webhooks.listen_port = ENV.fetch('PORT', 8080).to_i
            # config.webhooks.base_path = '/webhooks'
            # config.webhooks.global_secret = ENV['WEBHOOK_SECRET'] # Load from env

            # Set session service based on environment variable
            # Defaults to :memory if not set
            config.session_service = case session_service_type
                                     when :redis
                                       # Assumes REDIS_URL environment variable is set (e.g., redis://<redis_host>:<redis_port>)
                                       # You might need to adjust Redis client options depending on your setup
                                       ADK::SessionService::Redis.new
                                     when :memory
                                       ADK::SessionService::InMemory.new
                                     else
                                       raise "Unsupported ADK_SESSION_SERVICE: #{session_service_type}"
                                     end

            # Configure definition store (if using Redis)
            if session_service_type == :redis
              config.definition_store = ADK::DefinitionStore::RedisStore.new(redis_client: Redis.new(ADK.redis_options))
            end

            # --- IMPORTANT ---
            # The ADK framework initializes its own logger.
            # You generally don't need to set it here unless you have specific needs.
            # If you DO need to customize logging, refer to the ADK documentation.
          end

          ADK.logger.info("Sample ADK Web Entrypoint environment configured.")

          # --- ADK Agent/Application Logic Integration ---
          # You might load agent definitions or start background tasks here.
          # Example:
          # Dir[File.expand_path('../../../app/agents/**/*.rb', __FILE__)].each { |file| require file }
          # puts "INFO: Loaded agent definitions."

          # --- Define Rack Application(s) ---
          # Define your main application logic within a Rack-compatible class (like Sinatra).
          # The actual server (Puma, Unicorn, etc.) will be started via rackup/config.ru
          # based on the Dockerfile\'s CMD.

          class AdkWebApp < Sinatra::Base
            configure do
              # Use the central ADK logger
              set :logger, ADK.logger
              # You might want to disable Sinatra\'s default logging if it\'s noisy
              # disable :logging
            end

            # --- Health Check Endpoint ---
            # Cloud Run uses this to check if the container is ready to serve requests.
            get '/healthz' do
              # Check essential dependencies (e.g., database connection, ADK services)
              # Return 503 if not ready.
              begin
                # Example: Check ADK session service (adjust based on your config)
                # raise "Session service not available" unless ADK.config.session_service&.check_connection
                status 200
                headers 'Content-Type' => 'text/plain'
                body 'OK'
              rescue => e
                logger.error("Health check failed: #{e.message}")
                status 503
                headers 'Content-Type' => 'text/plain'
                body "Service Unavailable: #{e.message}"
              end
            end

            # --- Echo Agent Endpoint ---
            post '/echo' do
              content_type :json

              begin
                # 1. Get input from request body (expecting JSON: { "message": "..." })
                request.body.rewind
                request_payload = JSON.parse(request.body.read)
                user_message = request_payload['message']

                unless user_message
                  halt 400, json({ status: :error, error_message: "Missing 'message' key in JSON request body." })
                end

                # 2. Get configured session service
                session_service = ADK.config.session_service
                unless session_service
                  logger.error("/echo: ADK session service is not configured!")
                  halt 500, json({ status: :error, error_message: "Internal Server Error: Session service not configured." })
                end

                # 3. Instantiate an ephemeral Echo agent
                #    Create an ephemeral definition for the echo agent.
                echo_agent_definition = ADK::AgentDefinition.new
                echo_agent_definition.define do |def_proxy|
                  def_proxy.name :ephemeral_echo_sample # Ensure a unique name if needed, or just :ephemeral_echo
                  def_proxy.description 'Temporary Echo Agent for sample endpoint'
                  def_proxy.instruction 'You are an echo agent. You will use the echo tool to repeat the input.'
                  def_proxy.use_tool :echo # Assumes EchoTool is globally registered
                  # Model, fallback_mode, etc., will use defaults from AgentDefinition
                end

                # ADK::GlobalToolManager.register(ADK::Tools::Echo) unless ADK::GlobalToolManager.find_class(:echo)
                # Ensure EchoTool is globally available if not already (though ADK typically handles this for built-ins)

                echo_agent = ADK::Agent.new(definition: echo_agent_definition)
                # The agent will use the session_service from ADK.config for its internal @session_service,
                # but run_task below will use the specific session_service instance.

                # 4. Create a temporary session for this request
                temp_session = session_service.create_session(app_name: :echo_service, user_id: "web_#{SecureRandom.hex(4)}")
                session_id = temp_session.id

                logger.info("/echo: Running echo task in session #{session_id} for message: \"#{user_message}\"")

                # 5. Run the task
                #    The Echo tool doesn't require planning, agent.run_task handles it.
                final_event_or_error = echo_agent.run_task(
                  session_id: session_id,
                  user_input: user_message, # The agent/planner uses this
                  session_service: session_service
                  # We don't *need* to explicitly tell it to use the echo tool;
                  # the agent should figure it out or the Echo tool might be a fallback.
                  # If direct tool execution was needed: agent.execute_tool(:echo, {message: user_message}, session_id, session_service)
                )

                # 6. Process the result
                if final_event_or_error.is_a?(ADK::Event)
                  result_content = final_event_or_error.content
                  # Successfully echoed
                  json({ status: :success, echoed_message: result_content[:result] }) 
                elsif final_event_or_error.is_a?(Hash) && final_event_or_error[:status] == :error
                  # Handle errors reported by run_task
                  logger.error("/echo: Agent execution failed: #{final_event_or_error[:error_message]}")
                  status 500
                  json(final_event_or_error) # Return the error hash
                else
                  # Unexpected result
                  logger.error("/echo: Unexpected result from agent execution: #{final_event_or_error.inspect}")
                  halt 500, json({ status: :error, error_message: "Internal Server Error: Unexpected agent result." })
                end

              rescue JSON::ParserError => e
                logger.error("/echo: Invalid JSON input: #{e.message}")
                halt 400, json({ status: :error, error_message: "Invalid JSON format: #{e.message}" })
              rescue => e
                logger.error("/echo: Unhandled error: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
                halt 500, json({ status: :error, error_message: "Internal Server Error: #{e.message}" })
              ensure
                # Clean up temporary session if created
                session_service.delete_session(session_id: session_id) if session_service && session_id
              end
            end

            # --- Add Your Application Routes Here ---
            # Example:
            # get \'/\' do
            #   \'Hello from ADK Web App!\'
            # end
          end

          # --- NOTE ---
          # This script NO LONGER starts the web server directly.
          # The Docker container\'s CMD should use \'rackup\' (referencing config.ru)
          # to start a web server (like Puma) which will load this environment
          # and run the AdkWebApp.

          # Example config.ru content:
          #   require_relative \'./bin/adk_web_entrypoint\' # Load this script\'s environment
          #   run AdkWebApp # Tell rackup to run your Sinatra app

        RUBYCONTENT

        File.write(sample_path, content)
        # Make the script executable
        FileUtils.chmod(0o755, sample_path)
      end

      # --- GCP Asset Generation (Only called if --cloud gcp) ---
      def generate_gcp_assets(directory)
        say 'Generating GCP specific assets...', :magenta
        gcp_config_name = nil # Initialize

        # Validate required GCP options
        project_id = options[:gcp_project_id]

        unless project_id
          # Project ID is missing, generate a suggestion and exit
          random_hex = SecureRandom.hex(3) # Generate 6 hex characters
          # Ensure name is valid for project ID (lowercase, digits, hyphens, 6-30 chars)
          sanitized_base_name = options[:name].downcase.gsub(/[^a-z0-9-]/, '-').gsub(/^-+|-+$/, '')
          suggested_project_id = "adk-deploy-#{sanitized_base_name}-#{random_hex}".slice(0, 30).gsub(/-+$/, '') # Ensure max 30 chars, no trailing hyphen
          # Ensure it starts with a letter (though our pattern should ensure this)
          suggested_project_id = "a#{suggested_project_id}" unless suggested_project_id[/^[a-z]/]
          suggested_project_id = suggested_project_id.slice(0, 30) # Re-slice if prepended 'a' pushed length
          say 'Error: --gcp-project-id is required for GCP deployment.', :red
          say 'You must provide an existing GCP project ID where you have appropriate permissions.', :yellow
          say 'If you need to create a new project first, you could use a command like this ', :yellow
          say 'After ensuring billing is configured for your account):', :yellow
          say "  gcloud projects create #{suggested_project_id}", :cyan
          say 'Then, re-run this command adding the flag:', :yellow
          say "  --gcp-project-id #{suggested_project_id}", :cyan
          exit 1 # Stop execution, user needs to provide a valid project ID
        end

        # --- Project ID is present, proceed ---
        region = options[:gcp_region] # Use the class_option value

        # 1. Attempt to create gcloud configuration
        # gcp_config_name = create_gcloud_config(options[:name], project_id, region)

        # 2. Generate GCP specific config files (optional for now, script preferred)
        # generate_gcp_redis_config(directory)
        # generate_gcp_cloud_run_config(directory)

        # 3. Generate GCP deploy script
        generate_gcp_deploy_script(directory)

        # 4. Generate Cloud Build Config
        generate_gcp_cloudbuild_yaml(directory)

        # 5. Generate/Copy GCP docs
        generate_gcp_deployment_docs(directory)

        gcp_config_name # Return the generated name for the final message
      end

      # Helper to execute shell commands and check status
      def run_gcloud_command(args, error_message)
        # Ensure args is an array for safe execution
        args = args.is_a?(Array) ? args : Shellwords.split(args)

        command_str = "gcloud #{args.join(' ')}"
        say "Executing: #{command_str}"

        output, status = Open3.capture2e('gcloud', *args)

        unless status.success?
          say "Error: #{error_message}", :red
          say "gcloud output:\n#{output}", :red
          # Decide if we should exit or just warn
          # For config commands, maybe warn and continue?
          # For critical commands in deploy script, exit is better.
          # Let's warn for config issues but allow script generation.
          say 'Warning: Failed to automatically configure gcloud. Please ensure configuration is correct manually.',
              :yellow
          return false # Indicate failure
        end
        true # Indicate success
      end

      def create_gcloud_config(base_name, project_id, region)
        # Sanitize base_name for config name
        config_name = "adk-deploy-#{base_name.gsub(/[^0-9a-zA-Z_-]/, '-')}"
        say "Attempting to create/update gcloud configuration: #{config_name}"

        # Check if gcloud command exists first
        unless system('command', '-v', 'gcloud', out: File::NULL, err: File::NULL)
          say "Error: 'gcloud' command not found in PATH. Cannot create gcloud configuration.", :red
          say 'Please install the Google Cloud SDK.', :yellow
          return nil # Cannot proceed
        end

        # 1. Create or check configuration
        # Use describe to check existence non-destructively
        _output, status = Open3.capture2e('gcloud', 'config', 'configurations', 'describe', config_name)
        if status.success?
          say "Configuration '#{config_name}' already exists. Settings will be updated.", :yellow
        else
          # Try to create (use --no-activate)
          unless run_gcloud_command(['config', 'configurations', 'create', config_name, '--no-activate'],
                                    "Failed to create gcloud configuration '#{config_name}'.")
            return nil # Failed, can't set properties
          end

          say "Created gcloud configuration: #{config_name}"
        end

        # 2. Set properties
        run_gcloud_command(['config', 'set', 'project', project_id, "--configuration=#{config_name}"],
                           'Failed to set project in gcloud config.')
        run_gcloud_command(['config', 'set', 'compute/region', region, "--configuration=#{config_name}"],
                           'Failed to set region in gcloud config.')
        # Add other relevant defaults? e.g., run/region?
        # run_gcloud_command(['config', 'set', 'run/region', region, "--configuration=#{config_name}"], "Failed to set run/region in gcloud config.")

        config_name # Return the name used
      end

      # --- GCP Specific Helper Methods ---
      def generate_gcp_redis_config(directory)
        instance_name = options[:gcp_redis_instance_name]
        redis_config_path = File.join(directory, 'redis-memorystore.yaml')

        content = <<~YAML
          apiVersion: redis.cnrm.cloud.google.com/v1beta1
          kind: RedisInstance
          metadata:
            name: #{instance_name}
          spec:
            region: ${REGION}
            tier: BASIC
            memorySizeGb: 1
            redisVersion: REDIS_6_X
            # network field is usually set automatically or handled by deploy script
            # authorizedNetwork: default
            # You can adjust memory size, version and other parameters as needed
        YAML

        File.write(redis_config_path, content)
        say "Created GCP Redis MemoryStore YAML template at #{redis_config_path}", :cyan
      end

      def generate_gcp_cloud_run_config(_directory)
        # NOTE: Generating a static YAML is less flexible than the deploy script.
        # The script can dynamically fetch Redis IP etc. Keeping this commented out
        # as generating the script is generally preferred.
        say 'Skipping generation of static cloud-run-service.yaml, deploy script is preferred.', :yellow
      end

      def generate_gcp_deploy_script(directory)
        deploy_script_path = File.join(directory, 'deploy-gcp.sh')

        # Extract GCP options with defaults from class_options
        # Escape inputs for Bash safety
        project_id = Shellwords.escape(options[:gcp_project_id])
        region = Shellwords.escape(options[:gcp_region])
        redis_name = Shellwords.escape(options[:gcp_redis_instance_name])
        main_service_name = Shellwords.escape(options[:gcp_service_name])
        main_memory = Shellwords.escape(options[:gcp_memory])
        main_cpu = Shellwords.escape(options[:gcp_cpu])
        base_name = options[:name] # Used for image naming
        deployment_dir_basename = File.basename(directory) # Get basename

        # Image names
        main_image_name = Shellwords.escape("#{base_name}-web")
        main_image_tag = Shellwords.escape('latest')

        # Artifact Registry setup
        ar_location = region # Already escaped
        ar_repo_name = Shellwords.escape('adk-images')

        # Cloud Build config file path (relative to project root)
        cloudbuild_config_file = Shellwords.escape(File.join(deployment_dir_basename, 'cloudbuild.yaml'))
        # Dockerfile path relative to deployment dir
        main_dockerfile_path_relative = Shellwords.escape('Dockerfile')

        # --- Script Content ---
        # This script is more comprehensive than before, includes setup
        script_content = <<~BASH
          #!/bin/bash
          # Generated by ADK CLI for GCP Cloud Run deployment
          set -euo pipefail # Enable strict mode

          # --- Configuration (Edit these if needed) ---
          PROJECT_ID=#{project_id}
          REGION=#{region}
          REDIS_INSTANCE_NAME=#{redis_name}
          MAIN_SERVICE_NAME=#{main_service_name}
          MAIN_DOCKERFILE=#{main_dockerfile_path_relative} # Relative path within deployment dir
          MAIN_IMAGE_NAME=#{main_image_name}
          MAIN_IMAGE_TAG=#{main_image_tag}
          MAIN_MEMORY=#{main_memory}
          MAIN_CPU=#{main_cpu}

          # Secrets Configuration
          SECRET_NAME="google-api-key" # Name of the secret in Secret Manager
          SECRET_ENV_VAR="GOOGLE_API_KEY" # Env var name in Cloud Run

          # Artifact Registry Repository
          AR_REPO_NAME=#{ar_repo_name} # Artifact Registry repo name
          AR_LOCATION=#{ar_location} # Often same as REGION, but can differ

          # VPC Access Connector (Required for Redis)
          CONNECTOR_NAME="adk-vpc-connector" # Name for the VPC Access Connector
          # Important: Ensure this range does not overlap with other subnets!
          CONNECTOR_IP_RANGE="10.8.0.0/28"
          VPC_NETWORK_NAME="default" # Use 'default' or your specific VPC network

          # Service Account for Cloud Run (Recommended: Create a dedicated one)
          # Leave empty to use the default Compute Engine service account (less secure)
          RUN_SERVICE_ACCOUNT=""
          # Example: RUN_SERVICE_ACCOUNT="adk-runner@${PROJECT_ID}.iam.gserviceaccount.com"

          # --- Helper Functions ---
          info() {
            echo "[INFO] $1"
          }

          error() {
            echo "[ERROR] $1 >&2
            exit 1
          }

          check_command() {
            command -v "$1" >/dev/null 2>&1 || error "$1' command not found. Please install it."
          }

          # --- Prerequisites Check ---
          info "Checking prerequisites..."
          check_command gcloud
          #check_command docker # Often not needed if using Cloud Build

          # --- Set GCP Project ---
          info "Setting GCP project to ${PROJECT_ID}"
          gcloud config set project "${PROJECT_ID}"

          # --- Enable Required APIs ---
          info "Enabling necessary GCP APIs..."
          gcloud services enable \
              run.googleapis.com \
              artifactregistry.googleapis.com \
              redis.googleapis.com \
              secretmanager.googleapis.com \
              cloudbuild.googleapis.com \
              vpcaccess.googleapis.com \
              compute.googleapis.com || error "Failed to enable APIs"

          # --- Configure Docker for Artifact Registry ---
          #info "Configuring Docker authentication for ${AR_LOCATION}..."
          #gcloud auth configure-docker "${AR_LOCATION}-docker.pkg.dev" || error "Docker auth configuration failed"

          # --- Create Artifact Registry Repository (if it doesn't exist) ---
          info "Ensuring Artifact Registry repository '${AR_REPO_NAME}' exists in ${AR_LOCATION}..."
          if ! gcloud artifacts repositories describe "${AR_REPO_NAME}" --location="${AR_LOCATION}" --project="${PROJECT_ID}" &>/dev/null; then
            info "Creating Artifact Registry repository '${AR_REPO_NAME}'..."
            gcloud artifacts repositories create "${AR_REPO_NAME}" \
              --repository-format=docker \
              --location="${AR_LOCATION}" \
              --description="ADK Application Images" \
              --project="${PROJECT_ID}" || error "Failed to create Artifact Registry repository"
          else
            info "Artifact Registry repository '${AR_REPO_NAME}' already exists."
          fi
          MAIN_IMAGE_URI="${AR_LOCATION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO_NAME}/${MAIN_IMAGE_NAME}:${MAIN_IMAGE_TAG}"

          # --- Create Memorystore Redis Instance (if it doesn't exist) ---
          info "Ensuring Memorystore Redis instance '${REDIS_INSTANCE_NAME}' exists in ${REGION}..."
          if ! gcloud redis instances describe "${REDIS_INSTANCE_NAME}" --region="${REGION}" --project="${PROJECT_ID}" &>/dev/null; then
            info "Creating Memorystore Redis instance '${REDIS_INSTANCE_NAME}' (this may take a few minutes)..."
            gcloud redis instances create "${REDIS_INSTANCE_NAME}" \
              --size=1 \
              --tier=BASIC \
              --redis-version=redis_6_x \
              --region="${REGION}" \
              --project="${PROJECT_ID}" \
              --network="projects/${PROJECT_ID}/global/networks/${VPC_NETWORK_NAME}" || error "Failed to create Redis instance"
          else
            info "Memorystore Redis instance '${REDIS_INSTANCE_NAME}' already exists."
          fi
          REDIS_IP=$(gcloud redis instances describe "${REDIS_INSTANCE_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --format="value(host)")
          REDIS_URL="redis://${REDIS_IP}:6379"
          info "Redis instance IP: ${REDIS_IP}"

          # --- Create VPC Access Connector (if it doesn't exist) ---
          info "Ensuring Serverless VPC Access connector '${CONNECTOR_NAME}' exists in ${REGION}..."
          if ! gcloud compute networks vpc-access connectors describe "${CONNECTOR_NAME}" --region="${REGION}" --project="${PROJECT_ID}" &>/dev/null; then
            info "Creating Serverless VPC Access connector '${CONNECTOR_NAME}'..."
            gcloud compute networks vpc-access connectors create "${CONNECTOR_NAME}" \
              --region="${REGION}" \
              --range="${CONNECTOR_IP_RANGE}" \
              --network="${VPC_NETWORK_NAME}" \
              --project="${PROJECT_ID}" || error "Failed to create VPC Access connector"
          else
            info "Serverless VPC Access connector '${CONNECTOR_NAME}' already exists."
          fi
          VPC_CONNECTOR_FULL_NAME="projects/${PROJECT_ID}/locations/${REGION}/connectors/${CONNECTOR_NAME}"

          # --- Create Secret for API Key (if it doesn't exist) ---
          info "Ensuring Secret Manager secret '${SECRET_NAME}' exists..."
          if ! gcloud secrets describe "${SECRET_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
            info "Secret '${SECRET_NAME}' not found. Please create it manually or enter the value now."
            read -sp "Enter value for ${SECRET_NAME}: " SECRET_VALUE
            echo # Newline after password prompt
            if [[ -z "$SECRET_VALUE" ]]; then
              error "Secret value cannot be empty."
            fi
            echo -n "$SECRET_VALUE" | gcloud secrets create "${SECRET_NAME}" --data-file=- \
              --replication-policy="automatic" \
              --project="${PROJECT_ID}" || error "Failed to create secret '${SECRET_NAME}'"
            # Grant default compute service account access (adjust if using dedicated SA)
            info "Granting default compute SA access to secret..."
            PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')
            DEFAULT_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
            gcloud secrets add-iam-policy-binding ${SECRET_NAME} \
               --member="serviceAccount:${DEFAULT_SA}" \
               --role="roles/secretmanager.secretAccessor" \
               --project="${PROJECT_ID}" || echo "Warning: Failed to grant default SA access to secret. Ensure the running service account has access."
          else
            info "Secret '${SECRET_NAME}' already exists."
          fi
          # Use name:version format for Cloud Run secret injection
          SECRET_RESOURCE_FOR_RUN="${SECRET_NAME}:latest"

          # --- Grant Service Account Access to Secret ---
          info "Ensuring Cloud Run service account can access secret '${SECRET_NAME}'..."
          TARGET_SERVICE_ACCOUNT="${RUN_SERVICE_ACCOUNT}"
          if [[ -z "${TARGET_SERVICE_ACCOUNT}" ]]; then
            info "Using default Compute Engine service account."
            PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)') || error "Failed to get project number."
            TARGET_SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
          else
            info "Using specified service account: ${TARGET_SERVICE_ACCOUNT}"
          fi

          # Attempt to grant the role. Might fail if runner lacks permissions.
          gcloud secrets add-iam-policy-binding "${SECRET_NAME}" \
            --member="serviceAccount:${TARGET_SERVICE_ACCOUNT}" \
            --role="roles/secretmanager.secretAccessor" \
            --project="${PROJECT_ID}" \
            --condition=None \
            >/dev/null || echo "[WARNING] Failed to automatically grant Secret Accessor role to ${TARGET_SERVICE_ACCOUNT}. Please ensure it has permission manually."

          # --- Build and Push Main Docker Image ---
          info "Building main application image: ${MAIN_IMAGE_URI}..."
          # Using Cloud Build with an explicit config file
          CONFIG_FILE=#{cloudbuild_config_file}
          gcloud builds submit --config "${CONFIG_FILE}" --project="${PROJECT_ID}" --substitutions=_IMAGE_URI="${MAIN_IMAGE_URI}" .
          if [[ $? -ne 0 ]]; then
            error "Failed to build main image using ${CONFIG_FILE}"
          fi
          # Alternatively, build locally (Requires Docker):
          # info "Configuring Docker authentication for ${AR_LOCATION}..."
          # gcloud auth configure-docker "${AR_LOCATION}-docker.pkg.dev" || error "Docker auth configuration failed"
          # docker build -t "${MAIN_IMAGE_URI}" -f "#{File.join(deployment_dir_basename, main_dockerfile_path_relative)}" . || error "Failed to build main image locally"
          # docker push "${MAIN_IMAGE_URI}" || error "Failed to push main image"

          # --- Build and Push Agent Docker Images (if configured) ---
          # <<< Add logic here to loop through agent entry points, build and push their images >>>
          # Example for one agent:
          # AGENT_SERVICE_NAME="adk-agent-processor"
          # AGENT_DOCKERFILE="Dockerfile.agent.processor"
          # AGENT_IMAGE_NAME="adk-agent-processor"
          # AGENT_IMAGE_URI="${AR_LOCATION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO_NAME}/${AGENT_IMAGE_NAME}:${MAIN_IMAGE_TAG}"
          # AGENT_CLOUDBUILD_CONFIG="path/to/agent/cloudbuild.yaml" # Example path
          # info "Building agent image: ${AGENT_IMAGE_URI}..."
          # gcloud builds submit --config "${AGENT_CLOUDBUILD_CONFIG}" --project="${PROJECT_ID}" --substitutions=_IMAGE_URI="${AGENT_IMAGE_URI}" . || error "Failed to build agent image"

          # --- Deploy Main Service to Cloud Run ---
          info "Deploying main service '${MAIN_SERVICE_NAME}' to Cloud Run in ${REGION}..."

          # Base command arguments
          CMD_ARGS=(
            gcloud run deploy "${MAIN_SERVICE_NAME}"
            --project="${PROJECT_ID}"
            --region="${REGION}"
            --image="${MAIN_IMAGE_URI}"
            --platform="managed"
            --memory="${MAIN_MEMORY}"
            --cpu="${MAIN_CPU}"
            --port="8080"
            --set-env-vars="REDIS_URL=${REDIS_URL},ADK_SESSION_SERVICE=redis,RACK_ENV=production"
            # Use name:version format for secrets
            --set-secrets="${SECRET_ENV_VAR}=${SECRET_RESOURCE_FOR_RUN}"
            --vpc-connector="${VPC_CONNECTOR_FULL_NAME}"
            --vpc-egress="all-traffic"
            --allow-unauthenticated # Remove if service should not be public
          )

          # Conditionally add service account
          if [[ -n "${RUN_SERVICE_ACCOUNT}" ]]; then
            info "Using service account: ${RUN_SERVICE_ACCOUNT}"
            # Ensure this SA has roles/secretmanager.secretAccessor for the secret!
            CMD_ARGS+=(--service-account="${RUN_SERVICE_ACCOUNT}")
          else
             info "Using default Compute Engine service account. Ensure it has Secret Accessor role."
          fi

          # Debug: Print the command arguments
          echo "DEBUG: Executing: ${CMD_ARGS[@]}"

          # Execute the command
          "${CMD_ARGS[@]}"
          if [[ $? -ne 0 ]]; then
              error "Failed to deploy main service '${MAIN_SERVICE_NAME}'"
          fi

          # --- Deploy Agent Services to Cloud Run (if configured) ---
          # <<< Add logic here to loop through agents and deploy them >>>
          # Example for one agent:
          # info "Deploying agent service '${AGENT_SERVICE_NAME}'..."
          # AGENT_DEPLOY_ARGS=( ...) # Construct agent deployment args similarly
          # gcloud run deploy "${AGENT_DEPLOY_ARGS[@]}" || error "Failed to deploy agent service '${AGENT_SERVICE_NAME}'"

          # --- Deployment Complete ---
          info "Deployment successful!"
          MAIN_SERVICE_URL=$(gcloud run services describe "${MAIN_SERVICE_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --platform="managed" --format="value(status.url)")
          if [[ -n "${MAIN_SERVICE_URL}" ]]; then
            info "Main service '${MAIN_SERVICE_NAME}' URL: ${MAIN_SERVICE_URL}"
          else
            info "Main service '${MAIN_SERVICE_NAME}' deployed, but URL not available yet."
          fi

        BASH

        File.write(deploy_script_path, script_content)
        FileUtils.chmod(0o755, deploy_script_path)
        say "Created GCP deployment script at #{deploy_script_path}", :cyan
        say 'Please review and customize the script, especially the Configuration section, before running.', :yellow
      end

      def generate_gcp_deployment_docs(directory)
        # Instead of hardcoding, copy the canonical doc we maintain
        # Use __dir__ to get the directory of the current file (deployment_commands.rb)
        source_doc_path = File.expand_path('../../../../docs/go-to-gcp-production-gemini.md', __dir__)
        target_doc_path = File.join(directory, 'README-GCP-DEPLOYMENT.md')

        if File.exist?(source_doc_path)
          FileUtils.cp(source_doc_path, target_doc_path)
          say "Copied GCP deployment guide to #{target_doc_path}", :cyan
        else
          say "Warning: Source deployment document not found at #{source_doc_path}", :yellow
          # Optionally generate a placeholder
          File.write(target_doc_path, "# GCP Deployment Guide\n\nSee online documentation for deployment steps.\n")
        end
      end

      # New method to generate cloudbuild.yaml
      def generate_gcp_cloudbuild_yaml(directory)
        cloudbuild_path = File.join(directory, 'cloudbuild.yaml')
        deployment_dir_basename = File.basename(directory)
        main_dockerfile_path_relative = File.join(deployment_dir_basename, 'Dockerfile')

        content = <<~YAML
          steps:
          # Build the container image
          - name: 'gcr.io/cloud-builders/docker'
            args: ['build', '-t', '${_IMAGE_URI}', '-f', '#{main_dockerfile_path_relative}', '.']

          # Push the container image to Artifact Registry
          images: ['${_IMAGE_URI}']

          # Define substitutions that can be passed in via --substitutions flag
          substitutions:
            _IMAGE_URI: 'gcr.io/cloud-build/image' # Default value, will be overridden
        YAML

        File.write(cloudbuild_path, content)
        say "Created GCP Cloud Build config at #{cloudbuild_path}", :cyan
      end

      # --- AWS Asset Generation (Placeholder) ---
      def generate_aws_assets(_directory)
        say 'AWS deployment asset generation is not yet implemented.', :yellow
        # Placeholder for future: generate CloudFormation/CDK/Terraform, deploy scripts etc.
      end

      # --- Azure Asset Generation (Placeholder) ---
      def generate_azure_assets(_directory)
        say 'Azure deployment asset generation is not yet implemented.', :yellow
        # Placeholder for future: generate ARM templates/Bicep, deploy scripts etc.
      end
    end
  end
end
