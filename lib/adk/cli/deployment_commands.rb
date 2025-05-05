# File: lib/adk/cli/deployment_commands.rb
# frozen_string_literal: true

require 'thor'
require 'fileutils'
require 'json'
require 'yaml'
require 'logger' # Needed for sample entrypoint
require 'securerandom' # Needed for suggested project ID

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
      method_option :cloud, type: :string, aliases: "-c", default: 'none', required: true,
                            enum: %w[gcp aws azure none], desc: 'Target cloud provider (gcp, aws, azure, none)'
      method_option :entry_point, type: :string, aliases: "-e", required: true,
                                  desc: 'Entry point script for the main application/web process (e.g., bin/web)'
      method_option :agent_entry_points, type: :array, aliases: "-a",
                                         desc: 'Entry points for user agents (comma separated)'
      method_option :name, type: :string, aliases: "-n", default: DEFAULT_DEPLOYMENT_DIR_NAME,
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

      def generate(directory = ".")
        deployment_dir = File.expand_path(options[:name])
        gcp_config_name = nil # Store generated config name for final message
        FileUtils.mkdir_p(deployment_dir)

        say "Generating deployment assets in #{deployment_dir}...", :green

        # 0. Generate sample entrypoint if requested (BEFORE generating Dockerfiles)
        if options[:generate_sample_entrypoint]
          generate_sample_entrypoint_script
        end

        # 1. Generate Generic Assets (Dockerfile(s), .dockerignore)
        generate_dockerfiles(deployment_dir)
        generate_dockerignore(deployment_dir)

        # 2. Generate Cloud-Specific Assets
        case options[:cloud]
        when 'gcp'
          gcp_config_name = generate_gcp_assets(deployment_dir)
        when 'aws'
          generate_aws_assets(deployment_dir)
        when 'azure'
          generate_azure_assets(deployment_dir)
        when 'none'
          say "Generated generic Docker assets only.", :yellow
        else
          # Should not happen due to Thor's enum check, but good practice
          say "Unsupported cloud provider: #{options[:cloud]}", :red
          exit 1
        end

        say "Deployment asset generation complete!", :green
        if options[:generate_sample_entrypoint]
          say "NOTE: Sample entrypoint generated at '#{DEFAULT_SAMPLE_ENTRYPOINT_PATH}'.", :yellow
          say "      Ensure your --entrypoint option matches this path ('#{options[:entry_point]}).", :yellow
        end
        if gcp_config_name
          say "NOTE: A gcloud configuration named '#{gcp_config_name}' was created/updated.", :yellow
          say "      Activate it using:", :yellow
          say "        gcloud config configurations activate #{gcp_config_name}", :cyan
          say "      Before running the deployment script.", :yellow
        end
        if options[:cloud] == 'gcp'
          say "Review the generated files in #{deployment_dir} and the deployment guide:"
          say "  #{File.join(deployment_dir, 'README-GCP-DEPLOYMENT.md')}", :cyan
        end
      end

      private

      def generate_dockerfiles(directory)
        # Main Dockerfile
        main_dockerfile_path = File.join(directory, "Dockerfile")
        generate_dockerfile_content(main_dockerfile_path, options[:entry_point], options[:base_image])
        say "Created main Dockerfile at #{main_dockerfile_path}", :cyan

        # Agent Dockerfiles (if specified)
        options[:agent_entry_points]&.each_with_index do |agent_entry, index|
          agent_name = File.basename(agent_entry, ".rb").gsub(/[^0-9a-z_.-]/i, '_')
          agent_dockerfile_path = File.join(directory, "Dockerfile.agent.#{agent_name}.#{index}")
          generate_dockerfile_content(agent_dockerfile_path, agent_entry, options[:base_image])
          say "Created agent Dockerfile for '#{agent_entry}' at #{agent_dockerfile_path}", :cyan
        end
      end

      def generate_dockerfile_content(path, entry_point, base_image)
        # Basic validation for entry point format (crude check)
        unless entry_point && entry_point.include?('/') || entry_point.start_with?('bin/')
          say "Warning: Entry point '#{entry_point}' does not look like a path. Ensure it's correct.", :yellow
        end

        content = <<~DOCKERFILE
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
              && apt-get clean && \
              rm -rf /var/lib/apt/lists/*

          # Install Bundler
          RUN gem install bundler --no-document

          # Copy dependency definition files
          COPY Gemfile Gemfile.lock ./

          # Install gems
          RUN bundle install --jobs $(nproc) --retry 3 --without development test

          # Copy the rest of the application code
          # Ensure .dockerignore is properly configured
          COPY . .

          # --- Runtime Environment Variables ---
          # Set sensible defaults, overrideable at runtime (e.g., via Cloud Run)
          ENV RACK_ENV="production"
          ENV PORT="8080" # Required by Cloud Run unless overridden
          ENV ADK_LOG_LEVEL="INFO"

          # Required for ADK session state, override with actual Redis URL
          ENV REDIS_URL="redis://localhost:6379"
          ENV ADK_SESSION_SERVICE="redis"

          # Required by ADK for Gemini access, override with secret injection
          ENV GOOGLE_API_KEY=""

          # Expose the port the application listens on
          EXPOSE ${PORT}

          # --- Entry Point ---
          # Runs the specified application or agent script
          CMD ["bundle", "exec", "ruby", "#{entry_point}"]
        DOCKERFILE

        File.write(path, content)
      end

      def generate_dockerignore(directory)
        dockerignore_path = File.join(directory, ".dockerignore")
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

      # --- Sample Entrypoint Generation (Optional, generic) ---
      def generate_sample_entrypoint_script
        sample_path = File.expand_path(DEFAULT_SAMPLE_ENTRYPOINT_PATH)
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

        content = <<~RUBY
          #!/usr/bin/env ruby
          # frozen_string_literal: true

          # --- Generated Sample ADK Web Entrypoint ---#{' '}
          # This script provides a basic starting point for running ADK with a web server
          # and includes a /healthz endpoint suitable for Cloud Run health checks.

          require 'adk'
          require 'sinatra/base'
          require 'logger'

          # --- Configuration ---
          # ADK components will often rely on environment variables for configuration
          # (e.g., REDIS_URL, ADK_SESSION_SERVICE, GOOGLE_API_KEY, PORT).
          # Ensure these are set correctly in your deployment environment (e.g., Cloud Run).

          # Configure ADK basic settings
          ADK.configure do |config|
            config.logger = Logger.new($stdout)
            # Set log level via ENV ('DEBUG', 'INFO', 'WARN', 'ERROR') or default to INFO
            config.log_level = Logger.const_get(ENV.fetch('ADK_LOG_LEVEL', 'INFO').upcase) rescue Logger::INFO
            # ADK should automatically pick up Redis if ENV['ADK_SESSION_SERVICE'] == 'redis'
            # and ENV['REDIS_URL'] is set.
            # config.definition_store_path = './tools' # Optional: Specify tool definition path
          end

          # --- Health Check Application ---
          # A simple Rack app to respond to health checks.
          class HealthCheckApp < Sinatra::Base
            configure do
              # Disable Sinatra's built-in logging if ADK logger is preferred
              # disable :logging
              # set :dump_errors, false
            end

            get '/healthz' do
              ADK.logger.debug("Health check received.")
              status 200
              headers 'Content-Type' => 'text/plain'
              body 'OK'
            end
          end

          ADK.logger.info("Sample ADK Web Entrypoint starting...")
          ADK.logger.info("Log Level: #{ADK.config.log_level}")

          # --- ADK Agent/Application Logic Integration ---#{' '}
          # OPTION 1: Run agents or tasks in background threads (if needed)
          # Thread.new do
          #   begin
          #     ADK.logger.info("Starting background ADK agent...")
          #     # Example: agent = ADK::Agent::YourAgent.new
          #     # agent.run_loop
          #     sleep
          #   rescue => e
          #     ADK.logger.error("Error in background agent thread: #{e.message}\n#{e.backtrace.join("\n")}")
          #   end
          # end

          # OPTION 2: Add other Rack applications to be mounted by the web server
          # class MyApp < Sinatra::Base
          #   get '/' do
          #     'Hello from MyApp!'
          #   end
          # end
          # ADK::Web::Server.mount('/', MyApp)

          # --- Mount Health Check and Start Server ---
          # Ensure the ADK::Web::Server implementation supports mounting apps.
          # This assumes it uses something like Rack::Builder.
          ADK::Web::Server.mount('/healthz', HealthCheckApp.new)

          # The ADK Web Server should respect the PORT environment variable (default 8080 for Cloud Run).
          # This is typically a blocking call that starts the web server.
          begin
            ADK::Web::Server.run!
          rescue => e
            ADK.logger.fatal("ADK Web Server failed to start: #{e.message}")
            ADK.logger.fatal(e.backtrace.join("\n"))
            exit 1 # Exit if server fails to start
          end

          ADK.logger.info('ADK Web Server stopped.')

        RUBY

        File.write(sample_path, content)
        # Make the script executable
        FileUtils.chmod(0755, sample_path)
      end

      # --- GCP Asset Generation (Only called if --cloud gcp) ---
      def generate_gcp_assets(directory)
        say "Generating GCP specific assets...", :magenta
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
          say "Error: --gcp-project-id is required for GCP deployment.", :red
          say "You must provide an existing GCP project ID where you have appropriate permissions.", :yellow
          say "If you need to create a new project first, you could use a command like this ", :yellow
          say "After ensuring billing is configured for your account):", :yellow
          say "  gcloud projects create #{suggested_project_id}", :cyan
          say "Then, re-run this command adding the flag:", :yellow
          say "  --gcp-project-id #{suggested_project_id}", :cyan
          exit 1 # Stop execution, user needs to provide a valid project ID
        end

        # --- Project ID is present, proceed ---
        region = options[:gcp_region] # Use the class_option value

        # 1. Attempt to create gcloud configuration
        gcp_config_name = create_gcloud_config(options[:name], project_id, region)

        # 2. Generate GCP specific config files (optional for now, script preferred)
        # generate_gcp_redis_config(directory)
        # generate_gcp_cloud_run_config(directory)

        # 3. Generate GCP deploy script
        generate_gcp_deploy_script(directory)

        # 4. Generate/Copy GCP docs
        generate_gcp_deployment_docs(directory)

        return gcp_config_name # Return the generated name for the final message
      end

      # Helper to execute shell commands and check status
      def run_gcloud_command(command, error_message)
        say "Executing: gcloud #{command}", :detail # Use detail or another level
        output = `gcloud #{command} 2>&1` # Capture stderr too
        unless $?.success?
          say "Error: #{error_message}", :red
          say "gcloud output:\n#{output}", :red
          # Decide if we should exit or just warn
          # For config commands, maybe warn and continue?
          # For critical commands in deploy script, exit is better.
          # Let's warn for config issues but allow script generation.
          say "Warning: Failed to automatically configure gcloud. Please ensure configuration is correct manually.",
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
        unless system('command -v gcloud > /dev/null 2>&1')
          say "Error: 'gcloud' command not found in PATH. Cannot create gcloud configuration.", :red
          say "Please install the Google Cloud SDK.", :yellow
          return nil # Cannot proceed
        end

        # 1. Create or check configuration
        # Use describe to check existence non-destructively
        `gcloud config configurations describe #{config_name} > /dev/null 2>&1`
        if $?.success?
          say "Configuration '#{config_name}' already exists. Settings will be updated.", :yellow
        else
          # Try to create (use --no-activate)
          unless run_gcloud_command("config configurations create #{config_name} --no-activate",
                                    "Failed to create gcloud configuration '#{config_name}'.")
            return nil # Failed, can't set properties
          end

          say "Created gcloud configuration: #{config_name}"
        end

        # 2. Set properties
        run_gcloud_command("config set project #{project_id} --configuration=#{config_name}",
                           "Failed to set project in gcloud config.")
        run_gcloud_command("config set compute/region #{region} --configuration=#{config_name}",
                           "Failed to set region in gcloud config.")
        # Add other relevant defaults? e.g., run/region?
        # run_gcloud_command("config set run/region #{region} --configuration=#{config_name}", "Failed to set run/region in gcloud config.")

        config_name # Return the name used
      end

      # --- GCP Specific Helper Methods ---
      def generate_gcp_redis_config(directory)
        instance_name = options[:gcp_redis_instance_name]
        redis_config_path = File.join(directory, "redis-memorystore.yaml")

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

      def generate_gcp_cloud_run_config(directory)
        # Note: Generating a static YAML is less flexible than the deploy script.
        # The script can dynamically fetch Redis IP etc. Keeping this commented out
        # as generating the script is generally preferred.
        say "Skipping generation of static cloud-run-service.yaml, deploy script is preferred.", :yellow
      end

      def generate_gcp_deploy_script(directory)
        deploy_script_path = File.join(directory, "deploy-gcp.sh")

        # Extract GCP options with defaults from class_options
        project_id = options[:gcp_project_id] # Already validated in generate_gcp_assets
        region = options[:gcp_region]
        redis_name = options[:gcp_redis_instance_name]
        main_service_name = options[:gcp_service_name]
        main_memory = options[:gcp_memory]
        main_cpu = options[:gcp_cpu]
        base_name = options[:name] # Used for image naming

        # Image names
        main_image_name = "#{base_name}-web" # Assume main entry point is web
        main_image_tag = "latest"
        main_image_uri = "#{region}-docker.pkg.dev/#{project_id}/adk-images/#{main_image_name}:#{main_image_tag}"
        # Note: Repo 'adk-images' is assumed; could be made configurable

        # --- Script Content ---
        # This script is more comprehensive than before, includes setup
        script_content = <<~BASH
          #!/bin/bash
          # Generated by ADK CLI for GCP Cloud Run deployment
          set -euo pipefail # Enable strict mode

          # --- Configuration (Edit these if needed) ---
          PROJECT_ID="#{project_id}"
          REGION="#{region}"
          REDIS_INSTANCE_NAME="#{redis_name}"
          MAIN_SERVICE_NAME="#{main_service_name}"
          MAIN_DOCKERFILE="Dockerfile"
          MAIN_IMAGE_NAME="#{main_image_name}"
          MAIN_IMAGE_TAG="#{main_image_tag}"
          MAIN_MEMORY="#{main_memory}"
          MAIN_CPU="#{main_cpu}"

          # Secrets Configuration
          SECRET_NAME="google-api-key" # Name of the secret in Secret Manager
          SECRET_ENV_VAR="GOOGLE_API_KEY" # Env var name in Cloud Run

          # Artifact Registry Repository
          AR_REPO_NAME="adk-images" # Artifact Registry repo name
          AR_LOCATION="#{region}" # Often same as REGION, but can differ

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
            echo "[ERROR] $1" >&2
            exit 1
          }

          check_command() {
            command -v "$1" >/dev/null 2>&1 || error "$1' command not found. Please install it."
          }

          # --- Prerequisites Check ---
          info "Checking prerequisites..."
          check_command gcloud
          check_command docker

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
          info "Configuring Docker authentication for ${AR_LOCATION}..."
          gcloud auth configure-docker "${AR_LOCATION}-docker.pkg.dev" || error "Docker auth configuration failed"

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
            # info "Granting default compute SA access to secret..."
            # PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')
            # DEFAULT_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
            # gcloud secrets add-iam-policy-binding ${SECRET_NAME} \
            #    --member="serviceAccount:${DEFAULT_SA}" \
            #    --role="roles/secretmanager.secretAccessor" \
            #    --project="${PROJECT_ID}" || echo "Warning: Failed to grant default SA access to secret. Ensure the running service account has access."
          else
            info "Secret '${SECRET_NAME}' already exists."
          fi
          SECRET_RESOURCE="projects/${PROJECT_ID}/secrets/${SECRET_NAME}/versions/latest"

          # --- Build and Push Main Docker Image ---
          info "Building main application image: ${MAIN_IMAGE_URI}..."
          # Using Cloud Build is generally recommended for CI/CD
          gcloud builds submit --tag "${MAIN_IMAGE_URI}" --project="${PROJECT_ID}" --dockerfile="${MAIN_DOCKERFILE}" . || error "Failed to build main image"
          # Alternatively, build locally:
          # docker build -t "${MAIN_IMAGE_URI}" -f "${MAIN_DOCKERFILE}" . || error "Failed to build main image"
          # docker push "${MAIN_IMAGE_URI}" || error "Failed to push main image"

          # --- Build and Push Agent Docker Images (if configured) ---
          # <<< Add logic here to loop through agent entry points, build and push their images >>>
          # Example for one agent:
          # AGENT_SERVICE_NAME="adk-agent-processor"
          # AGENT_DOCKERFILE="Dockerfile.agent.processor"
          # AGENT_IMAGE_NAME="adk-agent-processor"
          # AGENT_IMAGE_URI="${AR_LOCATION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO_NAME}/${AGENT_IMAGE_NAME}:${MAIN_IMAGE_TAG}"
          # info "Building agent image: ${AGENT_IMAGE_URI}..."
          # gcloud builds submit --tag "${AGENT_IMAGE_URI}" --project="${PROJECT_ID}" --dockerfile="${AGENT_DOCKERFILE}" . || error "Failed to build agent image"

          # --- Deploy Main Service to Cloud Run ---
          info "Deploying main service '${MAIN_SERVICE_NAME}' to Cloud Run in ${REGION}..."
          DEPLOY_ARGS=(
            "${MAIN_SERVICE_NAME}" \
            --project="${PROJECT_ID}" \
            --region="${REGION}" \
            --image="${MAIN_IMAGE_URI}" \
            --platform="managed" \
            --memory="${MAIN_MEMORY}" \
            --cpu="${MAIN_CPU}" \
            --port="8080" \
            --set-env-vars="REDIS_URL=${REDIS_URL},ADK_SESSION_SERVICE=redis,RACK_ENV=production" \
            --set-secrets="${SECRET_ENV_VAR}=${SECRET_RESOURCE}" \
            --vpc-connector="${VPC_CONNECTOR_FULL_NAME}" \
            --vpc-egress="all-traffic" \
            --allow-unauthenticated # Remove if service should not be public
          )
          if [[ -n "${RUN_SERVICE_ACCOUNT}" ]]; then
            DEPLOY_ARGS+=(--service-account="${RUN_SERVICE_ACCOUNT}")
            info "Using service account: ${RUN_SERVICE_ACCOUNT}"
            # Ensure this SA has roles/secretmanager.secretAccessor for the secret!
          else
             info "Using default Compute Engine service account. Ensure it has Secret Accessor role."
          fi

          gcloud run deploy "${DEPLOY_ARGS[@]}" || error "Failed to deploy main service '${MAIN_SERVICE_NAME}'"

          # --- Deploy Agent Services to Cloud Run (if configured) ---
          # <<< Add logic here to loop through agents and deploy them >>>
          # Example for one agent:
          # info "Deploying agent service '${AGENT_SERVICE_NAME}'..."
          # gcloud run deploy "${AGENT_SERVICE_NAME}" \
          #   --project="${PROJECT_ID}" \
          #   --region="${REGION}" \
          #   --image="${AGENT_IMAGE_URI}" \
          #   --platform="managed" \
          #   --memory="512Mi" # Agent specific memory
          #   --cpu="1" # Agent specific CPU
          #   --no-traffic # Agents often don't need external traffic
          #   --set-env-vars="REDIS_URL=${REDIS_URL},ADK_SESSION_SERVICE=redis,RACK_ENV=production" \
          #   --set-secrets="${SECRET_ENV_VAR}=${SECRET_RESOURCE}" \
          #   --vpc-connector="${VPC_CONNECTOR_FULL_NAME}" \
          #   --vpc-egress="all-traffic" \
          #   ${RUN_SERVICE_ACCOUNT:+--service-account="${RUN_SERVICE_ACCOUNT"} || error "Failed to deploy agent service '${AGENT_SERVICE_NAME}'"}

          # --- Deployment Complete ---
          info "Deployment successful!"
          MAIN_SERVICE_URL=$(gcloud run services describe "${MAIN_SERVICE_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --platform="managed" --format="value(status.url)")
          if [[ -n "${MAIN_SERVICE_URL}" ]]; then
            info "Main service '${MAIN_SERVICE_NAME}' URL: ${MAIN_SERVICE_URL}"
          else
            info "Main service '${MAIN_SERVICE_NAME}' deployed, but URL not available yet."
          fi

        BASH

        File.write(deploy_script_path, content)
        FileUtils.chmod(0755, deploy_script_path)
        say "Created GCP deployment script at #{deploy_script_path}", :cyan
        say "Please review and customize the script, especially the Configuration section, before running.", :yellow
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

      # --- AWS Asset Generation (Placeholder) ---
      def generate_aws_assets(directory)
        say "AWS deployment asset generation is not yet implemented.", :yellow
        # Placeholder for future: generate CloudFormation/CDK/Terraform, deploy scripts etc.
      end

      # --- Azure Asset Generation (Placeholder) ---
      def generate_azure_assets(directory)
        say "Azure deployment asset generation is not yet implemented.", :yellow
        # Placeholder for future: generate ARM templates/Bicep, deploy scripts etc.
      end
    end
  end
end
