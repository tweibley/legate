# Deploying ADK to Google Cloud Platform

This guide will help you deploy your ADK application to Google Cloud Platform (GCP) using Cloud Run and Redis MemoryStore.

## Prerequisites

1. [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) installed and configured
2. A Google Cloud Platform account with billing enabled
3. Your ADK application code ready for deployment
4. Model provider API key (e.g., Claude, GPT-4)

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
gcloud redis instances create adk-redis \
  --size=1 \
  --region=us-central1 \
  --redis-version=redis_6_x
```

Note the IP address of your Redis instance:

```bash
gcloud redis instances describe adk-redis --region=us-central1 --format="get(host)"
```

### 3.2 Create Secret for API Key

```bash
echo -n "your-api-key" | gcloud secrets create model-api-keys --data-file=-
```

### 3.3 Build and Push Docker Image

```bash
gcloud builds submit --tag gcr.io/your-project-id/adk-agent-service .
```

### 3.4 Deploy to Cloud Run

```bash
gcloud run deploy adk-agent-service \
  --image gcr.io/your-project-id/adk-agent-service \
  --platform managed \
  --region us-central1 \
  --memory 2Gi \
  --cpu 1 \
  --set-env-vars="REDIS_URL=redis://REDIS_IP:6379,ADK_SESSION_SERVICE=redis" \
  --set-secrets="MODEL_PROVIDER_API_KEY=model-api-keys:latest" \
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
- `MODEL_PROVIDER_API_KEY`: API key for your chosen model provider
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