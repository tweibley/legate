# Deploying your ADK Ruby Agent to Google Cloud Run

This guide outlines the steps and considerations for deploying your ADK-based Ruby agent to Google Cloud Run. It assumes you have some familiarity with Google Cloud Platform (GCP), Docker, and the `gcloud` command-line tool.

## Overview

Deploying your ADK agent to GCP typically involves these steps:

1.  Generate deployment assets (Dockerfile, configuration).
2.  Create a Redis instance (Memorystore) for session/state management.
3.  Manage secrets (like API keys) using Secret Manager.
4.  Build a Docker container image of your agent.
5.  Push the image to Artifact Registry.
6.  Deploy the image to Cloud Run, configuring environment variables, networking, service identity, and health checks.

## Prerequisites

1.  **Google Cloud Project:** You need an active GCP project with billing enabled.
2.  **`gcloud` CLI:** Ensure the Google Cloud SDK is installed and authenticated (`gcloud auth login`, `gcloud config set project YOUR_PROJECT_ID`).
3.  **Docker:** Docker must be installed locally to build container images.
4.  **Enabled APIs:** Enable the following APIs in your GCP project:
    *   Cloud Run API
    *   Artifact Registry API
    *   Memorystore for Redis API
    *   Secret Manager API
    *   Cloud Build API (Recommended for automated builds)
    ```bash
    gcloud services enable run.googleapis.com \
        artifactregistry.googleapis.com \
        redis.googleapis.com \
        secretmanager.googleapis.com \
        cloudbuild.googleapis.com
    ```
5.  **ADK Application:** Your ADK Ruby agent application code.
6.  **Model Provider API Key:** The API key for your language model (e.g., Anthropic, OpenAI).

## Proposed `adk generate deployment` Command

To streamline the deployment process, we propose a new command:

```bash
adk generate deployment --cloud gcp --entrypoint path/to/your/entrypoint.rb [--agent-entrypoints path/to/agent1.rb] [--name my-deployment] [--generate-sample-entrypoint]
```

**Functionality:**

This command would create a `deployment/` directory (or similar) containing:

1.  **Generate `Dockerfile`:** A basic `Dockerfile` tailored for the main ADK agent process (using the `--entrypoint`).
2.  **Generate Agent `Dockerfile`s (Optional):** If `--agent-entrypoints` is provided, generate separate `Dockerfile.agent.<name>` files for each agent entry point. This facilitates deploying agents as separate Cloud Run services if needed.
3.  **Generate Provider-Specific Assets:** Based on the `--cloud` flag:
    *   `--cloud gcp`: Generate `deploy-gcp.sh` script and `README-GCP-DEPLOYMENT.md`.
    *   `--cloud aws`: (Future) Generate assets for AWS.
    *   `--cloud azure`: (Future) Generate assets for Azure.
    *   `--cloud none` or omitted: Generate only the generic Dockerfile(s) and `.dockerignore`.
4.  **Generate `.dockerignore`:** A `.dockerignore` file.
5.  **Generate Sample Entrypoint (Optional):** If `--generate-sample-entrypoint` is specified, create `bin/adk_web_entrypoint.rb`. This script provides a basic web server setup with a `/healthz` endpoint, suitable for initial deployment testing.
6.  **Generate Cloud-Specific Deploy Script:** A shell script template named according to the cloud provider (e.g., `deploy-gcp.sh`, `deploy-aws.sh`) with placeholders and logic for deploying the service(s) to that provider.
7.  **Provide Instructions:** Output guidance on the next steps relevant to the chosen cloud provider.

**Parameters:**

*   `--cloud`: **Required** (or defaults to `none`). Specifies the target deployment environment.
*   `--entrypoint`: **Required.** Specifies the relative path to the main Ruby script for the primary ADK process. *If using `--generate-sample-entrypoint`, you likely want to set this to `bin/adk_web_entrypoint.rb`.*
*   `--agent-entrypoints`: Optional. A comma-separated list of relative paths to Ruby scripts for separate, long-running agent processes.
*   `--name`: Optional. A base name used for generated files/directories (e.g., `my-deployment/`). Defaults to `deployment`.
*   `--base-image`: Optional. Specify a custom base Ruby image for the `Dockerfile`(s). Defaults to a recent official Ruby image.
*   `--generate-sample-entrypoint`: Optional (boolean). If true, generates `bin/adk_web_entrypoint.rb` with a `/healthz` check.

**Rationale:**

This command structure automates boilerplate creation for various targets, reducing setup time and potential errors. It supports different deployment patterns (single service vs. multiple agent services) and is extensible.

1.  **Expose an Endpoint:** If your ADK application runs a web server (e.g., via the `--entrypoint`), expose a simple HTTP endpoint (e.g., `/healthz`) that returns a `200 OK` status when the application is healthy and ready. **Tip:** Using the `--generate-sample-entrypoint` flag when running `adk generate deployment` will create a `bin/adk_web_entrypoint.rb` script that already includes a basic `/healthz` endpoint.
2.  **Configure Probes:** Use flags during deployment:
    ```bash
    gcloud run deploy ${SERVICE_NAME} \
      ...
      # Check every 15s after initial 10s delay, fail after 3 consecutive failures
      --probe-liveness=http://localhost:8080/healthz?path=/healthz,initial-delay-seconds=10,period-seconds=15,failure-threshold=3 \
      # Check startup using the same endpoint, fail faster
      --probe-startup=http://localhost:8080/healthz?path=/healthz,initial-delay-seconds=5,period-seconds=5,failure-threshold=3 \
      # Give more CPU during startup if needed
      --startup-cpu-boost \
      ...
    ```
    Adjust the path (`/healthz`), port (`8080`), and timing parameters as needed.

*(Note: This command is currently a proposal and not implemented in the ADK.)*

## Generating Deployment Assets Manually (for GCP)

Until the `adk generate deployment --cloud gcp` command exists, you'll need to create these assets manually for a Google Cloud Run deployment.

### 1. `Dockerfile`

Create a file named `Dockerfile` in your project's root directory. This file defines how to build the container image for your agent.

```dockerfile
# Use an official Ruby runtime as a parent image
ARG RUBY_VERSION=3.2
FROM ruby:${RUBY_VERSION}-slim

# Set working directory
WORKDIR /usr/src/app

# Install dependencies
# - Install build tools needed for some gems
# - Clean up apt cache afterwards
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends build-essential git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Bundler
RUN gem install bundler

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Install gems
# Use --jobs to speed up installation, --retry for network issues
RUN bundle install --jobs $(nproc) --retry 3

# Copy the rest of the application code
COPY . .

# Expose the port the ADK Web server might run on (if applicable)
# Adjust if your ADK configuration uses a different port
EXPOSE 8080

# --- Environment Variables ---
# These should be set during Cloud Run deployment, not hardcoded here.
# ENV REDIS_URL="redis://<redis_ip>:<redis_port>"
# ENV ADK_LOG_LEVEL="INFO"
# Add any other environment variables your agent needs

# --- Entrypoint ---
# Replace 'path/to/your/agent/entrypoint.rb' with the actual path
# to your agent's main executable script relative to the project root.
# This script should initialize the ADK and start the agent process.
CMD ["bundle", "exec", "ruby", "path/to/your/agent/entrypoint.rb"]
```

**Considerations:**

*   **Base Image:** Choose a Ruby version compatible with your project. Slim variants are smaller.
*   **Dependencies:** Ensure `build-essential` and any other system libraries needed by your gems are installed.
*   **Entrypoint:** The `CMD` should execute the script that starts your ADK agent, typically initializing the `Adk::Agent` or similar core component. This *must* be correctly specified.
*   **User Code:** This `Dockerfile` assumes your agent code is part of the same project/repository. If your agent code lives elsewhere, you'll need to adjust the `COPY` instructions or use multi-stage builds.
*   **Ports:** If your agent uses the ADK's built-in web server (e.g., for health checks or simple UI), expose the relevant port (default is often 8080).

### 2. `.dockerignore`

Create a `.dockerignore` file in your project root to prevent unnecessary files from being copied into the Docker image, keeping it smaller and build times faster.

```
.git
.gitignore
.dockerignore
Dockerfile
*.gem
logs/
tmp/
coverage/
spec/
docs/
.env
.vscode/
.cursor/
# Add any other files/directories not needed in the final image
```

### 3. Memorystore for Redis Instance

ADK often relies on Redis for session management or state persistence between agent instances, especially in a scaled environment like Cloud Run.

**Create a Redis Instance:**

Use the `gcloud` command to create a Memorystore for Redis instance. Choose a region close to where you'll run your Cloud Run service.

```bash
# Choose a REGION (e.g., us-central1)
export REGION=us-central1
# Choose a unique NAME for your Redis instance
export REDIS_INSTANCE_NAME=adk-redis-instance
# Choose a TIER (e.g., BASIC, STANDARD_HA)
export REDIS_TIER=BASIC # Basic is suitable for development/testing

gcloud redis instances create ${REDIS_INSTANCE_NAME} \
    --size=1 \
    --region=${REGION} \
    --tier=${REDIS_TIER} \
    --redis-version=6.x # Or choose a supported version

# Note: Creating the instance can take several minutes.
```

**Get Connection Details:**

Once the instance is ready, you need its IP address and port.

```bash
gcloud redis instances describe ${REDIS_INSTANCE_NAME} --region=${REGION} \
    --format='value(host)' # This gives the IP address

# The default Redis port is 6379
```

You will use these to construct the `REDIS_URL` environment variable for your Cloud Run service (e.g., `redis://<instance_ip>:6379`).

**Networking:**

*   Ensure your Cloud Run service can connect to the Memorystore instance. This usually involves setting up a [Serverless VPC Access connector](https://cloud.google.com/vpc/docs/serverless-vpc-access) and configuring your Cloud Run service to use it. This connects your serverless environment to your VPC network where Memorystore resides.
*   Configure the VPC connector:
    ```bash
    # Choose a NAME for the connector
    export VPC_CONNECTOR_NAME=adk-vpc-connector
    # Choose a CIDR range for the connector (must not overlap with others)
    export CONNECTOR_IP_RANGE=10.8.0.0/28

    gcloud compute networks vpc-access connectors create ${VPC_CONNECTOR_NAME} \
        --region=${REGION} \
        --range=${CONNECTOR_IP_RANGE} \
        --network=default # Or your specific VPC network name
    ```

### 4. Secret Management (API Key)

Store your model provider API key securely using Secret Manager.

```bash
# Choose a NAME for your secret
export SECRET_NAME=google-api-key
# Replace "YOUR_API_KEY_HERE" with your actual key
echo -n "YOUR_API_KEY_HERE" | gcloud secrets create ${SECRET_NAME} --data-file=- \
    --replication-policy="automatic"

# Grant the Cloud Run service account access to the secret
# First, find the service account email for Cloud Run (often PROJECT_NUMBER-compute@developer.gserviceaccount.com)
# Or, preferably, create a dedicated service account for your Cloud Run service.
# See: https://cloud.google.com/run/docs/configuring/service-identity
# export RUN_SERVICE_ACCOUNT="your-service-account@your-project-id.iam.gserviceaccount.com"
# gcloud secrets add-iam-policy-binding ${SECRET_NAME} \
#     --member="serviceAccount:${RUN_SERVICE_ACCOUNT}" \
#     --role="roles/secretmanager.secretAccessor"
# Note: You might configure the service account access during the 'gcloud run deploy' step instead.
```

## Deployment Steps to Cloud Run

### 1. Configure Docker Authentication for Artifact Registry

Allow Docker to push images to your GCP Artifact Registry.

```bash
# Choose a REGION for your repository (can be different from Redis/Cloud Run)
export AR_REGION=us-central1
gcloud auth configure-docker ${AR_REGION}-docker.pkg.dev
```

### 2. Create an Artifact Registry Repository

You need a repository to store your Docker images.

```bash
# Choose a NAME for your repository
export AR_REPO_NAME=adk-agents
gcloud artifacts repositories create ${AR_REPO_NAME} \
    --repository-format=docker \
    --location=${AR_REGION} \
    --description="Docker repository for ADK agents"
```

### 3. Build and Push the Docker Image

Use Cloud Build (recommended) or local Docker to build and push the image.

```bash
# Get your GCP Project ID
export PROJECT_ID=$(gcloud config get-value project)
# Choose a NAME for your image (e.g., adk-web-service or adk-agent-processor)
export IMAGE_NAME=my-adk-agent
# Choose a TAG (e.g., latest, v1.0)
export IMAGE_TAG=latest
# Artifact Registry region
export AR_REGION=us-central1 # Should match the repository location

# Construct the full image path
export IMAGE_URI="${AR_REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}" # Ensure AR_REPO_NAME is set from Step 2

# Build using Cloud Build (reads Dockerfile from current dir)
gcloud builds submit --tag ${IMAGE_URI} .

# --- OR --- Build locally and push
# docker build -t ${IMAGE_URI} .
# docker push ${IMAGE_URI}
```
*(Repeat build/push for separate agent images if using a multi-container approach).*

### 4. Deploy to Cloud Run

Deploy the container image(s) using the `gcloud run deploy` command.

```bash
# Choose a NAME for your Cloud Run service (e.g., adk-web, adk-agent-x)
export SERVICE_NAME=adk-agent-service
# Get Redis info (Ensure REGION, REDIS_INSTANCE_NAME are set)
export REDIS_IP=$(gcloud redis instances describe ${REDIS_INSTANCE_NAME} --region=${REGION} --format='value(host)')
export REDIS_URL="redis://${REDIS_IP}:6379"
# VPC Connector info (Ensure PROJECT_ID, REGION, VPC_CONNECTOR_NAME are set)
export VPC_CONNECTOR_FULL_NAME="projects/${PROJECT_ID}/locations/${REGION}/connectors/${VPC_CONNECTOR_NAME}"
# Secret info (Ensure SECRET_NAME is set to 'google-api-key' or your chosen name)
export SECRET_RESOURCE="projects/${PROJECT_ID}/secrets/${SECRET_NAME}/versions/latest"
# Optional: Specify a dedicated service account
# export RUN_SERVICE_ACCOUNT="your-service-account@your-project-id.iam.gserviceaccount.com"

gcloud run deploy ${SERVICE_NAME} \
    --image=${IMAGE_URI} \
    --platform=managed \
    --region=${REGION} \
    --allow-unauthenticated \ # Or --no-allow-unauthenticated
    --set-env-vars="REDIS_URL=${REDIS_URL}" \
    --set-env-vars="ADK_SESSION_SERVICE=redis" \
    --set-env-vars="RACK_ENV=production" \
    --set-env-vars="ADK_LOG_LEVEL=INFO" \
    # Mount the API key secret as an environment variable
    --set-secrets="GOOGLE_API_KEY=${SECRET_RESOURCE}" \
    # Add any other necessary environment variables
    # --set-env-vars="VAR1=value1,VAR2=value2" \
    --vpc-connector=${VPC_CONNECTOR_FULL_NAME} \
    --vpc-egress=all-traffic \
    --port=8080 \ # Ensure this matches EXPOSE in Dockerfile and app config
    --memory=512Mi \ # Adjust as needed
    --cpu=1 \ # Adjust as needed
    # --startup-cpu-boost \ # Consider if startup is slow
    # --probe-startup=/healthz \ # Optional: Add startup probe
    # --probe-liveness=/healthz \ # Optional: Add liveness probe
    # --service-account=${RUN_SERVICE_ACCOUNT} # Use a dedicated service account
    # Add --min-instances / --max-instances for scaling control if needed

# If deploying separate agent services, repeat 'gcloud run deploy' for each agent's image,
# potentially adjusting SERVICE_NAME, IMAGE_URI, memory/cpu, and removing --allow-unauthenticated if they don't need direct ingress.
# Ensure all services use the same REDIS_URL and VPC connector.
```

## Architecture Overview

The typical GCP deployment architecture involves:

1.  **Cloud Run Service(s):** One or more services host your containerized ADK application. This might be a single service for everything or separate services for the web UI/API and background agent processes.
2.  **Memorystore for Redis:** Provides a managed Redis instance for session state, enabling coordination between potentially scaled-out Cloud Run instances or separate agent services.
3.  **Artifact Registry:** Stores your built Docker container images.
4.  **Secret Manager:** Securely stores sensitive configuration like API keys.
5.  **VPC Network / VPC Access Connector:** Allows Cloud Run services (which run in a Google-managed environment) to securely connect to resources in your VPC network, like the Memorystore Redis instance.
6.  **(Optional) Cloud Build:** Automates the process of building container images from your source code.
7.  **Execution Environment:** Cloud Run services run in a specific execution environment (Gen1 or Gen2). Gen2 is the default for most new services and offers features like a standard Linux environment and broader network compatibility. The generated assets assume the default environment. See: https://cloud.google.com/run/docs/about-execution-environments

## Environment Variables (Summary)

Key environment variables for Cloud Run deployment:

*   `REDIS_URL`: Connection string for Memorystore (`redis://<ip>:6379`). **Required by ADK.**
*   `ADK_SESSION_SERVICE`: Must be set to `redis` to tell ADK to use Redis. **Required by ADK.**
*   `GOOGLE_API_KEY`: API key for your language model, injected via Secret Manager. **Required by your agent logic.**
*   `RACK_ENV`: Set to `production` for optimal performance/settings in Ruby web frameworks. Recommended.
*   `ADK_LOG_LEVEL`: Controls ADK log verbosity (`INFO`, `DEBUG`, etc.).
*   `PORT`: Provided by Cloud Run (default 8080), telling your app which port to listen on. ADK's web server should respect this.
*   *Agent-Specific Variables*: Any other config your agent needs.

## Multi-Container Considerations

If your application involves long-running background tasks or specific agents that should scale independently from the main web interface, consider deploying them as separate Cloud Run services:

1.  **Main ADK Service:** Handles web requests, API calls. Uses the `Dockerfile` with the web server entrypoint.
2.  **Agent Service(s):** Each runs a specific agent process. Uses a dedicated `Dockerfile.agent-<name>` with that agent's entrypoint script.
3.  **Shared Redis:** All services connect to the *same* Memorystore instance using the `REDIS_URL` for state sharing and coordination.
4.  **Networking:** All services need access to the VPC connector to reach Redis. Agent services might not need `--allow-unauthenticated` if they don't require direct external access.

This allows agents to run continuously and scale independently.

## Health Checks

To ensure Cloud Run can effectively manage your service instances, configure health checks:

*   **Liveness Probe:** Checks if your container is responsive. If it fails repeatedly, Cloud Run restarts the container.
*   **Startup Probe:** Checks if your container has finished starting up. If configured, liveness probes only start after the startup probe succeeds.

**Implementation:**

1.  **Expose an Endpoint:** If your ADK application runs a web server (e.g., via the `--entrypoint`), expose a simple HTTP endpoint (e.g., `/healthz`) that returns a `200 OK` status when the application is healthy and ready.
2.  **Configure Probes:** Use flags during deployment:
    ```bash
    gcloud run deploy ${SERVICE_NAME} \
      ...
      # Check every 15s after initial 10s delay, fail after 3 consecutive failures
      --probe-liveness=http://localhost:8080/healthz?path=/healthz,initial-delay-seconds=10,period-seconds=15,failure-threshold=3 \
      # Check startup using the same endpoint, fail faster
      --probe-startup=http://localhost:8080/healthz?path=/healthz,initial-delay-seconds=5,period-seconds=5,failure-threshold=3 \
      # Give more CPU during startup if needed
      --startup-cpu-boost \
      ...
    ```
    Adjust the path (`/healthz`), port (`8080`), and timing parameters as needed.

*   **Background Agents:** Services that only run background tasks (no web server) might not need HTTP health checks. Cloud Run considers them started once the container process begins.

See: https://cloud.google.com/run/docs/configuring/healthchecks

## Scaling

*   **Cloud Run:** Automatically scales based on incoming requests (up to `--max-instances`). You can set `--min-instances` > 0 to keep instances warm and reduce cold starts, at a higher cost. Monitor CPU/memory usage and adjust limits (`--cpu`, `--memory`) accordingly.
*   **Memorystore:** Monitor Redis CPU and memory usage in the GCP console. If it becomes a bottleneck, you can increase the instance size (requires instance recreation for some tiers/changes). Choose the appropriate tier (Basic vs. Standard HA) based on availability needs.

## Troubleshooting

*   **Connection Issues (Redis):**
    *   Verify `REDIS_URL` environment variable is correct in Cloud Run.
    *   Confirm the Cloud Run service has the VPC Connector configured (`gcloud run services describe $SERVICE_NAME --region $REGION --format='value(spec.template.spec.containers[0].env[?(@.name=="REDIS_URL")].value)'` and check `spec.template.metadata.annotations."run.googleapis.com/vpc-access-connector"`).
    *   Ensure the VPC Connector is healthy and firewall rules aren't blocking port 6379 between the connector's IP range and the Redis instance.
*   **Container Crashes / Errors:**
    *   Check Cloud Run logs: `gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE_NAME}" --project=${PROJECT_ID} --limit=100 --order=desc`
    *   Look for application errors, out-of-memory issues, or startup failures (including health check failures).
    *   Test the container locally (`docker run ...`) if possible.
*   **Secret / API Key Issues:**
    *   Verify the secret exists in Secret Manager (`gcloud secrets describe ${SECRET_NAME}`).
    *   Confirm the secret is correctly mounted in Cloud Run (`gcloud run services describe $SERVICE_NAME --region $REGION --format='value(spec.template.spec.containers[0].env[?(@.name=="GOOGLE_API_KEY")].valueFrom.secretKeyRef)'`).
    *   Ensure the Cloud Run service account (either default or dedicated) has the `roles/secretmanager.secretAccessor` IAM role for the specific secret or on the project level.

## Conclusion

Deploying an ADK Ruby agent to Cloud Run involves containerizing the application, setting up necessary backing services like Redis via Memorystore and Secret Manager, and configuring the Cloud Run service(s) correctly. While a future `adk generate deployment --cloud gcp` command could simplify asset creation, the steps outlined above provide a comprehensive path to get your agent running scalably on GCP. Remember security best practices like using dedicated service accounts and managing secrets properly. 