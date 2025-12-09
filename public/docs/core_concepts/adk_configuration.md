# ADK Configuration

This document explains how to configure the global settings for the ADK framework using the `ADK.configure` block.

## 1. Overview

Many aspects of the ADK's behavior, such as logging, session management, webhook settings, and default Redis connections, can be customized globally. This is typically done once during your application's initialization phase (e.g., in `config/initializers/adk.rb` for Rails/Sinatra, or near the start of a standalone script).

The configuration is managed through a singleton `ADK::Configuration` object, accessed via `ADK.configure` or `ADK.config`.

## 2. Using `ADK.configure`

The primary way to set configuration is using the `ADK.configure` block:

```ruby
# config/initializers/adk.rb or similar
require 'adk'

ADK.configure do |config|
  # Set the log level (DEBUG, INFO, WARN, ERROR, FATAL)
  # See also ADK_LOG_LEVEL environment variable
  config.log_level = :info 

  # Configure the session service (see adk_session_service)
  # config.session_service = ADK::SessionService::InMemory.new
  config.session_service = ADK::SessionService::Redis.new(
    # Optional: Provide custom Redis options hash or client instance
    # redis: Redis.new(url: ENV.fetch('ADK_REDIS_SESSION_URL', 'redis://localhost:6379/1'))
  )

  # Configure default Redis connection options (used by RedisSessionService
  # and RedisDefinitionStore if no specific client is passed to them).
  # See also REDIS_URL environment variable.
  config.redis_options = { 
    url: ENV.fetch('ADK_REDIS_DEFAULT_URL', 'redis://localhost:6379/0') 
    # Add other Redis options like: password:, timeout:, etc.
  }

  # Configure Webhook settings (see webhooks)
  config.webhooks.listener_enabled = true
  config.webhooks.listen_address = "0.0.0.0"
  config.webhooks.listen_port = 9293
  config.webhooks.base_path = "/adk-hooks"
  config.webhooks.enable_dynamic_agent_handler = true
  # Register custom webhook validators...
  # config.webhooks.register_validator(:my_validator) { |req, secret| ... }

  # Configure other settings as they become available...
end
```

*   The `ADK.configure` method yields the singleton `ADK::Configuration` instance.
*   You modify the attributes of this `config` object within the block.
*   This block should typically run only once during application startup.

## 3. Accessing Configuration (`ADK.config`)

After the initial configuration, you can access the current settings using `ADK.config`:

```ruby
# Get the configured session service later in your code
service = ADK.config.session_service

# Get the webhook base path
base_path = ADK.config.webhooks.base_path

# Get Redis options
redis_opts = ADK.config.redis_options 
# Note: ADK.redis_options is a shortcut for ADK.config.redis_options
```

## 4. Key Configuration Areas

### 4.1. Logging (`config.log_level`)

*   Sets the minimum severity level for messages logged by `ADK.logger`.
*   Accepts symbols: `:debug`, `:info`, `:warn`, `:error`, `:fatal`.
*   Can also be controlled via the `ADK_LOG_LEVEL` environment variable (which takes precedence if set during initial logger creation).
*   See `adk.rb` for the eager initialization logic of the logger.

### 4.2. Session Service (`config.session_service`)

*   Assign an instance of a session service implementation (e.g., `ADK::SessionService::Redis.new` or `ADK::SessionService::InMemory.new`).
*   This instance will be used by default when agents need to interact with sessions, unless a different service is explicitly passed.
*   See `public/docs/adk_session_service.md` for details.

### 4.3. Default Redis Connection (`config.redis_options`)

*   A hash containing options passed to `Redis.new` when ADK needs a default Redis client.
*   Used by `ADK::SessionService::Redis` and `ADK::DefinitionStore::RedisStore` *if they are not initialized with their own specific Redis client instance*.
*   Also used to configure the Sidekiq client connection.
*   The `:url` key is commonly used and can be set via the `REDIS_URL` environment variable (which is often the default).
*   Other standard `Redis.new` options can be included (e.g., `:password`, `:timeout`, `:ssl_params`).
*   Can also be accessed via the `ADK.redis_options` shortcut.

### 4.4. Webhooks (`config.webhooks`)

*   Accessed via `config.webhooks`, which returns an `ADK::Configuration::Webhooks` instance.
*   Controls the built-in webhook listener and dynamic agent triggering.
*   Settings include `listener_enabled`, `listen_address`, `listen_port`, `base_path`, `enable_dynamic_agent_handler`, etc.
*   Also provides methods to `register_validator` for webhook security.
*   See `public/docs/webhooks.md` and `public/docs/configuring_agent_webhooks.md` for details.

### 4.5 Background Jobs / Sidekiq

The ADK uses Sidekiq for background job processing, notably for:

*   Executing asynchronous tools (`ADK::Tools::BaseAsyncJobTool`).
*   Processing inbound webhooks via `ADK::WebhookJobWorker`.

Sidekiq configuration (specifically the Redis connection used by Sidekiq clients and servers) is automatically linked to the `ADK.config.redis_options`:

*   When `ADK.configure` is run, or when `ADK.config.redis_options` is modified, ADK attempts to reconfigure the `Sidekiq.configure_client` block to use the same Redis connection details.
*   This ensures that when your application (e.g., the web server) enqueues a job, it uses the same Redis as your Sidekiq worker processes.
*   **Important:** You still need to run separate Sidekiq worker processes in production, ensuring they load your application environment (including the ADK configuration) and listen to the relevant queues (e.g., `default`, `adk_webhooks`).

```bash
# Example: Starting a Sidekiq worker for ADK
# Ensure your environment (Gemfile, ADK config) is loaded
bundle exec sidekiq -q default -q adk_webhooks 
```

There are currently no direct `config.sidekiq` options within `ADK.configure`, as the primary link is through the shared Redis configuration.

## 5. Environment Variables

Several configuration options can also be influenced by environment variables, which are often loaded via `.env` files using the `dotenv` gem (loaded by `ADK.load_environment`). Environment variables typically take precedence during initial setup:

*   `ADK_LOG_LEVEL`: Sets the initial log level (`DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`, `NONE`, `SILENT`).
*   `REDIS_URL`: Often used as the default for `ADK.config.redis_options[:url]`.
*   Other environment variables might be used internally by specific components or within your application's ADK configuration block (e.g., `ENV['NOTIFICATION_API_URL']` in custom tool examples).

It's common practice to use environment variables for settings that differ between development, testing, and production environments (like Redis URLs, API keys, etc.).

## Further Reading

*   [`adk_architecture_overview`](./adk_architecture_overview)
*   [`adk_session_service`](./adk_session_service)
*   [`webhooks`](../guides/webhooks)
