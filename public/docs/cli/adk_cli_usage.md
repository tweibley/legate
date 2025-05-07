# ADK Command-Line Interface (CLI)

This document describes the `adk` command-line interface, a tool provided for managing ADK agents, definitions, and running related processes.

## 1. Installation & Setup

The `adk` CLI is typically made available when you install the `adk-ruby` gem or include it in your project's Gemfile and run `bundle install`.

Ensure your environment is set up correctly (e.g., Ruby version, Bundler, necessary environment variables like `REDIS_URL` if using Redis-based features).

## 2. Basic Usage

You invoke the CLI using the `adk` command, followed by a subcommand and its specific options.

```bash
adk <subcommand> [options]
```

Use `adk help` or `adk <subcommand> --help` to see available commands and their options.

## 3. Core Commands

### 3.1. Agent Management (`adk agent`)

This subcommand group deals with managing agent definitions stored in the configured `DefinitionStore` (usually Redis).

*   **`adk agent create <agent_name> [options]`**: Creates a new agent definition.
    *   **Required Argument:**
        *   `<agent_name>`: The unique name for the new agent.
    *   **Common Options:**
        *   `--description "Agent description"`: Set the agent's description.
        *   `--instruction "Agent instructions..."`: Set the core instructions/system prompt.
        *   `--tools tool1,tool2,tool3`: Comma-separated list of tool names (must be registered globally) to associate with the agent.
        *   `--model "model-name"`: Specify the LLM to use (e.g., `gemini-1.5-pro-latest`).
        *   `--webhook-enabled`: Flag to enable this agent for inbound webhooks.
        *   `--webhook-secret "your-secret"`: Set the secret for webhook validation.
        *   `--mcp-server-json '[{"type":"stdio", ...}]'`: JSON string defining MCP servers to connect to.
    *   **Example:**
        ```bash
        adk agent create my_calculator --description "A simple calculator agent" --instruction "Use the calculator tool." --tools calculator --model gemini-pro
        ```

*   **`adk agent list`**: Lists all agent definitions found in the store.
    *   **Example Output:**
        ```
        Available Agent Definitions:
        - my_calculator: A simple calculator agent (Model: gemini-pro)
        - another_agent: Does other things (Model: gpt-4o)
        ```

*   **`adk agent show <agent_name>`**: Displays the detailed definition of a specific agent.
    *   **Example:** `adk agent show my_calculator`

*   **`adk agent update <agent_name> [options]`**: Updates specific fields of an existing agent definition. Uses the same options as `create` (e.g., `--description`, `--instruction`, `--tools`, `--model`). Only provided fields are updated.
    *   **Example:** `adk agent update my_calculator --description "An improved calculator agent" --model gemini-1.5-pro-latest`

*   **`adk agent delete <agent_name>`**: Deletes an agent definition from the store. Prompts for confirmation.
    *   **Example:** `adk agent delete my_calculator`

### 3.2. Web Server (`adk web`)

This subcommand group manages the built-in development web server, which includes the Web UI and potentially the Webhook Listener.

*   **`adk web start [options]`**: Starts the ADK development web server (using Puma by default).
    *   **Common Options:**
        *   `-p <port>`: Specify the port number (default: defined by Puma/Rack, often 9292).
        *   `-o <address>`: Specify the address to bind to (default: `localhost`). Use `0.0.0.0` to listen on all interfaces.
        *   `-e <environment>`: Set the Rack environment (`development`, `production`, `test`).
    *   **Webhook Listener:** If `ADK.configure { |c| c.webhooks.listener_enabled = true }` is set in your configuration, this command will *also* typically start the webhook listener application, either mounted within the main web app or alongside it, according to the ADK's internal setup.
    *   **Example:** `adk web start -p 3000 -o 0.0.0.0`

*   **`adk web routes`**: (If implemented) Lists the available routes for the main Web UI application.

### 3.3. Tool Management (`adk tool`)

*   **`adk tool list`**: Lists all tools currently registered in the `ADK::GlobalToolManager`. Useful for seeing which tools are available to be added to agent definitions.
    *   **Example Output:**
        ```
        Globally Registered Tools:
        - calculator: Performs basic arithmetic operations.
        - echo_tool: Echoes back the input message.
        - webhook_tool: Sends an outbound HTTP POST request (webhook).
        - ... (other built-in and custom tools)
        ```

### 3.4. Session Management (`adk session`)

*   **`adk session show <session_id>`**: Retrieves and displays the details and event history of a specific session from the configured `SessionService` (primarily useful with `RedisSessionService`).
*   **`adk session list [options]`**: (If implemented) Lists recent or active sessions.
*   **`adk session delete <session_id>`**: Deletes a specific session.

### 3.5. Sidekiq (`adk sidekiq`)

Manages Sidekiq workers and jobs.

*   `adk sidekiq start [options]`: Starts Sidekiq workers.
    *   Requires a Sidekiq configuration file (e.g., `config/sidekiq.yml`).
    *   Options:
        *   `--config <path>`: Path to Sidekiq configuration file.
        *   `--environment <env>`: Rails environment.
        *   `--logfile <path>`: Path to logfile.
        *   `--pidfile <path>`: Path to PID file.
        *   `--daemon`: Daemonize process.
*   `adk sidekiq stop [options]`: Stops Sidekiq workers.
*   `adk sidekiq status`: Checks Sidekiq status.

(More subcommands might exist, refer to `adk sidekiq help`)

### 3.6. Deployment (`adk deployment`)

Helps in generating assets for deploying your ADK application.

#### `adk deployment generate [directory]`

Generates deployment assets such as Dockerfiles, `.dockerignore` files, a `config.ru` for Rack applications, and cloud-specific configuration scripts. These assets are placed into a new directory (default name: `deployment`).

**Arguments:**

*   `[directory]` (Optional): The base path where the deployment assets directory will be created. If not specified, it defaults to the current directory (`.`). The actual assets will be placed in a subdirectory named according to the `--name` option.

**Generic Options:**

*   `--cloud <provider>` / `-c <provider>`: **(Required)** Specifies the target cloud provider for which to generate assets.
    *   Allowed values: `gcp`, `aws`, `azure`, `none`.
    *   Default: `none` (generates only generic Docker assets).
*   `--entry-point <path>` / `-e <path>`: The path to your main application entry point script (e.g., `bin/web_server.rb`, `app.rb`, or a `config.ru`). This is required unless `--generate-sample-entrypoint` is used. The generated `config.ru` will reference this script to run your application.
*   `--agent-entry-points <path1,path2,...>` / `-a <path1,path2,...>`: A comma-separated list of paths to entry point scripts for any standalone agent processes you want to deploy. A separate Dockerfile may be generated for each.
*   `--name <name>` / `-n <name>`: The base name for the output directory where assets will be generated (e.g., if `my-app-deploy` is given, assets will be in `./my-app-deploy/`). This name may also be used as a prefix for generated cloud resources.
    *   Default: `deployment`.
*   `--base-image <image_name:tag>`: The base Ruby Docker image to use for the generated Dockerfile(s) (e.g., `ruby:3.3-slim`).
    *   Default: `ruby:3.2-slim`.
*   `--generate-sample-entrypoint`: If set, a sample web entrypoint script (default: `bin/adk_web_entrypoint.rb`) with a basic `/healthz` endpoint and an example `/echo` agent endpoint will be generated. This is useful if your ADK application doesn't have an existing web server entry point.
    *   Default: `false`.

**GCP Specific Options (applicable if `--cloud gcp` is used):**

*   `--gcp-project-id <id>`: **(Required for GCP)** Your Google Cloud Project ID.
*   `--gcp-region <region>`: The GCP region where resources will be deployed (e.g., `us-central1`).
    *   Default: `us-central1`.
*   `--gcp-redis-instance-name <name>`: The name for the GCP Memorystore Redis instance that will be created or used.
    *   Default: `adk-redis`.
*   `--gcp-service-name <name>`: The name for the main GCP Cloud Run service that will host your application.
    *   Default: `adk-agent-service`.
*   `--gcp-memory <size>`: The memory allocation for the main Cloud Run service (e.g., `512Mi`, `1Gi`).
    *   Default: `512Mi`.
*   `--gcp-cpu <count>`: The CPU allocation for the main Cloud Run service.
    *   Default: `1`.

**Example:**

To generate deployment assets for GCP, targeting your project `my-gcp-project-123`, with the main application entry point at `bin/my_app_server.rb`, and outputting to a directory named `my_adk_prod_deployment`:

```bash
bundle exec adk deployment generate . --cloud gcp \
  --gcp-project-id "my-gcp-project-123" \
  --entry-point "bin/my_app_server.rb" \
  --name "my_adk_prod_deployment" \
  --gcp-region "us-east1"
```

This will create a directory `./my_adk_prod_deployment/` containing a `Dockerfile`, `.dockerignore`, `config.ru`, a `deploy-gcp.sh` script, a `cloudbuild.yaml` file, and a `README-GCP-DEPLOYMENT.md` guide.

### 3.7. Help (`adk help`)

*   **`adk help`**: Displays the main help message listing all available subcommands.
*   **`adk help <subcommand>`**: Displays detailed help for a specific subcommand (e.g., `adk help agent`).

## 4. Configuration

The CLI relies on the same ADK configuration mechanisms as the library itself:

*   It loads the application environment (often via `Bundler.setup` and `Dotenv.load`).
*   It respects settings configured in `ADK.configure` blocks within your application's initialization code.
*   It uses environment variables (e.g., `REDIS_URL`, `ADK_LOG_LEVEL`).

Ensure your ADK configuration (especially `ADK.config.redis_options` if using Redis for definitions/sessions) is accessible when running `adk` commands.

## Further Reading

*   [`adk_configuration`](../core_concepts/adk_configuration)
*   [`adk_definition_store`](../core_concepts/adk_definition_store)
*   [`adk_web_ui`](../web_ui/adk_web_ui)
*   [`adk_tools_and_registry`](../tools/adk_tools_and_registry)