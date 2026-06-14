# Legate Configuration

This document explains how to configure the global settings for the Legate framework using the `Legate.configure` block.

## 1. Overview

Many aspects of the Legate's behavior, such as logging, session management, and webhook settings, can be customized globally. This is typically done once during your application's initialization phase (e.g., in `config/initializers/legate.rb` for Rails/Sinatra, or near the start of a standalone script).

The configuration is managed through a singleton `Legate::Configuration` object, accessed via `Legate.configure` or `Legate.config`.

## 2. Using `Legate.configure`

The primary way to set configuration is using the `Legate.configure` block:

```ruby
# config/initializers/legate.rb or similar
require 'legate'

Legate.configure do |config|
  # Note: log level is NOT configured here. It is controlled exclusively by
  # the LEGATE_LOG_LEVEL environment variable (see section 4.1 / 5).

  # Configure the session service (see legate_session_service)
  # Sessions are always in-memory
  config.session_service = Legate::SessionService::InMemory.new

  # Configure Webhook settings (see webhooks)
  config.webhooks.listener_enabled = true
  config.webhooks.listen_address = "0.0.0.0"
  config.webhooks.listen_port = 9293
  config.webhooks.base_path = "/legate-hooks"
  config.webhooks.enable_dynamic_agent_handler = true
  # Register custom webhook validators...
  # config.webhooks.register_validator(:my_validator) { |req, secret| ... }

  # Configure other settings as they become available...
end
```

*   The `Legate.configure` method yields the singleton `Legate::Configuration` instance.
*   You modify the attributes of this `config` object within the block.
*   This block should typically run only once during application startup.

## 3. Accessing Configuration (`Legate.config`)

After the initial configuration, you can access the current settings using `Legate.config`:

```ruby
# Get the configured session service later in your code
service = Legate.config.session_service

# Get the webhook base path
base_path = Legate.config.webhooks.base_path
```

## 4. Key Configuration Areas

### 4.1. Logging (`LEGATE_LOG_LEVEL`)

*   The log level is **not** a `Legate::Configuration` attribute and cannot be set inside the `Legate.configure` block. Assigning `config.log_level` raises `NoMethodError`.
*   The minimum severity level for messages logged by `Legate.logger` is controlled **only** by the `LEGATE_LOG_LEVEL` environment variable (falling back to a default derived from `RACK_ENV` when unset).
*   Accepts: `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`, `NONE`, `SILENT`.
*   See `legate.rb` for the eager initialization logic of the logger.

### 4.2. Session Service (`config.session_service`)

*   Assign an instance of a session service implementation (`Legate::SessionService::InMemory.new`).
*   This instance will be used by default when agents need to interact with sessions, unless a different service is explicitly passed.
*   See `public/docs/core_concepts/legate_session_service.md` for details.

### 4.3. Webhooks (`config.webhooks`)

*   Accessed via `config.webhooks`, which returns an `Legate::Configuration::Webhooks` instance.
*   Controls the built-in webhook listener and dynamic agent triggering.
*   Settings include `listener_enabled`, `listen_address`, `listen_port`, `base_path`, `enable_dynamic_agent_handler`, etc.
*   Also provides methods to `register_validator` for webhook security.
*   See `public/docs/guides/webhooks.md` and `public/docs/guides/configuring_agent_webhooks.md` for details.

### 4.4. Runtime Tool Loading (`config.allow_runtime_tool_load`)

Controls whether the Web UI's AI **tool** builder may load a generated custom tool
into the **running** process ("Add Tool to Legion"). Because this executes
LLM-generated Ruby in-process, it is gated:

*   **Default:** ON outside production, OFF in production
    (`ENV['RACK_ENV'] != 'production'`).
*   Override explicitly:
    ```ruby
    Legate.configure { |config| config.allow_runtime_tool_load = false }
    ```
*   When enabled, installing a tool also writes `tools/<name>.rb` (durable and
    auditable; re-loaded on next boot). When disabled, the builder offers Download
    only — place the file in `tools/` and restart to activate it.
*   **Security:** the generated source is re-validated server-side
    (`CodeValidator`, a *denylist* — not a sandbox), the UI requires an explicit
    per-tool confirmation, and the web UI sits behind Basic Auth. Ruby has no true
    in-process sandbox, so only enable this where you trust the operators. See
    [AI-Powered Code Generators](../guides/ai_code_generators).

## 5. Environment Variables

Several configuration options can also be influenced by environment variables, which are often loaded via `.env` files using the `dotenv` gem (loaded by `Legate.load_environment`). Environment variables typically take precedence during initial setup:

*   `LEGATE_LOG_LEVEL`: Sets the initial log level (`DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`, `NONE`, `SILENT`).
*   `GOOGLE_API_KEY`: The API key for Gemini LLM integration.
*   `RACK_ENV`: `development` / `production`. Among other things it sets the default
    of `allow_runtime_tool_load` (OFF in production) and enables secure session cookies.
*   Other environment variables might be used internally by specific components or within your application's Legate configuration block (e.g., `ENV['NOTIFICATION_API_URL']` in custom tool examples).

It's common practice to use environment variables for settings that differ between development, testing, and production environments (like API keys, etc.).

## Further Reading

*   [`legate_architecture_overview`](./legate_architecture_overview)
*   [`legate_session_service`](./legate_session_service)
*   [`webhooks`](../guides/webhooks)
