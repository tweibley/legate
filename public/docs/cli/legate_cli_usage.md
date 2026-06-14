# Legate Command-Line Interface (CLI)

This document describes the `legate` command-line interface, a tool provided for managing Legate agents, definitions, and running related processes.

## 1. Installation & Setup

The `legate` CLI is typically made available when you install the `legate` gem or include it in your project's Gemfile and run `bundle install`.

Ensure your environment is set up correctly (e.g., Ruby version, Bundler, necessary environment variables like `GOOGLE_API_KEY`).

## 2. Basic Usage

You invoke the CLI using the `legate` command, followed by a subcommand and its specific options.

```bash
legate <subcommand> [options]
```

Use `legate help` or `legate <subcommand> --help` to see available commands and their options.

## 3. Core Commands

### 3.1. Agent Management (`legate agent`)

This subcommand group deals with managing agent definitions stored in the `GlobalDefinitionRegistry` (in-memory).

*   **`legate agent save NAME [options]`**: Creates or updates an agent definition in the store.
    *   **Required Argument:**
        *   `NAME`: The unique name for the agent.
    *   **Required Options:**
        *   `--description "Agent description"`: Set the agent's description.
    *   **Common Options:**
        *   `--instruction "Agent instructions..."`: Set the core instructions/system prompt.
        *   `--tools` / `-t` `tool1,tool2,tool3`: Comma-separated list of tool names (must be registered globally) to associate with the agent.
        *   `--model "model-name"`: Specify the LLM to use (e.g., `gemini-3.5-flash`).
        *   `--webhook-enabled`: Flag to enable this agent for inbound webhooks.
        *   `--webhook-secret "your-secret"`: Set the secret for webhook validation.
        *   `--mcp-servers-json '[{"type":"stdio", ...}]'`: JSON string defining MCP servers to connect to.
    *   **Example:**
        ```bash
        legate agent save my_calculator --description "A simple calculator agent" --instruction "Use the calculator tool." --tools calculator --model gemini-pro
        ```

*   **`legate agent list`**: Lists all agent definitions found in the store.
    *   **Options:**
        *   `--json`: Output result in JSON format.
    *   **Example Output:**
        ```
        Defined Agents:
        - my_calculator: A simple calculator agent (Model: gemini-pro, Tools: calculator)
        ```

*   **`legate agent generate NAME [options]`**: Generates a new agent definition Ruby file from a template.
    *   **Options:**
        *   `--description "Agent description"`: Agent description (default: "A new Legate agent.").
        *   `--instruction "Agent instruction"`: Agent instruction/system prompt (default: "You are a helpful assistant.").
        *   `--tools` / `-t` `tool1,tool2`: Comma-separated list of tool names.
        *   `--model "model-name"`: LLM model name.
        *   `--dir "./agents"`: Directory to save the agent definition file (default: `./agents`).
        *   `--force`: Overwrite existing file without prompting.
        *   `--webhook-enabled`: Include webhook configuration placeholders.
    *   **Example:** `legate agent generate my_calculator --description "A calculator" --tools calculator`

*   **`legate agent delete NAME`**: Deletes an agent definition from the store. Prompts for confirmation.
    *   **Example:** `legate agent delete my_calculator`

*   **`legate agent stop \u003cagent_name\u003e [options]`**: Stops a persistent agent by marking it as 'stopped' in the definition store.
    *   **Options:**
        *   `--force`: Skip confirmation prompt
        *   `--quiet` / `-q`: Suppress status messages, only output result.
        *   `--json`: Output result in JSON format (implies --quiet).
    *   **Notes:**
        *   If the agent is running in a web server, it will stop on the next status check or server restart.
        *   Useful for remotely stopping agents without accessing the web UI.
    *   **Example:** `legate agent stop my_calculator --force`

*   **`legate agent start NAME [options]`**: Verifies agent definition loading and starts the agent runtime (ephemeral diagnostic). Loads the definition, instantiates the agent, starts and stops the runtime, prints details, and exits.
    *   **Options:**
        *   `--quiet` / `-q`: Suppress status messages, only output result.
        *   `--json`: Output result in JSON format (implies --quiet).
    *   **Example:** `legate agent start my_calculator --json`

*   **`legate agent status \u003cagent_name\u003e [options]`**: Checks the current status of an agent.
    *   **Options:**
        *   `--json`: Output result in JSON format.
    *   **Example:** `legate agent status my_calculator --json`
    *   **JSON Output Format:**
        ```json
        {
          "agent": "my_calculator",
          "status": "running",
          "model": "gemini-2.0-flash",
          "tools": ["calculator"]
        }
        ```

*   **`legate agent ai_generate [options]`**: Uses AI (Gemini LLM) to generate production-ready agent definition code from a natural language description.
    *   **Input Options (one required):**
        *   `--description` / `-d`: Inline description
        *   `--prompt-file` / `-f`: Read description from a file
        *   **stdin**: Pipe description via stdin (auto-outputs to stdout)
    *   **Output Options:**
        *   `--output` / `-o`: Custom output file path (default: `./<suggested_name>_agent.rb`)
        *   `--stdout`: Force output to stdout instead of file
        *   `--force`: Overwrite existing file without prompting
    *   **Environment:** Requires `GOOGLE_API_KEY` to be set
    *   **Examples:**
        ```bash
        legate agent ai_generate -d "An agent that helps with customer support"
        legate agent ai_generate -f prompt.txt -o ./agents/support_agent.rb
        echo "A calculator agent" | legate agent ai_generate > calc_agent.rb
        ```

*   **`legate agent export <agent_name> [options]`**: Exports an agent definition to YAML or JSON.
    *   **Options:**
        *   `--format`: Output format, either `yaml` (default) or `json`.
        *   `--output` / `-o`: Output file path. If omitted, prints to stdout.
    *   **Example:** `legate agent export my_calculator --format=json --output=my_calculator.json`

*   **`legate agent execute <agent_name> <task> [options]`**: Executes a single task with an agent and exits.
    *   **Required Arguments:**
        *   `<agent_name>`: Name of the agent to execute.
        *   `<task>`: The task/prompt to execute.
    *   **Options:**
        *   `--session-id=<id>`: Continue an existing session.
        *   `--user-id=<id>`: Associate session with a user ID for tracking and resumption.
        *   `--quiet` / `-q`: Suppress status messages, only output result.
        *   `--json`: Output result in JSON format (implies --quiet).
    *   **Examples:**
        ```bash
        # Normal execution with verbose status
        legate agent execute my_calculator "What is 5 + 3?"
        
        # Quiet mode - only show result
        legate agent execute my_calculator "What is 5 + 3?" --quiet
        
        # JSON output for scripting/automation
        legate agent execute my_calculator "What is 5 + 3?" --json
        ```
    *   **JSON Output Format:**
        ```json
        {
          "session_id": "uuid-here",
          "agent": "my_calculator",
          "result": {
            "role": "agent",
            "content": {"status": "success", "result": "8"},
            "timestamp": "2025-12-16 00:00:00 UTC"
          }
        }
        ```

### 3.2. Web Server (`legate web`)

This subcommand group manages the built-in development web server, which includes the Web UI and potentially the Webhook Listener.

*   **`legate web start [options]`**: Starts the Legate development web server (using Puma by default).
    *   **Options:**
        *   `--port <port>`: Specify the port number (default: `4567`).
        *   `--host <address>`: Specify the address to bind to (default: `localhost`). Use `0.0.0.0` to listen on all interfaces.
        *   `--no-autoload`: Disable auto-loading of custom tools and agents.
    *   **Webhook Listener:** If `Legate.configure { |c| c.webhooks.listener_enabled = true }` is set in your configuration, this command will *also* typically start the webhook listener application, either mounted within the main web app or alongside it, according to the Legate's internal setup.
    *   **Example:** `legate web start --port 3000 --host 0.0.0.0`

### 3.3. Tool Management (`legate tool`)

*   **`legate tool list`**: Lists all tools currently registered in the `Legate::GlobalToolManager`. Useful for seeing which tools are available to be added to agent definitions.
    *   **Options:**
        *   `--json`: Output result in JSON format.
    *   **Example Output:**
        ```
        Available tools:
        - calculator: Performs basic arithmetic operations.
        - echo: Echoes back the input message.
        - webhook: Sends an outbound HTTP POST request (webhook).
        ```

*   **`legate tool info NAME`**: Shows detailed information about a specific tool, including its description and parameter definitions (names, types, required/optional status).
    *   **Example:** `legate tool info calculator`

*   **`legate tool ai_generate [options]`**: Uses AI (Gemini LLM) to generate production-ready tool class code from a natural language description. Automatically determines if the tool should be simple, HTTP API, or async.
    *   **Input Options (one required):**
        *   `--description` / `-d`: Inline description
        *   `--prompt-file` / `-f`: Read description from a file
        *   **stdin**: Pipe description via stdin (auto-outputs to stdout)
    *   **Output Options:**
        *   `--output` / `-o`: Custom output file path (default: `./<suggested_name>.rb`)
        *   `--stdout`: Force output to stdout instead of file
        *   `--force`: Overwrite existing file without prompting
    *   **Environment:** Requires `GOOGLE_API_KEY` to be set
    *   **Examples:**
        ```bash
        legate tool ai_generate -d "A tool that converts temperatures"
        echo "A URL status checker" | legate tool ai_generate > url_checker.rb
        ```

*   **`legate tool execute <tool_name> [param=value ...] [options]`**: Executes a tool directly with parameters.
    *   **Options:**
        *   `--quiet` / `-q`: Suppress status messages, only output result.
        *   `--json`: Output result in JSON format (implies --quiet).
    *   **Example:**
        ```bash
        legate tool execute calculator operand1=5 operand2=3 operation=add --json
        ```

### 3.4. Session Management (`legate session`)

*   **`legate session show <session_id>`**: Retrieves and displays the details and event history of a specific session from the configured `SessionService`.
*   **`legate session list [APP_NAME] [USER_ID]`**: Lists all sessions, optionally filtered by `app_name` and/or `user_id`.
*   **`legate session delete <session_id>`**: Deletes a specific session.

### 3.5. Authentication (`legate auth`)

Manages authentication schemes, credentials, and URL mappings. These commands interact with the same `Legate::Auth::Manager` used by the web UI.

#### Status

*   **`legate auth status`**: Shows an overview of the authentication system.
    *   **Example Output:**
        ```
        Authentication System Status

          Schemes:     6
          Credentials: 2
          Mappings:    1

          Scheme types: api_key, http_bearer, oauth2
          Credential types: api_key, oauth2
        ```

#### Scheme Management (`legate auth schemes`)

*   **`legate auth schemes list`**: Lists all registered authentication schemes.
*   **`legate auth schemes show <name>`**: Shows details for a specific scheme.
*   **`legate auth schemes create <name> --type=<type> [options]`**: Creates a new scheme.
    *   **Required Options:**
        *   `--type`: Scheme type (`api_key`, `http_bearer`, `oauth2`, `oidc`, `service_account`, `google_service_account`)
    *   **Type-specific Options (OAuth2/OIDC):**
        *   `--authorization-url`: OAuth2 authorization endpoint
        *   `--token-url`: OAuth2 token endpoint
        *   `--userinfo-url`: OIDC userinfo endpoint
        *   `--scopes`: Space-separated scopes
        *   `--use-pkce`: Enable PKCE
    *   **Example:**
        ```bash
        legate auth schemes create my_oauth --type=oauth2 \
          --authorization-url="https://auth.example.com/authorize" \
          --token-url="https://auth.example.com/token"
        ```
*   **`legate auth schemes delete <name> [--force]`**: Deletes a scheme.

#### Credential Management (`legate auth credentials`)

*   **`legate auth credentials list`**: Lists all credentials (sensitive values are masked).
*   **`legate auth credentials show <name>`**: Shows credential details with masked values.
*   **`legate auth credentials create <name> --type=<type> [options]`**: Creates a new credential.
    *   **Required Options:**
        *   `--type`: Credential type (`api_key`, `http_bearer`, `oauth2`, `oidc`, `service_account`, `google_service_account`, `basic`)
    *   **Type-specific Options:**
        *   `--api-key`: API key value (or `ENV:VAR_NAME` for environment variable)
        *   `--bearer-token`: Bearer token value
        *   `--client-id`: OAuth2/OIDC client ID
        *   `--client-secret`: OAuth2/OIDC client secret
        *   `--service-account-key`: Service account JSON key
        *   `--service-account-key-file`: Path to service account key file
        *   `--username`, `--password`: Basic auth credentials
    *   **Example:**
        ```bash
        legate auth credentials create my_api_key --type=api_key --api-key="ENV:MY_API_KEY"
        ```
*   **`legate auth credentials delete <name> [--force]`**: Deletes a credential.
*   **`legate auth credentials test <name> [--url=<url>]`**: Tests a credential's validity.

#### URL Mapping (`legate auth mappings`)

*   **`legate auth mappings list`**: Lists all URL-to-auth mappings.
*   **`legate auth mappings create --pattern=<pattern> --scheme=<name> --credential=<name> [--regex]`**: Creates a mapping.
    *   **Required Options:**
        *   `--pattern`: URL pattern to match
        *   `--scheme`: Name of the scheme to use
        *   `--credential`: Name of the credential to use
    *   **Optional:**
        *   `--regex`: Treat pattern as a regular expression
    *   **Example:**
        ```bash
        legate auth mappings create \
          --pattern="https://api.example.com/*" \
          --scheme=api_key \
          --credential=my_api_key
        ```
*   **`legate auth mappings delete <index>`**: Deletes a mapping by its index.

### 3.6. Deployment (`legate deployment`)

Helps in generating assets for deploying your Legate application.

#### `legate deployment generate [directory]`

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
*   `--generate-sample-entrypoint`: If set, a sample web entrypoint script (default: `bin/legate_web_entrypoint.rb`) with a basic `/healthz` endpoint and an example `/echo` agent endpoint will be generated. This is useful if your Legate application doesn't have an existing web server entry point.
    *   Default: `false`.

**GCP Specific Options (applicable if `--cloud gcp` is used):**

*   `--gcp-project-id <id>`: **(Required for GCP)** Your Google Cloud Project ID.
*   `--gcp-region <region>`: The GCP region where resources will be deployed (e.g., `us-central1`).
    *   Default: `us-central1`.
*   `--gcp-service-name <name>`: The name for the main GCP Cloud Run service that will host your application.
    *   Default: `legate-agent-service`.
*   `--gcp-memory <size>`: The memory allocation for the main Cloud Run service (e.g., `512Mi`, `1Gi`).
    *   Default: `512Mi`.
*   `--gcp-cpu <count>`: The CPU allocation for the main Cloud Run service.
    *   Default: `1`.

**Example:**

To generate deployment assets for GCP, targeting your project `my-gcp-project-123`, with the main application entry point at `bin/my_app_server.rb`, and outputting to a directory named `my_legate_prod_deployment`:

```bash
bundle exec legate deployment generate . --cloud gcp \
  --gcp-project-id "my-gcp-project-123" \
  --entry-point "bin/my_app_server.rb" \
  --name "my_legate_prod_deployment" \
  --gcp-region "us-east1"
```

This will create a directory `./my_legate_prod_deployment/` containing a `Dockerfile`, `.dockerignore`, `config.ru`, a `deploy-gcp.sh` script, a `cloudbuild.yaml` file, and a `README-GCP-DEPLOYMENT.md` guide.

### 3.7. Help (`legate help`)

*   **`legate help`**: Displays the main help message listing all available subcommands.
*   **`legate help <subcommand>`**: Displays detailed help for a specific subcommand (e.g., `legate help agent`).

## 4. Configuration

The CLI relies on the same Legate configuration mechanisms as the library itself:

*   It loads the application environment (often via `Bundler.setup` and `Dotenv.load`).
*   It respects settings configured in `Legate.configure` blocks within your application's initialization code.
*   It uses environment variables (e.g., `GOOGLE_API_KEY`, `LEGATE_LOG_LEVEL`).

## Further Reading

*   [`legate_configuration`](../core_concepts/legate_configuration)
*   [`legate_definition_store`](../core_concepts/legate_definition_store)
*   [`legate_web_ui`](../web_ui/legate_web_ui)
*   [`legate_tools_and_registry`](../tools/legate_tools_and_registry)