# File: lib/adk/cli/deployment_commands.rb
# frozen_string_literal: true

require 'thor'
require 'fileutils'
require 'json'
require 'yaml'
require 'logger' # Needed for sample entrypoint

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

      desc 'generate [DIRECTORY]', 'Generate deployment assets for GCP Cloud Run'
      method_option :entry_point, type: :string, aliases: "-e", desc: 'Entry point for the main agent application'
      method_option :agent_entry_points, type: :array, aliases: "-a",
                                         desc: 'Entry points for user agents (comma separated)'
      method_option :redis_instance_name, type: :string, aliases: "-r", default: 'adk-redis',
                                          desc: 'Name for the MemoryStore Redis instance'
      method_option :project_id, type: :string, aliases: "-p", desc: 'Google Cloud project ID'
      method_option :region, type: :string, default: 'us-central1', desc: 'Google Cloud region'
      method_option :memory, type: :string, default: '2Gi', desc: 'Memory allocation for Cloud Run service'
      method_option :cpu, type: :string, default: '1', desc: 'CPU allocation for Cloud Run service'
      method_option :service_name, type: :string, default: 'adk-agent-service', desc: 'Name for the Cloud Run service'
      method_option :name, type: :string, aliases: "-n", default: DEFAULT_DEPLOYMENT_DIR_NAME,
                           desc: 'Base name for the output directory and potentially generated resources'
      method_option :base_image, type: :string, default: DEFAULT_RUBY_IMAGE, desc: 'Base Ruby Docker image to use'
      method_option :generate_sample_entrypoint, type: :boolean, default: false,
                                                 desc: "Generate a sample web entrypoint script (#{DEFAULT_SAMPLE_ENTRYPOINT_PATH}) with a /healthz check."

      # --- GCP Specific Options (Only relevant if --cloud gcp) ---
      # We access these directly from `options` hash within GCP-specific methods for now.
      # A more robust approach might involve subcommands or conditional option parsing.
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
        FileUtils.mkdir_p(deployment_dir)

        say "Generating deployment assets in #{deployment_dir}...", :green

        # 0. Generate sample entrypoint if requested (BEFORE generating Dockerfiles)
        if options[:generate_sample_entrypoint]
          generate_sample_entrypoint_script
        end

        # Generate Docker files
        generate_main_dockerfile(deployment_dir)
        generate_agent_dockerfiles(deployment_dir, options[:agent_entry_points]) if options[:agent_entry_points]

        # Generate Redis MemoryStore configuration
        generate_redis_config(deployment_dir, options[:redis_instance_name])

        # Generate deployment scripts and configurations
        generate_cloud_run_config(deployment_dir, options)

        # Generate documentation
        generate_deployment_docs(File.join(directory, "docs"))

        say "Deployment assets generated successfully!", :green
        say "See the documentation at docs/go-to-gcp-production-claude.md for deployment instructions.", :green
      end

      private

      def generate_main_dockerfile(directory)
        dockerfile_path = File.join(directory, "Dockerfile")

        content = <<~DOCKERFILE
          FROM ruby:3.2-slim

          WORKDIR /app

          # Install system dependencies
          RUN apt-get update && apt-get install -y \\
              build-essential \\
              git \\
              && rm -rf /var/lib/apt/lists/*

          # Copy Gemfile and install gems
          COPY Gemfile Gemfile.lock ./
          RUN bundle install

          # Copy the application code
          COPY . .

          # Environment variables
          ENV REDIS_URL="redis://localhost:6379"
          ENV RACK_ENV="production"
          ENV PORT="8080"

          # You can override these with your own values at runtime
          ENV GOOGLE_API_KEY=""
          ENV ADK_SESSION_SERVICE="redis"

          # Start the application
          CMD ["bundle", "exec", "bin/adk", "web", "start"]

          # The default is to start the web interface
          # To use a custom entry point, override this with your own command
          # Example: CMD ["bundle", "exec", "bin/adk", "agent", "start", "your_agent_name"]
        DOCKERFILE

        File.write(dockerfile_path, content)
        say "Created main Dockerfile at #{dockerfile_path}", :cyan
      end

      def generate_agent_dockerfiles(directory, agent_entry_points)
        agent_entry_points&.each_with_index do |entry_point, index|
          dockerfile_path = File.join(directory, "Dockerfile.agent.#{index + 1}")

          content = <<~DOCKERFILE
            FROM ruby:3.2-slim

            WORKDIR /app

            # Install system dependencies
            RUN apt-get update && apt-get install -y \\
                build-essential \\
                git \\
                && rm -rf /var/lib/apt/lists/*

            # Copy Gemfile and install gems
            COPY Gemfile Gemfile.lock ./
            RUN bundle install

            # Copy the application code
            COPY . .

            # Environment variables
            ENV REDIS_URL="redis://localhost:6379"
            ENV RACK_ENV="production"

            # You can override these with your own values at runtime
            ENV GOOGLE_API_KEY=""
            ENV ADK_SESSION_SERVICE="redis"

            # Start the specific agent
            CMD ["bundle", "exec", "bin/adk", "agent", "start", "#{entry_point}"]
          DOCKERFILE

          File.write(dockerfile_path, content)
          say "Created agent Dockerfile at #{dockerfile_path}", :cyan
        end
      end

      def generate_redis_config(directory, instance_name)
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
            authorizedNetwork: default
            # You can adjust memory size, version and other parameters as needed
        YAML

        File.write(redis_config_path, content)
        say "Created Redis MemoryStore configuration at #{redis_config_path}", :cyan
      end

      def generate_cloud_run_config(directory, options)
        service_name = options[:service_name] || "adk-agent-service"
        region = options[:region] || "us-central1"
        memory = options[:memory] || "2Gi"
        cpu = options[:cpu] || "1"

        cloud_run_config_path = File.join(directory, "cloud-run-service.yaml")

        content = <<~YAML
          apiVersion: serving.knative.dev/v1
          kind: Service
          metadata:
            name: #{service_name}
          spec:
            template:
              metadata:
                annotations:
                  autoscaling.knative.dev/minScale: "1"
                  autoscaling.knative.dev/maxScale: "5"
              spec:
                containers:
                - image: ${PROJECT_ID}/#{service_name}:latest
                  resources:
                    limits:
                      memory: "#{memory}"
                      cpu: "#{cpu}"
                  env:
                  - name: REDIS_URL
                    value: "redis://${REDIS_IP}:6379"
                  - name: GOOGLE_API_KEY
                    valueFrom:
                      secretKeyRef:
                        name: google-api-key
                        key: api-key
                  - name: ADK_SESSION_SERVICE
                    value: "redis"
        YAML

        File.write(cloud_run_config_path, content)
        say "Created Cloud Run configuration at #{cloud_run_config_path}", :cyan

        # Generate deployment script
        deploy_script_path = File.join(directory, "deploy.sh")

        script_content = <<~BASH
          #!/bin/bash
          set -e

          # Check if gcloud is installed
          if ! command -v gcloud &> /dev/null; then
            echo "gcloud CLI is not installed. Please install it first."
            exit 1
          fi

          # Set default values
          PROJECT_ID="${1:-\$(gcloud config get-value project)}"
          REGION="${2:-us-central1}"
          SERVICE_NAME="${3:-adk-agent-service}"
          REDIS_NAME="${4:-adk-redis}"

          echo "Deploying ADK to Google Cloud..."
          echo "Project ID: $PROJECT_ID"
          echo "Region: $REGION"
          echo "Service Name: $SERVICE_NAME"
          echo "Redis Instance Name: $REDIS_NAME"

          # Create Redis MemoryStore instance if it doesn't exist
          if ! gcloud redis instances describe $REDIS_NAME --region=$REGION &> /dev/null; then
            echo "Creating Redis MemoryStore instance..."
            gcloud redis instances create $REDIS_NAME \\
              --size=1 \\
              --region=$REGION \\
              --redis-version=redis_6_x
          fi

          # Get Redis IP address
          REDIS_IP=$(gcloud redis instances describe $REDIS_NAME --region=$REGION --format="get(host)")
          echo "Redis IP: $REDIS_IP"

          # Build and push Docker image
          echo "Building and pushing Docker image..."
          gcloud builds submit --tag gcr.io/$PROJECT_ID/$SERVICE_NAME .

          # Create API key secret if it doesn't exist
          if ! gcloud secrets describe google-api-key &> /dev/null; then
            echo "Creating Google API key secret..."
            read -p "Enter your Google API key: " API_KEY
            echo -n "$API_KEY" | gcloud secrets create google-api-key --data-file=-
          fi

          # Deploy to Cloud Run
          echo "Deploying to Cloud Run..."
          gcloud run deploy $SERVICE_NAME \\
            --image gcr.io/$PROJECT_ID/$SERVICE_NAME \\
            --platform managed \\
            --region $REGION \\
            --memory ${5:-2Gi} \\
            --cpu ${6:-1} \\
            --set-env-vars="REDIS_URL=redis://$REDIS_IP:6379,ADK_SESSION_SERVICE=redis,RACK_ENV=production" \\
            --set-secrets="GOOGLE_API_KEY=google-api-key:latest" \\
            --allow-unauthenticated

          echo "Deployment completed successfully!"
          echo "Your ADK service is available at: $(gcloud run services describe $SERVICE_NAME --region=$REGION --format='value(status.url)')"
        BASH

        File.write(deploy_script_path, script_content)
        FileUtils.chmod(0755, deploy_script_path)
        say "Created deployment script at #{deploy_script_path}", :cyan
      end

      def generate_deployment_docs(directory)
        FileUtils.mkdir_p(directory) unless File.directory?(directory)

        docs_path = File.join(directory, "go-to-gcp-production-claude.md")

        content = <<~MARKDOWN
          # Deploying ADK to Google Cloud Platform

          This guide will help you deploy your ADK application to Google Cloud Platform (GCP) using Cloud Run and Redis MemoryStore.

          ## Prerequisites

          1. [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) installed and configured
          2. A Google Cloud Platform account with billing enabled
          3. Your ADK application code ready for deployment
          4. Google API key

          ## Overview

          The deployment process consists of the following steps:

          1. Generate deployment assets using ADK CLI
          2. Create a Redis MemoryStore instance for session storage
          3. Build and deploy Docker containers to Cloud Run
          4. Configure environment variables and secrets

          ## Step 1: Generate Deployment Assets

          Use the ADK CLI to generate all necessary deployment assets:

          ```bash
          # Basic deployment generation
          adk deployment generate

          # With agent entry points
          adk deployment generate --agent-entry-points agent1,agent2

          # With custom project and region
          adk deployment generate --project-id your-project-id --region us-west1
          ```

          This command creates a `deployment` directory containing:
          - Dockerfile for the main ADK application
          - Dockerfiles for agent processes (if specified)
          - Redis MemoryStore configuration
          - Cloud Run service configuration
          - Deployment script

          ## Step 2: Review and Customize

          Review the generated files and customize them as needed:

          - `deployment/Dockerfile`: Main application container
          - `deployment/Dockerfile.agent.*`: Agent-specific containers (if applicable)
          - `deployment/redis-memorystore.yaml`: Redis configuration
          - `deployment/cloud-run-service.yaml`: Cloud Run service configuration
          - `deployment/deploy.sh`: Deployment script

          You may need to adjust memory allocations, CPU resources, or environment variables.

          ## Step 3: Deploy to GCP

          You can deploy to GCP using the provided deployment script:

          ```bash
          cd deployment
          ./deploy.sh [PROJECT_ID] [REGION] [SERVICE_NAME] [REDIS_NAME] [MEMORY] [CPU]
          ```

          Or you can deploy manually with these steps:

          ### 3.1 Create Redis MemoryStore Instance

          ```bash
          gcloud redis instances create adk-redis \\
            --size=1 \\
            --region=us-central1 \\
            --redis-version=redis_6_x
          ```

          Note the IP address of your Redis instance:

          ```bash
          gcloud redis instances describe adk-redis --region=us-central1 --format="get(host)"
          ```

          ### 3.2 Create Secret for API Key

          ```bash
          echo -n "your-api-key" | gcloud secrets create google-api-key --data-file=-
          ```

          ### 3.3 Build and Push Docker Image

          ```bash
          gcloud builds submit --tag gcr.io/your-project-id/adk-agent-service .
          ```

          ### 3.4 Deploy to Cloud Run

          ```bash
          gcloud run deploy adk-agent-service \\
            --image gcr.io/your-project-id/adk-agent-service \\
            --platform managed \\
            --region us-central1 \\
            --memory 2Gi \\
            --cpu 1 \\
            --set-env-vars="REDIS_URL=redis://$REDIS_IP:6379,ADK_SESSION_SERVICE=redis,RACK_ENV=production" \\
            --set-secrets="GOOGLE_API_KEY=google-api-key:latest" \\
            --allow-unauthenticated
          ```

          ## Architecture

          The deployment architecture consists of:

          1. **Cloud Run Services**:
             - Main ADK service running the web interface
             - Optional separate services for long-running agents

          2. **Redis MemoryStore**:
             - Session storage for ADK
             - Shared state between services

          3. **Container Registry**:
             - Stores Docker images for all services

          ## Environment Variables

          The following environment variables are set in the deployment:

          - `REDIS_URL`: Connection string for Redis MemoryStore
          - `GOOGLE_API_KEY`: API key for your chosen model provider
          - `ADK_SESSION_SERVICE`: Set to "redis" to enable Redis session storage
          - `RACK_ENV`: Set to "production" for production environment
          - `PORT`: Set to 8080 for Cloud Run

          ## Multi-Container Deployment

          If you're using multiple agents that need to run independently, you can:

          1. Deploy the main ADK web interface as one service
          2. Deploy each agent as a separate Cloud Run service
          3. Ensure all services connect to the same Redis instance

          This allows agents to run continuously without being tied to the web interface.

          ## Scaling Considerations

          Cloud Run will automatically scale your services based on traffic. Configure the min/max instances based on your needs:

          ```yaml
          autoscaling.knative.dev/minScale: "1"
          autoscaling.knative.dev/maxScale: "5"
          ```

          For Redis MemoryStore, monitor your usage and upgrade the instance size if needed.

          ## Troubleshooting

          ### Connection Issues with Redis

          Ensure the REDIS_URL environment variable is correctly set and that your Cloud Run service has network access to your Redis instance.

          ### Container Crashes

          Check the Cloud Run logs for details on any crashes or errors:

          ```bash
          gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=adk-agent-service"
          ```

          ### API Key Issues

          Verify that your secret was created correctly and is being properly mounted in your service.
        MARKDOWN

        File.write(docs_path, content)
        say "Created deployment documentation at #{docs_path}", :cyan
      end

      # --- Sample Entrypoint Generation ---
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
    end
  end
end
