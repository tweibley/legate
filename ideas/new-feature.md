
#Here's a detailed PRD and the proposed code changes to add support for long-running tools using Temporal.

**Assumptions:**

1.  We will leverage the `temporalio` gem as suggested.
2.  Users of this feature will need a running Temporal Server instance (e.g., local dev server via `temporal server start-dev` or Temporal Cloud).
3.  Users will need to run a separate Temporal Worker process that registers and executes the specific Temporal Workflows/Activities associated with their custom long-running ADK tools. The ADK library itself won't run the Temporal worker directly; it will only provide the client interface and the tool abstractions.
4.  The initial approach focuses on an explicit "start" tool and a separate "check status/get result" tool pattern, requiring the planner/agent to manage the polling flow.

---

## PRD: Long-Running Tool Support via Temporal

**Version:** 1.0
**Date:** 2025-04-17
**Status:** Draft

**1. Introduction**

*   **1.1. Goals:**
    *   Enable `adk-ruby` developers to create tools that initiate potentially long-running, asynchronous tasks (e.g., complex computations, batch jobs, tasks requiring human interaction/approval) without blocking the main agent execution flow.
    *   Provide a mechanism for the agent to check the status and retrieve the final result of these asynchronous tasks.
    *   Leverage the `temporalio` Ruby SDK and the Temporal platform for robust, scalable, and durable execution of these tasks.
*   **1.2. Problem Statement:**
    *   Standard `ADK::Tool` execution is synchronous within the agent's `run_task` loop. A tool performing a long operation (minutes, hours) would block the agent entirely, making it unresponsive.
    *   There is no built-in way for a tool to yield intermediate progress updates or signal completion asynchronously back to the agent.
*   **1.3. Proposed Solution:**
    *   Introduce a pattern where initiating a long-running task via a specialized ADK tool starts a Temporal Workflow and immediately returns a "pending" status with a unique Workflow ID.
    *   Provide a separate, built-in ADK tool (`CheckWorkflowStatusTool`) that agents can use to query the status and retrieve the result (or error) of a Temporal Workflow using its ID.
    *   Developers implementing long-running tools will define both an `ADK::LongRunningTool` subclass (to start the Temporal Workflow) and the corresponding Temporal Workflow/Activity logic (to be run by a separate Temporal Worker process).
*   **1.4. Scope:**
    *   **In Scope:**
        *   Defining a base class (`ADK::Tools::BaseLongRunningTool`) for initiating Temporal Workflows.
        *   Implementing a built-in tool (`ADK::Tools::CheckWorkflowStatusTool`) for polling Temporal Workflow status/results.
        *   Configuration mechanism for the Temporal client within `adk-ruby`.
        *   Passing necessary context (like `session_id`) from ADK Tool execution to the initiated Temporal Workflow.
        *   Updating CLI and Web UI to handle `:pending` status from tools.
        *   Documentation and examples for setting up and using this feature.
    *   **Out of Scope (for V1):**
        *   Automatic progress updates pushed from Temporal to the ADK Agent (requires callbacks/webhooks or more complex integration).
        *   Embedding a Temporal Worker within the ADK process (users must run workers separately).
        *   Advanced Temporal features (complex scheduling, specific cancellation patterns beyond basic result checking).
        *   Automatic plan generation by the ADK planner for the start-and-poll pattern (the LLM must be instructed to use both tools).

**2. User Stories**

*   **As a Developer (implementing a long-running tool):**
    *   I want to inherit from a specific base class (`BaseLongRunningTool`) to create a tool that starts a long task.
    *   I want to define the Temporal Workflow and Activities that perform the actual long-running logic separately.
    *   I want to easily start the corresponding Temporal Workflow from my tool's execution logic, passing relevant input arguments (including ADK context like `session_id`).
    *   I want my tool to return a unique ID (Temporal Workflow ID) immediately so the agent knows the task has started.
*   **As a Developer (using ADK):**
    *   I want to configure `adk-ruby` with the connection details for my Temporal Server.
    *   I want to register my custom `LongRunningTool` subclasses with an `ADK::Agent`.
    *   I want the agent's planner (when appropriately prompted) to be able to use the `LongRunningTool` to start a task and the built-in `CheckWorkflowStatusTool` to later query its result using the returned Workflow ID.
    *   I want the CLI and Web UI execution flows to clearly indicate when a task is `:pending` and provide the Workflow ID.

**3. Functional Requirements**

*   **FR1: Temporal Client Configuration:**
    *   Allow global configuration of a `Temporalio::Client` instance for `adk-ruby`.
    *   This could be via an `ADK.configure` block or environment variables (`TEMPORAL_ADDRESS`, `TEMPORAL_NAMESPACE`, TLS options, etc.).
    *   Provide a way to access this configured client (e.g., `ADK.temporal_client`).
*   **FR2: `ADK::Tools::BaseLongRunningTool`:**
    *   Define an abstract base class `lib/adk/tools/base_long_running_tool.rb` inheriting `ADK::Tool`.
    *   Require subclasses to implement:
        *   `temporal_workflow_class`: Returns the class of the Temporal Workflow to start.
        *   `prepare_workflow_input(params, context)`: Takes ADK tool `params` and the new `context` object (see FR4) and returns the arguments hash for the Temporal Workflow's `execute` method.
    *   Override `perform_execution(params, context)`:
        *   Access the global `ADK.temporal_client`.
        *   Call subclass's `prepare_workflow_input`.
        *   Generate a unique Temporal Workflow ID (or allow configuration).
        *   Use the client to call `start_workflow` with the `temporal_workflow_class`, input args, workflow ID, and appropriate Temporal options (task queue, timeouts, etc. - may need configuration hooks).
        *   Return `{ status: :pending, workflow_id: <the_workflow_id> }`.
        *   Handle `Temporalio::Error` exceptions during `start_workflow` and return an ADK error hash.
*   **FR3: `ADK::Tools::CheckWorkflowStatusTool`:**
    *   Define a new built-in tool class `lib/adk/tools/check_workflow_status_tool.rb`.
    *   Register it with the name `:check_workflow_status`.
    *   Metadata: Description "Checks the status and retrieves the result of a previously started long-running task (Temporal Workflow)", Parameters: `workflow_id: { type: :string, required: true }`.
    *   `perform_execution(params, context)`:
        *   Access the global `ADK.temporal_client`.
        *   Get `workflow_id` from `params`.
        *   Use `client.workflow_handle(workflow_id)` to get a handle.
        *   Use `handle.describe` to check status (Running, Completed, Failed, TimedOut, Canceled, Terminated).
        *   If **Running**: Return `{ status: :pending, workflow_id: workflow_id, message: "Task is still running." }`.
        *   If **Completed**:
            *   Call `handle.result(timeout: <short_timeout>)` (e.g., 5 seconds) to get the result.
            *   Return `{ status: :success, result: <workflow_result> }`.
            *   Handle potential `Timeout::Error` during result fetch gracefully (return pending or specific error).
        *   If **Failed/TimedOut/Canceled/Terminated**:
            *   Attempt to get the failure details (might require fetching history or specific error types from Temporal).
            *   Return `{ status: :error, error_message: "Workflow <status>: <details>" }`.
        *   Handle `Temporalio::Error` exceptions during handle operations and return ADK error hashes.
*   **FR4: Tool Context:**
    *   Modify `ADK::Agent#execute_step` to create and pass a `context` object (e.g., `ADK::ToolContext`) to `tool.perform_execution`.
    *   This `context` object should provide read-only access to relevant session information like `session_id`, `user_id`, `app_name`.
    *   `BaseLongRunningTool` subclasses will use this context in `prepare_workflow_input`.
*   **FR5: CLI Handling:**
    *   Modify `ADK::CLI::AgentCommands#format_cli_result` and `ToolCommands#execute` result handling.
    *   When encountering `{ status: :pending, workflow_id: ... }`, display a clear "Pending" status message including the Workflow ID.
*   **FR6: Web UI Handling:**
    *   Modify `ADK::Web::App` helpers (`format_execution_result_html`) and relevant routes (`/agents/:name/execute`, `/tools/:name/execute`).
    *   When encountering `{ status: :pending, ... }`, display a "Pending" notification (e.g., `is-info` or `is-warning` class) showing the status message and the Workflow ID.

**4. Non-Functional Requirements**

*   **NFR1: Reliability:** Rely on Temporal for task execution reliability and durability. Error handling in the ADK tools must correctly map Temporal states/errors.
*   **NFR2: Scalability:** The Temporal cluster itself scales independently. The ADK client connection should be lightweight. The number of polling checks could impact performance if not managed well by the agent's planning.
*   **NFR3: Usability:** Clear documentation and examples are crucial due to the added complexity of Temporal setup and the two-tool pattern.
*   **NFR4: Configuration:** Easy configuration of the Temporal client is required.

**5. Dependencies & External Factors**

*   **Gem:** `temporalio`
*   **External System:** Running Temporal Server (v1.20+ recommended).
*   **User Setup:** Users *must* implement and run Temporal Workers separately for their specific long-running logic.

**6. Implementation Plan / Codebase Changes (`adk-ruby`)**

*   **(Config)** Add `temporalio` gem to `adk-ruby.gemspec` and `Gemfile`.
*   **(Core)** Modify `lib/adk.rb`:
    *   Add global configuration for `temporal_client`.
    *   Add `require` statements for new tool files.
*   **(Tooling)** Create `lib/adk/tools/base_long_running_tool.rb`.
*   **(Tooling)** Create `lib/adk/tools/check_workflow_status_tool.rb` and register it.
*   **(Context)** Define `lib/adk/tool_context.rb` (simple Struct or class).
*   **(Agent)** Modify `lib/adk/agent.rb`:
    *   Update `execute_step` to instantiate and pass `ADK::ToolContext`.
    *   Update `perform_execution` signature in `ADK::Tool` (and all subclasses) to accept the context (make it optional for backward compatibility if needed initially, but required for new long-running tools).
*   **(CLI)** Modify `lib/adk/cli/agent_commands.rb` and `lib/adk/cli/tool_commands.rb` to handle `:pending` status display.
*   **(Web)** Modify `lib/adk/web/app.rb` helper `format_execution_result_html` and relevant route handlers to display `:pending` status.
*   **(Tests)** Add `spec/adk/tools/base_long_running_tool_spec.rb`.
*   **(Tests)** Add `spec/adk/tools/check_workflow_status_tool_spec.rb`.
*   **(Tests)** Update `spec/adk/agent_spec.rb` to test context passing and `:pending` result handling.
*   **(Docs)** Update `README.md` and add new documentation pages explaining the feature, Temporal setup, and usage patterns.
*   **(Examples)** Add a new example demonstrating a custom `LongRunningTool` and its corresponding Temporal Workflow/Activity.

**7. Open Questions & Future Considerations**

*   How to best manage Temporal Task Queue names? Configurable per tool or globally?
*   Should `BaseLongRunningTool` allow more customization of Temporal `start_workflow` options (timeouts, retry policies)?
*   Could we implement a push-based update mechanism instead of polling (e.g., Temporal Workflow signals an ADK Webhook)? V2 feature.
*   How to handle Temporal Workflow cancellation initiated from the ADK side? V2 feature.

---

## Code Changes

**1. Add `temporalio` Gem**

*   **File:** `adk-ruby.gemspec`
*   **Action:** Add `spec.add_dependency 'temporalio', '~> 0.1'` (adjust version constraint as needed)

```ruby
# File: ./adk-ruby.gemspec
# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'adk-ruby'
  spec.version       = '0.1.0' # <-- Update version if releasing this feature
  spec.authors       = ['Taylor Weibley']
  spec.email         = ['spam@taylorw.com']

  spec.summary       = 'Agent Development Kit for Ruby'
  spec.description   = 'A framework for building and managing AI agents in Ruby'
  spec.homepage      = 'https://github.com/tweibley/adk-ruby'
  spec.license       = 'NODHHLICENSE'
  spec.required_ruby_version = '>= 3.0.0' # Temporal requires 3.2+

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob('{bin,lib,views,public}/**/*') + %w[README.md Gemfile Gemfile.lock] # Ensure views/public are included if needed by web UI directly
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'concurrent-ruby', '~> 1.2'
  spec.add_dependency 'redis', '~> 5.0'
  spec.add_dependency 'thor', '~> 1.2'
  spec.add_dependency 'logger', '~> 1.5'
  spec.add_dependency 'prometheus-client', '~> 2.1'
  spec.add_dependency 'temporalio', '~> 0.1' # <--- ADDED

  # Web UI dependencies
  spec.add_dependency 'sinatra', '~> 3.1'
  spec.add_dependency 'sinatra-contrib', '~> 3.1'
  spec.add_dependency 'puma', '~> 6.4'
  spec.add_dependency 'slim', '~> 5.1'
  spec.add_dependency 'sass-embedded', '~> 1.72'
  spec.add_dependency 'coffee-script', '~> 2.4'
  spec.add_dependency 'gemini-ai','~> 4.2.0'
  spec.add_dependency 'faraday'
  spec.add_dependency 'faraday-net_http'

  # CLI
  spec.add_dependency 'ostruct'
end
```

*   **File:** `Gemfile`
*   **Action:** Ensure `gemspec` line is present. Run `bundle install` after changes.

```ruby
# File: ./Gemfile
source 'https://rubygems.org'

# Specify your gem's dependencies in adk-ruby.gemspec
gemspec

group :development, :test do
  gem 'rspec', '~> 3.12'
  gem 'rake', '~> 13.0'
  gem 'rubocop', '~> 1.50' # <-- Ensure this line is present here
  gem 'yard', '~> 0.9'
  gem 'webmock'
  gem 'temporal-ruby', group: :test # For testing Temporal interactions (optional but recommended)
  # gem "gemini-ai" # Moved to gemspec
end

group :development do
  gem 'pry', '~> 0.14'
  gem 'pry-byebug', '~> 3.10'
  gem 'dotenv', '~> 2.0'
end
```

**2. Configure Temporal Client**

*   **File:** `lib/adk.rb`
*   **Action:** Add configuration accessor for `temporal_client` and require `temporalio`.

```ruby
# File: lib/adk.rb
require 'dotenv/load' if File.exist?('.env') # Load early for ENV vars

# frozen_string_literal: true
require 'logger' # Require logger here
require 'temporalio' # <--- ADDED
require_relative 'adk/version'

# --- Central ADK Logger and Configuration ---
module ADK
  @logger = nil
  @temporal_client = nil
  @temporal_client_options = {
    host: ENV.fetch('TEMPORAL_ADDRESS', 'localhost:7233'),
    namespace: ENV.fetch('TEMPORAL_NAMESPACE', 'default'),
    # Add more options as needed (tls, api_key, identity, etc.)
    # tls: ENV['TEMPORAL_TLS_CERT_PATH'] ? Temporalio::Client::Connection::TLSOptions.new(...) : false,
    # api_key: ENV['TEMPORAL_API_KEY'],
  }

  def self.logger
    # ... (existing logger code) ...
  end

  # Configure ADK settings
  # Example:
  # ADK.configure do |config|
  #   config.temporal_address = "your-cloud.tmprl.cloud:7233"
  #   config.temporal_namespace = "your-namespace"
  #   # config.temporal_tls_options = Temporalio::Client::Connection::TLSOptions.new(...)
  #   # config.temporal_api_key = "..."
  # end
  def self.configure
    yield self
    # Force re-initialization of client if settings change
    @temporal_client = nil
  end

  # Accessors for Temporal config (optional, direct access via @temporal_client_options also works)
  def self.temporal_address=(addr) @temporal_client_options[:host] = addr; @temporal_client = nil; end
  def self.temporal_namespace=(ns) @temporal_client_options[:namespace] = ns; @temporal_client = nil; end
  # Add more accessors for other options if needed

  # Lazily creates and returns the Temporal client instance
  # @return [Temporalio::Client]
  def self.temporal_client
    return @temporal_client if @temporal_client

    begin
      logger.info("Connecting to Temporal: host=#{@temporal_client_options[:host]}, ns=#{@temporal_client_options[:namespace]}")
      @temporal_client = Temporalio::Client.connect(**@temporal_client_options)
      # Perform a simple check
      # Note: Temporal client doesn't have a simple 'ping'. Checking connection involves RPC.
      # We might rely on the first call to fail if connection is bad, or add a check_connection method.
      logger.info("Temporal client configured successfully.")
      @temporal_client
    rescue StandardError => e
      logger.error("Failed to connect to Temporal: #{e.class} - #{e.message}")
      logger.error("Temporal connection options used: #{@temporal_client_options.inspect}")
      # Raise or return nil? Returning nil might mask issues. Raising is safer.
      raise Error, "Failed to establish Temporal client connection: #{e.message}"
    end
  end

  # Resets the temporal client connection
  def self.reset_temporal_client!
    @temporal_client&.close rescue nil # Attempt graceful close if possible
    @temporal_client = nil
  end

end

# --- Require components AFTER logger is configurable ---
require_relative 'adk/errors'
require_relative 'adk/event'
require_relative 'adk/session'
require_relative 'adk/tool_context' # <--- ADDED
require_relative 'adk/tool'
require_relative 'adk/tool_registry'
# --- Load dependencies BEFORE Agent ---
require_relative 'adk/planner'
# --- Load Services ---
require_relative 'adk/session_service/base'
require_relative 'adk/session_service/in_memory'
require_relative 'adk/session_service/redis'
# --- Load Migrations ---
require_relative 'adk/migrations/001_add_state_scoping'
# --- Now load Agent ---
require_relative 'adk/agent'
# --- Load CLI and Tools last ---
require_relative 'adk/cli'

# Tools (Order doesn't strictly matter here, but keep AgentTool first if it uses others)
require_relative 'adk/tools/agent_tool'
require_relative 'adk/tools/echo'
require_relative 'adk/tools/calculator'
require_relative 'adk/tools/cat_facts'
require_relative 'adk/tools/random_number_tool'
require_relative 'adk/tools/base_long_running_tool' # <--- ADDED
require_relative 'adk/tools/check_workflow_status_tool' # <--- ADDED

module ADK
  class Error < StandardError; end
  # Define SessionService module base for namespacing
  module SessionService; end
end
```

**3. Define Tool Context**

*   **File:** `lib/adk/tool_context.rb` (New File)
*   **Action:** Create a simple class or struct to hold context passed to tools.

```ruby
# File: lib/adk/tool_context.rb
# frozen_string_literal: true

module ADK
  # Provides contextual information to ADK::Tool#perform_execution
  # Currently includes session details. Read-only.
  class ToolContext
    attr_reader :session_id, :user_id, :app_name

    # @param session_id [String] The ID of the current session.
    # @param user_id [String] The user ID associated with the session.
    # @param app_name [String] The application/agent name associated with the session.
    def initialize(session_id:, user_id:, app_name:)
      @session_id = session_id
      @user_id = user_id
      @app_name = app_name
      freeze # Make context immutable
    end

    def to_h
      {
        session_id: @session_id,
        user_id: @user_id,
        app_name: @app_name
      }
    end
  end
end
```

**4. Modify `ADK::Tool` Base Class**

*   **File:** `lib/adk/tool.rb`
*   **Action:** Update `execute` and `perform_execution` signatures to accept `context`.

```ruby
# File: lib/adk/tool.rb
# frozen_string_literal: true

require_relative 'tool_registry'
require 'logger'
require_relative 'tool_context' # <-- ADDED require

module ADK
  class Tool
    # --- Class-level attributes ---
    class << self
      attr_reader :tool_name, :description, :parameters_definition

      def define_metadata(name:, description:, parameters: {})
        @tool_name = name.to_sym
        @description = description
        @parameters_definition = parameters
        # --- Trigger registration AFTER metadata is defined ---
        register_tool_class
      end

      # --- Moved Registration Logic Here ---
      def register_tool_class
        return unless @tool_name && @description # Check if metadata was set

        ADK.logger.debug("Attempting to register tool '#{@tool_name}' with class #{self}")
        ADK::ToolRegistry.register(@tool_name, self)
      end
      # --- End Moved Registration Logic ---
    end
    # --- End Class-level ---

    # --- Self-Registration Hook (Now less critical but harmless) ---
    def self.inherited(subclass)
      super # Call parent's inherited if necessary
      # The registration now happens when define_metadata is called in the subclass
      ADK.logger.debug("Tool subclass #{subclass} inherited from ADK::Tool.")
      # Registration now triggered by define_metadata in subclass
    end
    # --- End Hook ---

    # Instance readers
    attr_reader :name, :description, :parameters

    # Initialize - Sets instance vars from class metadata
    def initialize(**_options)
      @name = self.class.tool_name
      @description = self.class.description
      @parameters = self.class.parameters_definition || {}

      unless @name && @description
        raise ArgumentError, "Tool class #{self.class} must define :name and :description using `define_metadata`."
      end

      # --- REMOVED registration call from initialize ---
    end

    # --- Add Class method to handle registration ---
    def self.register_tool_class
      unless @tool_name && @description && defined?(@parameters_definition) # check defined? for parameters
        ADK.logger.error("ToolRegistry: Cannot register #{self}. Metadata not defined via `define_metadata`.")
        return
      end
      # Prevent re-registration if already done
      unless ADK::ToolRegistry.find_class(@tool_name) == self
        ADK::ToolRegistry.register(@tool_name, self)
      end
    end
    # --- End Class method ---

    # Execute the tool
    # @param params [Hash] Input parameters for the tool.
    # @param context [ADK::ToolContext, nil] Contextual information (session details). <-- ADDED
    # @return [Hash] A hash with :status (:success, :error, :pending) and :result/:error_message/:workflow_id.
    def execute(params = {}, context = nil) # <-- ADDED context = nil for potential backward compat
      validate_params(params)
      # Log parameters *after* validation succeeds but before execution
      ADK.logger.debug("Executing tool '#{name}' with validated params: #{params.inspect} and context: #{context&.to_h.inspect}")
      # Pass context to perform_execution
      perform_execution(params, context) # <-- MODIFIED: Pass context
    end

    # Validate the parameters
    def validate_params(params)
      required_param_names = @parameters.select { |_, p| p[:required] }.keys.map(&:to_s)
      # Handle both symbol and string keys from input params
      present_keys = params.keys.map(&:to_s)
      missing_params = required_param_names - present_keys

      unless missing_params.empty?
        log_message = "Validation failed for tool '#{@name}'. Required(string): #{required_param_names.inspect}, Received keys(string): #{present_keys.inspect}, Received params: #{params.inspect}"
        ADK.logger.error(log_message)
        raise ADK::Error, "Missing required parameters: #{missing_params.join(', ')}"
      end
      # Optional: Add type validation here later if needed
    end

    private

    # Perform the actual execution of the tool
    # Subclasses MUST implement this method.
    # @param params [Hash] The validated parameters to execute with.
    # @param context [ADK::ToolContext, nil] Contextual information (session details). <-- ADDED
    # @return [Hash] A hash with :status (:success, :error, :pending) and :result/:error_message/:workflow_id.
    def perform_execution(params, context) # <-- ADDED context
      raise NotImplementedError, "Subclasses must implement #perform_execution(params, context)"
    end
  end
end
```

**5. Update Existing Tools to Accept Context**

*   **Action:** Modify `perform_execution` in *all* existing tool subclasses (`lib/adk/tools/*.rb`) to accept the `context` argument, even if they don't use it immediately.

*Example Change (Apply similarly to all tools):*

*   **File:** `lib/adk/tools/echo.rb`

```ruby
# File: lib/adk/tools/echo.rb
# frozen_string_literal: true

require_relative '../tool'

module ADK
  module Tools
    class Echo < Tool
      define_metadata(
        name: :echo,
        description: 'Echoes back the provided message.',
        parameters: {
          message: {
            type: :string,
            description: 'The message to echo',
            required: true
          }
        }
      )

      def initialize(**options)
        super(**options)
      end

      private

      # Returns a hash with :status and :result or :error_message
      # @param params [Hash] The validated parameters.
      # @param _context [ADK::ToolContext, nil] The execution context (unused here). <-- ADDED
      def perform_execution(params, _context) # <-- ADDED _context
        begin
          # Fetch validated parameter using fetch for safety against nil keys
          message = params.fetch(:message) { params.fetch('message', nil) } # Allow string or symbol keys

          # This check is belts-and-suspenders; validation should catch missing required params.
          unless message
            err_msg = "Internal Error: Message parameter missing in perform_execution for Echo tool after validation."
            ADK.logger.error(err_msg)
            return { status: :error, error_message: err_msg }
          end

          # Simple success case
          { status: :success, result: message }
        rescue StandardError => e # Catch any truly unexpected errors during fetch/processing
          ADK.logger.error("Echo Tool: Unexpected error: #{e.class} - #{e.message}")
          { status: :error, error_message: "Unexpected error in Echo tool: #{e.message}" }
        end
      end
    end # End Echo class
  end # End Tools module
end # End ADK module
```

*(Repeat the pattern of adding `_context` or `context` to `perform_execution` for `calculator.rb`, `cat_facts.rb`, `random_number_tool.rb`, and `agent_tool.rb`)*

**6. Create Base Long-Running Tool**

*   **File:** `lib/adk/tools/base_long_running_tool.rb` (New File)
*   **Action:** Define the abstract base class.

```ruby
# File: lib/adk/tools/base_long_running_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative '../error'
require 'securerandom'

module ADK
  module Tools
    # Abstract base class for tools that initiate long-running tasks via Temporal.
    class BaseLongRunningTool < ADK::Tool

      # Subclasses MUST override this method to return the Temporal Workflow class
      # that should be executed.
      # @return [Class] The Temporal Workflow class (must respond to #execute).
      def temporal_workflow_class
        raise NotImplementedError, "#{self.class.name} must implement #temporal_workflow_class"
      end

      # Subclasses MUST override this method to define the Temporal Task Queue.
      # @return [String] The name of the Temporal Task Queue for the workflow.
      def temporal_task_queue
        raise NotImplementedError, "#{self.class.name} must implement #temporal_task_queue"
      end

      # Subclasses SHOULD override this method to customize workflow options.
      # @return [Hash] Options hash for Temporalio::Client#start_workflow.
      def temporal_workflow_options
        {
          task_queue: temporal_task_queue,
          # Default timeouts - subclasses should override if needed
          execution_timeout: 3600, # 1 hour
          run_timeout: 3600,       # 1 hour
          task_timeout: 60         # 1 minute
        }
      end

      # Subclasses MUST override this method to prepare the input arguments
      # for the Temporal workflow based on the ADK tool's parameters and context.
      # @param params [Hash] The validated parameters passed to the ADK tool.
      # @param context [ADK::ToolContext] Contextual information (session_id, etc.).
      # @return [Array] An array of arguments to be passed to the workflow's execute method.
      def prepare_workflow_input(params, context)
        raise NotImplementedError, "#{self.class.name} must implement #prepare_workflow_input(params, context)"
      end

      # Subclasses CAN override this to generate a custom workflow ID.
      # Default uses a UUID.
      # @param params [Hash] The validated parameters passed to the ADK tool.
      # @param context [ADK::ToolContext] Contextual information (session_id, etc.).
      # @return [String] The Temporal Workflow ID.
      def generate_workflow_id(params, context)
        # Example: Include session_id for potential correlation
        "#{name}-#{context&.session_id || 'no-session'}-#{SecureRandom.uuid}"
      end

      # Overrides ADK::Tool#perform_execution to start the Temporal workflow.
      # @param params [Hash] The validated parameters.
      # @param context [ADK::ToolContext] The execution context.
      # @return [Hash] { status: :pending, workflow_id: ... } or { status: :error, ... }
      private def perform_execution(params, context)
        client = ADK.temporal_client # Get the configured client
        workflow_class = temporal_workflow_class
        workflow_args = prepare_workflow_input(params, context)
        workflow_id = generate_workflow_id(params, context)
        options = temporal_workflow_options.merge(id: workflow_id) # Ensure ID is in options

        unless client
          msg = "Temporal client not configured. Cannot start long-running task for tool '#{name}'."
          ADK.logger.error(msg)
          return { status: :error, error_message: msg }
        end
        unless workflow_class
          msg = "temporal_workflow_class not defined for tool '#{name}'."
          ADK.logger.error(msg)
          return { status: :error, error_message: msg }
        end

        ADK.logger.info("Starting Temporal Workflow '#{workflow_class.name}' with ID '#{workflow_id}' for tool '#{name}'. Task Queue: #{options[:task_queue]}")
        ADK.logger.debug("Workflow Args: #{workflow_args.inspect}")
        ADK.logger.debug("Workflow Options: #{options.inspect}")

        begin
          # Use start_workflow to run asynchronously
          handle = client.start_workflow(
            workflow_class,
            *workflow_args, # Splat the arguments array
            **options
          )

          ADK.logger.info("Successfully started Temporal Workflow '#{handle.id}'. Task is pending.")
          # Immediately return pending status and the workflow ID
          { status: :pending, workflow_id: handle.id }

        rescue Temporalio::Error::ClientError, Temporalio::Error::ServerError => e
          # Catch specific Temporal client/server errors during start
          msg = "Failed to start Temporal Workflow for tool '#{name}': #{e.class} - #{e.message}"
          ADK.logger.error(msg)
          ADK.logger.error(e.backtrace.first(5).join("\n"))
          { status: :error, error_message: msg }
        rescue StandardError => e
          # Catch other unexpected errors
          msg = "Unexpected error starting Temporal Workflow for tool '#{name}': #{e.class} - #{e.message}"
          ADK.logger.error(msg)
          ADK.logger.error(e.backtrace.first(5).join("\n"))
          { status: :error, error_message: msg }
        end
      end
    end
  end
end
```

**7. Create Check Workflow Status Tool**

*   **File:** `lib/adk/tools/check_workflow_status_tool.rb` (New File)
*   **Action:** Implement the built-in polling tool.

```ruby
# File: lib/adk/tools/check_workflow_status_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative '../error'
require 'temporalio/errors' # To catch specific Temporal errors
require 'timeout' # For result fetch timeout

module ADK
  module Tools
    # A built-in tool to check the status and retrieve results from a Temporal Workflow.
    class CheckWorkflowStatusTool < ADK::Tool

      RESULT_FETCH_TIMEOUT = 5 # Seconds to wait for result fetch if workflow is complete

      define_metadata(
        name: :check_workflow_status,
        description: 'Checks the status and retrieves the result of a previously started long-running task (Temporal Workflow) using its ID.',
        parameters: {
          workflow_id: {
            type: :string,
            description: 'The unique ID of the Temporal Workflow to check.',
            required: true
          }
        }
      )

      def initialize(**options)
        super(**options)
        # No specific initialization needed for this tool
      end

      private

      # @param params [Hash] Must contain :workflow_id.
      # @param _context [ADK::ToolContext, nil] The execution context (unused here).
      # @return [Hash] { status: :pending/:success/:error, ... }
      def perform_execution(params, _context)
        client = ADK.temporal_client
        workflow_id = params.fetch(:workflow_id) { params.fetch('workflow_id', nil) }

        unless client
          msg = "Temporal client not configured. Cannot check workflow status."
          ADK.logger.error(msg)
          return { status: :error, error_message: msg }
        end
        unless workflow_id
          msg = "Missing required parameter: workflow_id" # Should be caught by validation, but double-check
          ADK.logger.error("CheckWorkflowStatusTool Error: #{msg}")
          return { status: :error, error_message: msg }
        end

        ADK.logger.info("Checking status for Temporal Workflow ID: '#{workflow_id}'")

        begin
          handle = client.workflow_handle(workflow_id)
          description = handle.describe

          case description.status
          when :RUNNING
            ADK.logger.info("Workflow '#{workflow_id}' is still running.")
            { status: :pending, workflow_id: workflow_id, message: "Task is still running." }
          when :COMPLETED
            ADK.logger.info("Workflow '#{workflow_id}' completed. Fetching result...")
            begin
              # Use a timeout for fetching the result
              result = handle.result(timeout: RESULT_FETCH_TIMEOUT)
              ADK.logger.info("Workflow '#{workflow_id}' result fetched successfully.")
              { status: :success, result: result }
            rescue Timeout::Error
              msg = "Workflow '#{workflow_id}' completed, but timed out fetching result after #{RESULT_FETCH_TIMEOUT}s."
              ADK.logger.warn(msg)
              { status: :pending, workflow_id: workflow_id, message: msg } # Still pending from agent's perspective
            rescue StandardError => result_err
              msg = "Workflow '#{workflow_id}' completed, but failed to fetch result: #{result_err.class} - #{result_err.message}"
              ADK.logger.error(msg)
              { status: :error, error_message: msg }
            end
          when :FAILED, :TIMED_OUT, :TERMINATED, :CANCELED
            status_str = description.status.to_s.downcase
            msg = "Workflow '#{workflow_id}' finished with non-completed status: #{status_str}."
            ADK.logger.warn(msg)
            # Try to get failure info (might require fetching history in complex cases)
            # For simplicity, we just report the status now.
            # You might need to fetch history `handle.fetch_history` and parse for failure details.
            error_details = "Workflow finished with status: #{status_str}"
            # Attempt to get failure if available (might be nil)
            begin
              handle.result # This might raise the actual workflow failure exception
            rescue Temporalio::Error::WorkflowFailure => wf_failure
               error_details += ". Cause: #{wf_failure.cause.class} - #{wf_failure.cause.message}" if wf_failure.cause
            rescue StandardError => e
               error_details += ". Error getting failure details: #{e.class}"
            end
            { status: :error, error_message: error_details }
          else
            msg = "Workflow '#{workflow_id}' has unexpected status: #{description.status}"
            ADK.logger.error(msg)
            { status: :error, error_message: msg }
          end

        rescue Temporalio::Error::NotFound
          msg = "Temporal Workflow ID '#{workflow_id}' not found."
          ADK.logger.error(msg)
          { status: :error, error_message: msg }
        rescue Temporalio::Error::ClientError, Temporalio::Error::ServerError => e
          msg = "Error interacting with Temporal for workflow '#{workflow_id}': #{e.class} - #{e.message}"
          ADK.logger.error(msg)
          { status: :error, error_message: msg }
        rescue StandardError => e
          msg = "Unexpected error checking workflow status for '#{workflow_id}': #{e.class} - #{e.message}"
          ADK.logger.error(msg)
          ADK.logger.error(e.backtrace.first(5).join("\n"))
          { status: :error, error_message: msg }
        end
      end
    end
  end
end
```

**8. Update Agent Execution Logic**

*   **File:** `lib/adk/agent.rb`
*   **Action:** Modify `execute_step` to create and pass `ToolContext`.

```ruby
# File: lib/adk/agent.rb
# frozen_string_literal: true

require 'logger'
require 'concurrent'
require_relative 'tool_context' # <-- ADDED require

# Note: Requires are handled by lib/adk.rb

module ADK
  class Error < StandardError; end unless defined?(ADK::Error)

  # Agent class represents an AI agent that can perform tasks using tools and a planner.
  # It operates within the context of a session managed by a SessionService.
  class Agent
    DEFAULT_MODEL = 'gemini-2.0-flash'

    attr_reader :name, :description, :tools, :planner, :logger, :model_name

    # Initializes a new agent instance.
    # Note: Session and Memory are no longer managed directly by the agent instance.
    #
    # @param name [String] The unique name of the agent definition.
    # @param description [String] A description of the agent's purpose.
    # @param model_name [String, nil] The specific LLM model name (optional).
    # @param options [Hash] Additional options:
    # @option options [ADK::Planner] :planner Custom planner instance.
    # @option options [Logger] :logger Custom logger instance.
    def initialize(name:, description:, model_name: nil, **options)
      @name = name
      @description = description
      @model_name = model_name && !model_name.empty? ? model_name : DEFAULT_MODEL
      @tools = []
      @logger = options[:logger] || ADK.logger
      # Planner is still needed per agent instance, configured with its model
      @planner = options[:planner] || ADK::Planner.new(agent: self, logger: @logger, model_name: @model_name)
      # @memory and @session removed
      @state = Concurrent::Map.new # For runtime state ONLY (e.g., running?)
      logger.info("Agent '#{@name}' initialized with model: '#{@model_name}'")

      # Automatically add check_workflow_status tool if Temporal client is configured
      # But only if it hasn't been added manually already
      if ADK.temporal_client rescue nil # Check if client can be initialized without error
         unless @tools.any? { |t| t.name == :check_workflow_status }
            begin
              status_tool_instance = ADK::ToolRegistry.create_instance(:check_workflow_status)
              add_tool(status_tool_instance) if status_tool_instance
              logger.info("Automatically added :check_workflow_status tool.")
            rescue => e
              logger.warn("Failed to automatically add :check_workflow_status tool: #{e.message}")
            end
         end
      end
    end

    # Adds a tool instance.
    def add_tool(tool)
      unless tool.is_a?(ADK::Tool)
        logger.error("Attempted to add invalid tool: #{tool.inspect}")
        return self
      end
      if @tools.any? { |t| t.name == tool.name }
        logger.warn("Tool '#{tool.name}' already added to agent '#{name}'. Skipping.")
      else
        @tools << tool
        logger.debug("Added tool '#{tool.name}' to agent '#{name}'")
      end
      self
    end

    # --- Runtime State Methods (unchanged) ---
    def start
      # ... (unchanged start logic) ...
    end

    def stop
      # ... (unchanged stop logic) ...
    end

    def running?
      # ... (unchanged running? logic) ...
    end
    # --- End Runtime State Methods ---

    # --- REFACTORED: run_task operates within a session context ---
    # Processes user input within the context of a specific session.
    #
    # @param session_id [String] The ID of the session to use/update.
    # @param user_input [String] The user's input/request for this turn.
    # @param session_service [Object] The service used to manage sessions (must respond to #append_event, #get_session).
    # @return [ADK::Event] The final :agent event containing the response.
    # @return [Hash] An error hash { status: :error, error_message: ... } if a critical error occurs (less common now, errors wrap in Events).
    def run_task(session_id:, user_input:, session_service:)
      final_agent_event = nil # Define here for scope
      adk_session = nil # Define session here for access in rescue

      # --- Pre-check: Get Session ---
      adk_session = session_service.get_session(session_id: session_id) # Assign to adk_session
      unless adk_session
        msg = "Session not found: #{session_id}"
        logger.error(msg)
        # Create and attempt to log an error event *even if session isn't found*
        # The service might handle this case (e.g., log to central log).
        error_event = ADK::Event.new(role: :agent, content: { status: :error, error_message: msg }) # Wrap error content
        session_service.append_event(session_id: session_id, event: error_event) rescue nil # Best effort
        return error_event # Return the event itself
      end

      # --- Pre-check: Agent Running? ---
      unless running?
        msg = "Agent '#{name}' runtime is not active (stopped)."
        logger.error(msg)
        error_event = ADK::Event.new(role: :agent, content: { status: :error, error_message: msg }) # Wrap error content
        session_service.append_event(session_id: session_id, event: error_event)
        return error_event
      end

      logger.info("Agent '#{name}' starting task in session '#{session_id}': #{user_input}")

      # --- Task Processing Block ---
      begin
        # 1. Record User Event
        user_event = ADK::Event.new(role: :user, content: user_input)
        session_service.append_event(session_id: session_id, event: user_event)

        # 2. Plan Execution
        plan = []
        # TODO: Pass session history/state to planner if needed for context
        plan = planner.plan(user_input) # Returns Array of Hashes or empty Array

        # 3. Execute Plan (Logs events internally)
        # Returns Hash or Array<Hash> or Error Hash
        # Note: execute_plan now calls execute_step which uses append_event internally
        execution_result = execute_plan(plan, adk_session, session_service) # Pass session object

        # 4. Determine Final Agent Response based on execution result
        final_content = nil
        # --- State Change: Define delta hash if needed ---
        # state_changes_from_task = {} # Example: { user_preference: 'blue' }

        if execution_result.is_a?(Hash) && execution_result[:status] == :error
          # Handle planning error or single-step execution error
          final_content = execution_result # Pass the whole error hash
          logger.error("Agent '#{name}' task failed. Reason: #{execution_result[:error_message]}")
        elsif execution_result.is_a?(Array)
          # Multi-step: Handle based on last step's status
          last_step = execution_result.last
          if last_step
            if last_step[:status] == :success
               final_content = last_step # Pass the success hash
               logger.info("Agent '#{name}' task completed multi-step successfully.")
            elsif last_step[:status] == :pending
                final_content = last_step # Pass the pending hash
                logger.info("Agent '#{name}' task resulted in pending status.")
            else # Error
               final_content = last_step # Pass the error hash
               logger.warn("Agent '#{name}' task completed multi-step with error. Last step msg: #{last_step&.dig(:error_message)}")
            end
          else # Empty results array? Should not happen if plan was not empty.
            final_content = { status: :error, error_message: "Multi-step execution resulted in empty result array."}
            logger.error(final_content[:error_message])
          end
        elsif execution_result.is_a?(Hash) && (execution_result[:status] == :success || execution_result[:status] == :pending) # Single successful or pending step
          final_content = execution_result # Pass the success/pending hash
          logger.info("Agent '#{name}' task completed with status: #{execution_result[:status]}.")
        else
          msg = "Task finished with unexpected execution result: #{execution_result.inspect}"
          final_content = { status: :error, error_message: msg }
          logger.error(msg)
        end

        # Ensure final content is a Hash for the event content
        unless final_content.is_a?(Hash) && final_content.key?(:status)
           final_content = { status: :success, result: final_content.to_s } # Wrap simple strings/results
        end

        # 5. Record Final Agent Event
        final_agent_event = ADK::Event.new(
          role: :agent,
          content: final_content # Store the result/error/pending hash directly
          # state_delta: state_changes_from_task # Pass delta if needed
        )
        session_service.append_event(session_id: session_id, event: final_agent_event)
      rescue StandardError => e
        # Catch errors during the overall run_task flow
        logger.error("Critical error during run_task for agent '#{name}': #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        error_event_content = { status: :error, error_message: "An internal error occurred: #{e.message}" }
        # Create and log agent error event
        final_agent_event = ADK::Event.new(role: :agent, content: error_event_content)
        session_service.append_event(session_id: session_id, event: final_agent_event) if adk_session rescue nil # Best effort log
      end

      # 6. Return the final agent event itself
      final_agent_event
    end # end run_task

    private

    # --- REFACTORED: execute_plan uses session context ---
    # Executes a plan, logging tool request/result events via the session service.
    # @param plan [Array<Hash>] Plan from the planner.
    # @param session [ADK::Session] The current session object.
    # @param session_service [Object] The session service instance.
    # @return [Hash, Array<Hash>] Result hash or array of hashes from steps. Returns error hash on planning issues.
    def execute_plan(plan, session, session_service) # <-- Takes session object now
      session_id = session.id # Get ID from session

      unless plan.is_a?(Array)
        msg = "Invalid plan received from planner (not an Array)."
        logger.error("#{msg} Plan: #{plan.inspect}")
        return { status: :error, error_message: msg }
      end
      if plan.empty?
        msg = "I cannot fulfill this request with the available tools (empty plan)."
        logger.warn(msg)
        return { status: :error, error_message: msg }
      end

      logger.debug("Executing plan with #{plan.length} step(s) for session '#{session_id}': #{plan.inspect}")
      previous_step_result_hash = nil
      all_results_hashes = []

      plan.each_with_index do |step, index|
        logger.debug("Executing step #{index + 1}/#{plan.length}: #{step.inspect}")
        logger.debug("  Input (result hash from previous step): #{previous_step_result_hash.inspect}")

        # --- Input Injection Logic (Updated for nested results) ---
        current_params = step[:params].dup
        current_params.transform_values! do |value|
          injection_value = nil
          if value.is_a?(String) && value.match?(/\[Result from step \d+\]|\[Result from previous step\]/i)
             # --- Check previous step was success or pending (pending might have useful IDs) ---
             if previous_step_result_hash && [:success, :pending].include?(previous_step_result_hash[:status])
               # Prioritize :result, then :workflow_id, then :message if previous was pending/success
               if previous_step_result_hash.key?(:result)
                 prev_result = previous_step_result_hash[:result]
                 # Handle nested results if previous step was AgentTool
                 if prev_result.is_a?(Hash) && prev_result.key?(:status) && prev_result.key?(:result)
                     injection_value = prev_result[:result]
                     logger.debug("Injecting nested result...")
                 else
                     injection_value = prev_result
                     logger.debug("Injecting direct result...")
                 end
               elsif previous_step_result_hash.key?(:workflow_id)
                 injection_value = previous_step_result_hash[:workflow_id]
                 logger.debug("Injecting workflow_id from previous step...")
               elsif previous_step_result_hash.key?(:message) # Less common, maybe from pending status
                 injection_value = previous_step_result_hash[:message]
                 logger.debug("Injecting message from previous step...")
               else
                 logger.warn("Cannot inject: Previous successful/pending step missing usable key (:result, :workflow_id, :message). Prev Hash: #{previous_step_result_hash.inspect}")
                 value # Keep original placeholder
               end
             else # Previous step failed or was nil
               logger.warn("Cannot inject: Previous step failed or absent. Prev Hash: #{previous_step_result_hash.inspect}")
               value # Keep original placeholder
             end
             injection_value || value # Use injection if found, otherwise keep original
          else
            value # Not a placeholder string, keep original value
          end
        end
        step_with_injected_params = step.merge(params: current_params)
        logger.debug("  Params after potential injection: #{current_params.inspect}")
        # --- End Input Injection Logic ---

        # --- Execute Step (Passes session context) ---
        current_result_hash = execute_step(step_with_injected_params, session, session_service) # <-- Pass session
        all_results_hashes << current_result_hash

        # --- Stop on first error ---
        if current_result_hash[:status] == :error
          logger.warn("Step #{index + 1} failed, stopping plan execution: #{current_result_hash[:error_message]}")
          break # Exit the loop
        end
        # --- End Stop on first error ---

        previous_step_result_hash = current_result_hash
      end

      logger.debug("Plan execution finished. Result hashes collected: #{all_results_hashes.inspect}")

      if all_results_hashes.length == 1
        all_results_hashes.first
      else
        all_results_hashes
      end
    end # end execute_plan

    # --- REFACTORED: execute_step uses session context ---
    # Executes a single step, logging :tool_request and :tool_result events via session service.
    # @param step [Hash] A hash like { tool: :symbol, params: {...} }.
    # @param session [ADK::Session] The current session object.
    # @param session_service [Object] The session service instance.
    # @return [Hash] A standard result hash { status: ..., result/error_message/workflow_id: ... }.
    def execute_step(step, session, session_service) # <-- Takes session object now
      session_id = session.id # Get ID from session

      # --- Basic validation ---
      # ... (validation unchanged) ...

      # 1. Log Tool Request Event (No state delta typically for requests)
      request_event = ADK::Event.new(role: :tool_request, tool_name: tool_name, content: params)
      session_service.append_event(session_id: session_id, event: request_event)

      # 2. Execute Tool
      result_hash = nil
      begin
        tool = find_tool(tool_name) # Raises ADK::Error if not found

        # --- Create ToolContext ---
        tool_context = ADK::ToolContext.new(
          session_id: session.id,
          user_id: session.user_id,
          app_name: session.app_name
        )
        logger.info("Executing tool '#{tool_name}' with params: #{params.inspect}")
        # --- Pass context to execute ---
        result_hash = tool.execute(params, tool_context) # <-- MODIFIED: Pass context

        # Validate tool's return format (including :pending status)
        unless result_hash.is_a?(Hash) && result_hash.key?(:status) && [:success, :error, :pending].include?(result_hash[:status])
          logger.error("Tool '#{tool_name}' returned invalid hash or status: #{result_hash.inspect}")
          result_hash = { status: :error, error_message: "Tool '#{tool_name}' failed to return standard hash format." }
        end
      rescue ADK::Error => e # Tool not found or validation error from tool.execute
        logger.error("ADK::Error executing tool '#{tool_name}': #{e.message}")
        result_hash = { status: :error, error_message: e.message }
      rescue StandardError => e # Unexpected error within tool.execute
        logger.error("Unexpected error executing tool '#{tool_name}': #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
        result_hash = { status: :error, error_message: "Internal error executing tool '#{tool_name}': #{e.message}" }
      end

      # 3. Log Tool Result Event
      result_event = ADK::Event.new(
        role: :tool_result,
        tool_name: tool_name,
        content: result_hash # Log the entire result hash as content
      )
      session_service.append_event(session_id: session_id, event: result_event)

      # 4. Return the result hash from the tool execution
      result_hash
    end # end execute_step

    # --- find_tool remains unchanged ---
    def find_tool(name_symbol)
      # ... (unchanged find_tool logic) ...
    end
  end # End Agent class
end # End ADK module

```

**9. Update CLI**

*   **File:** `lib/adk/cli/agent_commands.rb`
*   **Action:** Modify `format_cli_result` to handle `:pending` status.

```ruby
# File: lib/adk/cli/agent_commands.rb
# frozen_string_literal: true

require 'thor'
require 'redis'
require 'json'
require_relative '../tool_registry'
require_relative '../agent'
require_relative '../event'   # Need Event for result formatting understanding
require_relative '../session' # Need Session for session service context
require_relative '../session_service/in_memory' # Need Service implementation
require_relative '../session_service/redis' # Add Redis session service

module ADK
  module CLI
    # CLI commands for agent definition management AND temporary execution
    class AgentCommands < Thor
      # Redis Keys Constants
      REDIS_AGENT_HASH_PREFIX = "adk:agent:"
      REDIS_AGENTS_SET_KEY = "adk:agents:all_names"

      # --- Session Service Instance ---
      # For the CLI, InMemorySessionService is suitable as state is lost anyway on exit.
      # A shared instance allows reusing session ID across multiple execute calls if needed.
      @@session_service = ADK::SessionService::InMemory.new

      no_commands do
        def agent_redis_key(name)
          "#{REDIS_AGENT_HASH_PREFIX}#{name}"
        end

        def connect_redis
          redis = Redis.new # Assumes localhost:6379
          redis.ping # Verify connection
          redis
        rescue Redis::CannotConnectError => e
          say "Error: Could not connect to Redis. Is it running? (#{e.message})", :red
          exit(1) # Exit if Redis is unavailable
        end

        def parse_tools(tools_json)
          return [] unless tools_json && !tools_json.empty?

          JSON.parse(tools_json) rescue [] # Return empty array on parse error
        end

        # --- Updated format_cli_result to handle Event/Error/Pending Hash ---
        def format_cli_result(result_data)
          content_to_display = nil
          is_error = false
          is_pending = false # <-- ADDED
          status_prefix = ""

          # Determine what kind of result we got from run_task
          if result_data.is_a?(ADK::Event)
            if result_data.role == :agent || result_data.role == :tool_result
              content_to_display = result_data.content
              # Check if the content itself is a status hash
              if content_to_display.is_a?(Hash) && content_to_display.key?(:status)
                is_error = (content_to_display[:status] == :error)
                is_pending = (content_to_display[:status] == :pending) # <-- ADDED check
                status_prefix = "(Nested Result) " if result_data.role == :agent # Indicate the origin only for agent final
              end
            end
          elsif result_data.is_a?(Hash) && result_data.key?(:status)
            # An error occurred directly during run_task OR a tool returned directly (less common now)
            content_to_display = result_data
            is_error = (result_data[:status] == :error)
            is_pending = (result_data[:status] == :pending) # <-- ADDED check
          else
            # Handle simple responses (like strings) as successful results
            content_to_display = result_data
            is_error = false
            is_pending = false
          end

          # Now format based on the determined content and status
          if content_to_display.is_a?(Array) && !is_error && !is_pending # Multi-Step Plan Result
            say "#{status_prefix}Multi-Step Result:", :cyan
            any_step_errors = false
            any_step_pending = false # <-- ADDED
            content_to_display.each_with_index do |step_hash, index|
              if step_hash.is_a?(Hash) && step_hash.key?(:status)
                case step_hash[:status]
                when :success
                  say "  Step #{index + 1} (Success):", :green
                  step_result = step_hash[:result]
                  if step_result.is_a?(Hash) && step_result.key?(:status)
                    say "    Result (Nested): #{step_result.inspect}"
                  else
                    say "    Result: #{step_result}"
                  end
                when :pending # <-- ADDED case
                  say "  Step #{index + 1} (Pending):", :yellow
                  say "    Workflow ID: #{step_hash[:workflow_id]}"
                  say "    Message: #{step_hash[:message]}" if step_hash[:message]
                  any_step_pending = true
                when :error # :error or other
                  say "  Step #{index + 1} (Error):", :red
                  say "    Message: #{step_hash[:error_message]}"
                  any_step_errors = true
                else
                   say "  Step #{index + 1} (Unknown Status): #{step_hash.inspect}", :yellow
                   any_step_errors = true # Treat as error
                end
              else
                say "  Step #{index + 1} (Unknown Step Format): #{step_hash.inspect}", :yellow
                any_step_errors = true
              end
            end
            # --- UPDATED Overall Status ---
            overall_msg = if any_step_errors
                            'Completed with errors'
                          elsif any_step_pending
                            'Completed with pending steps'
                          else
                            'Completed successfully'
                          end
            overall_color = if any_step_errors
                              :red
                            elsif any_step_pending
                              :yellow
                            else
                              :green
                            end
            say "Overall Plan Status: #{overall_msg}", overall_color

          elsif content_to_display.is_a?(Hash) && content_to_display.key?(:status)
            # Single step result or error/pending
            case content_to_display[:status]
            when :success
              say "#{status_prefix}Success:", :green
              say "  Result: #{content_to_display[:result]}"
            when :pending # <-- ADDED case
              say "#{status_prefix}Pending:", :yellow
              say "  Workflow ID: #{content_to_display[:workflow_id]}"
              say "  Message: #{content_to_display[:message]}" if content_to_display[:message]
            when :error
              say "#{status_prefix}Error:", :red
              say "  Message: #{content_to_display[:error_message]}"
            else
              say "#{status_prefix}Unknown Status:", :yellow
              say "  Data: #{content_to_display.inspect}"
            end
          else
            # Simple response (like a string) - Treat as success
            say "#{status_prefix}Success:", :green
            say "  Result: #{content_to_display}"
          end
        end
        # --- End format_cli_result ---
      end # end no_commands

      # --- Definition Management Commands (Unchanged) ---
      desc 'list', 'List all defined agents from Redis'
      def list
        # ... (unchanged list logic) ...
      end

      desc 'create NAME', 'Create a new agent definition in Redis'
      method_option :description, type: :string, required: true, desc: 'Agent description'
      method_option :tools, type: :string, aliases: "-t",
                            desc: 'Comma-separated list of tool names (e.g., "echo,calculator")'
      method_option :model, type: :string, desc: "LLM model name (default: #{ADK::Agent::DEFAULT_MODEL})"
      def create(name)
        # ... (unchanged create logic) ...
      end

      desc 'update NAME', 'Update an existing agent definition in Redis'
      method_option :description, type: :string, desc: "New description for the agent"
      method_option :tools, type: :string, aliases: "-t", desc: 'REPLACE existing tools with this list'
      method_option :add_tool, type: :string, repeatable: true, desc: 'Add a specific tool'
      method_option :remove_tool, type: :string, repeatable: true, desc: 'Remove a specific tool'
      method_option :model, type: :string, desc: "New LLM model name for the agent"
      def update(name)
       # ... (unchanged update logic) ...
      end

      desc 'delete NAME', "Delete an agent's definition from Redis"
      def delete(name)
        # ... (unchanged delete logic) ...
      end

      # --- Runtime/Execution Commands (Using Redis Definition) ---

      desc 'start NAME', 'Verify agent definition loading and start (Ephemeral)'
      long_desc <<-LONGDESC
        Loads agent definition, instantiates agent, starts agent runtime state,
        verifies all components loaded correctly, prints details & exits.
        This is a diagnostic tool to verify agent definition loads properly.
        Use 'execute' command to run an actual task with the agent.
      LONGDESC
      def start(name)
        # ... (unchanged start logic) ...
      end

      # --- Updated 'execute' command for Session Handling ---
      desc 'execute NAME TASK', 'Execute a task using agent definition (ephemeral)'
      long_desc <<-LONGDESC
        Loads agent definition, instantiates agent, runs TASK within a session context,
        prints the result, stops agent runtime & exits.

        Use --session-id to continue an existing conversation,
        otherwise starts a new session for this execution. The session ID used will be printed.

        Use --redis to use Redis for session storage instead of in-memory storage.
        This allows sessions to persist between CLI invocations.

        If a task results in a :pending status (e.g., for a long-running tool),
        the workflow_id will be printed. Use the check_workflow_status tool
        in a subsequent call to get the final result.
      LONGDESC
      method_option :session_id, type: :string, desc: 'Optional ID of an existing session to use.'
      method_option :redis, type: :boolean, default: false, desc: 'Use Redis for session storage instead of in-memory.'
      def execute(name, task)
        say "Loading agent '#{name}' to execute task: \"#{task}\"..."
        redis = connect_redis
        key = agent_redis_key(name)
        redis_agent_data = redis.hmget(key, 'description', 'tools', 'model')
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]
        model_name = redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL

        unless description then say "Error: Agent definition '#{name}' not found.", :red; exit(1); end

        # --- Session Handling ---
        session_service = options[:redis] ? ADK::SessionService::Redis.new : @@session_service
        session_id = options[:session_id]
        adk_session = nil

        if session_id
          adk_session = session_service.get_session(session_id: session_id)
          if adk_session
            say "Continuing session: #{session_id}", :cyan
          else
            say "Warning: Session ID '#{session_id}' provided but not found. Starting a new session.", :yellow
            session_id = nil # Force creation below
          end
        end

        unless adk_session
          adk_session = session_service.create_session(app_name: name, user_id: 'cli_user')
          session_id = adk_session.id
          say "Started new session: #{session_id}", :cyan
          say "  (Using #{options[:redis] ? 'Redis' : 'in-memory'} session storage)", :cyan
        end
        # --- End Session Handling ---

        agent = nil
        e = nil # Define error variable for ensure block
        begin
          # Instantiate Agent
          agent = ADK::Agent.new(name: name, description: description, model_name: model_name)
          say "  - Agent uses model: #{agent.model_name}", :cyan

          # Load Tools
          tool_names_to_load = parse_tools(tools_json_string).map(&:to_sym)
          # --- Automatically add check_workflow_status if not present ---
          unless tool_names_to_load.include?(:check_workflow_status)
            if ADK::ToolRegistry.find_class(:check_workflow_status)
              tool_names_to_load << :check_workflow_status
              say "  - Adding implicit tool: check_workflow_status", :faint
            end
          end
          # --- End auto-add ---
          added_tools = []
          if tool_names_to_load.empty?
            say "  - Warning: No tools configured.", :yellow
          else
            say "  - Adding tools: [#{tool_names_to_load.join(', ')}]", :cyan
            tool_names_to_load.each do |t|
              i = ADK::ToolRegistry.create_instance(t)
              if i
                agent.add_tool(i)
                added_tools << t
              else
                say "  - Warn: Tool '#{t}' not found in registry.", :yellow
              end
            end
          end

          # Start Agent Runtime & Execute Task within Session
          say "  - Starting agent runtime...", :cyan, false; agent.start; say "started.", :cyan
          say "  - Running task in session #{session_id}: '#{task}'...", :cyan, false;
          final_event_or_error = agent.run_task(
            session_id: session_id,
            user_input: task,
            session_service: session_service
          )
          say "finished.", :cyan

          # Format and Print Result (using updated helper)
          say "\nTask Result:", :bold
          format_cli_result(final_event_or_error) # Use helper method

        rescue StandardError => e # Catch errors during setup or run_task
          say "\nError during agent execution: #{e.class} - #{e.message}", :red
          puts e.backtrace.first(5).join("\n") # Print some backtrace for debug
        ensure
          # Stop the ephemeral agent runtime state
          if agent&.running?
            say "  - Stopping agent runtime...", :cyan, false; agent.stop; say "stopped.", :cyan
          end
          # Exit with error code if an exception was caught
          exit(1) if e
        end
      end # End 'execute' command

    end # End AgentCommands class
  end # End CLI module
end # End ADK module
```

*   **File:** `lib/adk/cli/tool_commands.rb`
*   **Action:** Modify `execute` result handling for `:pending`.

```ruby
# File: lib/adk/cli/tool_commands.rb
# frozen_string_literal: true

require 'thor'
require_relative '../tool_registry' # Require the registry
require_relative '../tool_context' # <--- ADDED require

module ADK
  module CLI
    # CLI commands for tool management using ToolRegistry
    class ToolCommands < Thor
      desc 'list', 'List available tools from the registry'
      def list
        # ... (list logic unchanged) ...
      end

      desc 'info NAME', 'Show information about a tool from the registry'
      def info(name)
        # ... (info logic unchanged) ...
      end

      desc 'execute NAME [param1=value1 param2=value2 ...]', 'Execute a tool directly using key=value arguments'
      long_desc <<-LONGDESC
      Executes a specified tool directly with key=value pair arguments.

      Example:
        adk tool execute calculator operand1=10 operand2=5 operation=add

      Arguments should be provided as `key=value`. If a value contains spaces,
      it might need quoting depending on your shell.

      If the tool execution results in a :pending status (e.g., for a long-running tool),
      the workflow_id will be printed. Use the check_workflow_status tool
      in a subsequent call to get the final result.
      LONGDESC
      def execute(name, *args)
        tool_name_sym = name.to_sym
        tool = ADK::ToolRegistry.create_instance(tool_name_sym)

        unless tool
          say "Error: Tool '#{name}' not found in registry.", :red
          exit(1)
        end

        params_to_execute = {}
        valid_param_names = tool.parameters.keys.map(&:to_s)

        args.each do |arg|
          parts = arg.split('=', 2)
          if parts.length == 2
            key = parts[0].strip
            value = parts[1]

            unless valid_param_names.include?(key)
              say "Warning: Provided parameter '#{key}' is not defined for tool '#{name}'. Ignoring.", :yellow
              next
            end

            params_to_execute[key.to_sym] = value # Store as symbol key
            say "  Parsed: #{key} = '#{value}'"
          else
            # Simplified single arg handling
            if args.length == 1 && tool.parameters.length == 1 && tool.parameters.values.first[:required]
              single_key = tool.parameters.keys.first # Should be symbol
              say "Info: Assuming single argument '#{arg}' maps to required parameter '#{single_key}'.", :cyan
              params_to_execute[single_key] = arg
            elsif !args.empty?
              say "Warning: Argument '#{arg}' ignored. Please use 'key=value' format for parameters.", :yellow
            end
          end
        end

        begin
          say "Executing tool '#{name}' with parsed params: #{params_to_execute.inspect}"
          # --- Create a dummy context for direct tool execution ---
          # Tools might expect context, even if they don't use session details here.
          dummy_context = ADK::ToolContext.new(session_id: "cli_direct_#{SecureRandom.hex(4)}", user_id: 'cli_user', app_name: 'cli_tool_exec')

          # --- Call execute with context ---
          result_hash = tool.execute(params_to_execute, dummy_context) # <-- PASS CONTEXT

          say "\nResult:", :bold
          if result_hash.is_a?(Hash) && result_hash.key?(:status)
            case result_hash[:status]
            when :success
              say "Success:", :green
              say "  Output: #{result_hash[:result]}"
            when :pending # <-- ADDED case
              say "Pending:", :yellow
              say "  Workflow ID: #{result_hash[:workflow_id]}"
              say "  Message: #{result_hash[:message]}" if result_hash[:message]
            when :error
              say "Error:", :red
              say "  Message: #{result_hash[:error_message]}"
            else
               say "Unknown Status:", :yellow
               say "  Data: #{result_hash.inspect}"
            end
          else
            say "Unknown Result Format:", :yellow
            say "  Data: #{result_hash.inspect}"
          end
        rescue ADK::Error, ArgumentError => e
          say "\nError executing tool:", :red
          say e.message, :red
        rescue StandardError => e
          say "\nAn unexpected error occurred:", :red
          say "#{e.class} - #{e.message}", :red
          puts e.backtrace.first(5).join("\n") # Add backtrace for unexpected errors
        end
      end # end execute
    end
  end
end

```

**10. Update Web UI**

*   **File:** `lib/adk/web/app.rb`
*   **Action:** Modify `format_execution_result_html` and route handlers for `/agents/:name/execute` and `/tools/:name/execute`.

```ruby
# File: lib/adk/web/app.rb
# frozen_string_literal: true

# STDOUT.sync = true # Uncomment for immediate output flushing if needed
require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/custom_logger' # For using helpers Sinatra::CustomLogger
require 'sinatra/reloader'
require 'slim'
require 'json'
require_relative 'sass_compiler'
require 'rack/utils' # For escape_html
require 'redis'
require 'securerandom' # For session secret

# --- Load ADK Components ---
# Load dependencies in a sensible order
require_relative '../event'   # Load Event first as Session uses it
require_relative '../session' # Load Session next
require_relative '../tool_context' # <--- ADDED
require_relative '../agent'   # Agent needs default model constant
require_relative '../tool'
require_relative '../tool_registry'
require_relative '../session_service/in_memory' # Load Service
require_relative '../session_service/redis' # Load Redis Service
# Explicitly require all tools
require_relative '../tools/echo'
require_relative '../tools/calculator'
require_relative '../tools/cat_facts'
require_relative '../tools/random_number_tool'
require_relative '../tools/agent_tool' # Load AgentTool
require_relative '../tools/base_long_running_tool' # <--- ADDED
require_relative '../tools/check_workflow_status_tool' # <--- ADDED

# Load dotenv for development AFTER other requires if needed
if ENV['RACK_ENV'] == 'development' || Sinatra::Base.development?
  begin; require 'dotenv/load'; rescue LoadError; end
end

module ADK
  module Web
    # Web interface for ADK
    class App < Sinatra::Base
      helpers Sinatra::CustomLogger # Use ADK.logger via 'logger' helper

      configure :development do
        register Sinatra::Reloader
        # Optional: Increase logging level specifically for development web server
        # ADK.logger.level = Logger::DEBUG if ADK.logger
      end

      # Configure the logger and session support for all environments
      configure do
        set :logger, ADK.logger # Use the central ADK logger for Sinatra's logging
        # --- Enable Sinatra Sessions ---
        enable :sessions
        # IMPORTANT: Set a strong secret key in production (e.g., via ENV variable)
        set :session_secret, ENV['SESSION_SECRET'] || SecureRandom.hex(64)
        # Initialize Temporal Client (best effort, log errors)
        begin
          ADK.temporal_client # Trigger lazy initialization
        rescue => e
          # Log error but don't crash the app start if Temporal isn't available
          ADK.logger.error("Temporal client initialization failed during app configure: #{e.message}")
        end
      end

      # --- Sinatra Settings ---
      set :root, File.expand_path('../../..', __dir__)
      set :views, File.expand_path('../views', __FILE__)
      set :public_folder, File.expand_path('../public', __FILE__)
      set :slim, pretty: true

      # --- Constants ---
      REDIS_AGENT_HASH_PREFIX = "adk:agent:"
      REDIS_AGENTS_SET_KEY = "adk:agents:all_names"
      AVAILABLE_MODELS = ['gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-1.5-pro', 'gemini-1.0-pro'].freeze

      # --- Instance Variables ---
      # Initialize agent registry, Redis client, AND Session Service
      def initialize
        super
        # In-memory store for LIVE/RUNNING agent *runtime* instances
        @agents = {}
        # Session service to manage conversation state
        # Use Redis if available for web sessions too? Or stick to in-memory? Let's stick to in-memory for now.
        @session_service = ADK::SessionService::InMemory.new
        # Redis client for persistent agent *definitions*
        begin
          @redis = Redis.new # Assumes default connection
          @redis.ping
          logger.info("Successfully connected to Redis.")
        rescue Redis::CannotConnectError => e
          logger.error("Could not connect to Redis. Persistence disabled. #{e.message}")
          @redis = nil
        end
        # Compile Sass on startup
        SassCompiler.compile_all
      end

      # Helper to generate Redis key for an agent definition hash
      def agent_redis_key(name)
        "#{REDIS_AGENT_HASH_PREFIX}#{name}"
      end

      # --- Sinatra Helpers ---
      helpers do
        # Helper for Agent Start/Stop button fragments (used in table view)
        def agent_status_fragments(agent_data_or_obj)
          # ... (unchanged helper logic) ...
        end # end agent_status_fragments

        # Helper for formatting tool/agent execution results into HTML
        # Handles success, error, and pending statuses.
        def format_execution_result_html(result_data)
          html_parts = []
          notification_class = 'is-info' # Default
          overall_status = :unknown # Default

          # --- Determine overall status ---
          # Handle ADK::Event first
          if result_data.is_a?(ADK::Event)
             result_data = result_data.content # Extract content hash
          end

          # Now work with the hash
          if result_data.is_a?(Hash) && result_data.key?(:status)
             overall_status = result_data[:status]
          elsif result_data.is_a?(Array) && result_data.all? { |h| h.is_a?(Hash) && h.key?(:status) }
             # Multi-step array - determine overall status
             if result_data.any? { |h| h[:status] == :error }
               overall_status = :error
             elsif result_data.any? { |h| h[:status] == :pending }
               overall_status = :pending
             elsif result_data.empty? # Empty plan result
               overall_status = :warning # Or treat as error?
             else # All success
               overall_status = :success
             end
          else # Unexpected format, treat as error
             overall_status = :error
             # Wrap the unexpected data into a standard error hash for consistent handling below
             result_data = { status: :error, error_message: "Unexpected result format: #{result_data.inspect}" }
          end
          # --- End determine overall status ---

          # Set notification class based on status
          notification_class = case overall_status
                               when :success then 'is-success'
                               when :error then 'is-danger'
                               when :pending then 'is-warning' # Use warning for pending
                               else 'is-info' # includes :unknown, :warning (empty plan)
                               end

          # --- Generate HTML content ---
          if result_data.is_a?(Array) # Multi-step result array
            html_parts << "<p><strong>Multi-step Result:</strong></p><ol>"
            result_data.each_with_index do |step_hash, index|
              html_parts << "<li>"
              if step_hash.is_a?(Hash) # Ensure it's a hash before checking status
                  case step_hash[:status]
                  when :success
                    step_result_content = step_hash[:result]
                    # Handle potential nested result from AgentTool for display
                    if step_result_content.is_a?(Hash) && step_result_content.key?(:status)
                      html_parts << "<strong>Step #{index + 1} (Success - Delegated):</strong>"
                      html_parts << "<blockquote style='margin-left: 1em; border-left: 3px solid #dbdbdb; padding-left: 1em;'>"
                      html_parts << format_execution_result_html(step_result_content) # Recursive call
                      html_parts << "</blockquote>"
                    else
                      html_parts << "<strong>Step #{index + 1} (Success):</strong> <pre>#{Rack::Utils.escape_html(step_result_content.to_s)}</pre>"
                    end
                  when :pending # <-- ADDED Pending Case for Multi-step
                    html_parts << "<strong>Step #{index + 1} (Pending):</strong>"
                    html_parts << "<pre>Workflow ID: #{Rack::Utils.escape_html(step_hash[:workflow_id].to_s)}"
                    html_parts << "\nMessage: #{Rack::Utils.escape_html(step_hash[:message].to_s)}" if step_hash[:message]
                    html_parts << "</pre>"
                  when :error
                    html_parts << "<strong>Step #{index + 1} (Error):</strong> <pre class='has-text-danger'>#{Rack::Utils.escape_html(step_hash[:error_message].to_s)}</pre>"
                  else # Unknown status
                    html_parts << "<strong>Step #{index + 1} (Unknown Status):</strong> <pre>#{Rack::Utils.escape_html(step_hash.inspect)}</pre>"
                  end
              else
                # Handle case where an element in the array isn't a hash
                html_parts << "<strong>Step #{index + 1} (Invalid format):</strong> <pre>#{Rack::Utils.escape_html(step_hash.inspect)}</pre>"
              end
              html_parts << "</li>"
            end
            html_parts << "</ol>"

          elsif result_data.is_a?(Hash) # Single result/error/pending hash
            case result_data[:status]
            when :success
              result_content = result_data[:result]
              # Handle potential nested result from AgentTool
              if result_content.is_a?(Hash) && result_content.key?(:status)
                html_parts << "<p><strong>Result (from delegated agent):</strong></p>"
                html_parts << "<blockquote style='margin-left: 1em; border-left: 3px solid #dbdbdb; padding-left: 1em;'>"
                html_parts << format_execution_result_html(result_content) # Recursive call
                html_parts << "</blockquote>"
              else
                html_parts << "<p><strong>Result:</strong></p><pre>#{Rack::Utils.escape_html(result_content.to_s)}</pre>"
              end
            when :pending # <-- ADDED Pending Case for Single Step
              html_parts << "<p><strong>Status: Pending</strong></p>"
              html_parts << "<pre>Workflow ID: #{Rack::Utils.escape_html(result_data[:workflow_id].to_s)}"
              html_parts << "\nMessage: #{Rack::Utils.escape_html(result_data[:message].to_s)}" if result_data[:message]
              html_parts << "\n(Use tool 'check_workflow_status' with this ID to get the final result)</pre>"
            when :error
              html_parts << "<p><strong>Error:</strong></p><pre class='has-text-danger'>#{Rack::Utils.escape_html(result_data[:error_message].to_s)}</pre>"
            else # Unknown status within hash
              html_parts << "<p><strong>Result (Unknown Status):</strong></p><pre>#{Rack::Utils.escape_html(result_data.inspect)}</pre>"
            end
          end # End if result_data.is_a?(Hash)
          # --- End Generate HTML ---

          # Return final HTML structure
          "<div class='notification #{notification_class} mt-4'>#{html_parts.join}</div>"
        end # end format_execution_result_html
      end # end helpers

      # --- Routes ---

      get '/' do
        # ... (unchanged route) ...
      end

      # --- Agent Definition Management Routes ---
      get '/agents' do
        # ... (unchanged route, may implicitly list check_workflow_status if tool registry is used) ...
      end

      post '/agents' do
        # ... (unchanged route) ...
      end

      delete '/agents/:name' do |name|
        # ... (unchanged route) ...
      end

      # Agent Detail Page
      get '/agents/:name' do |name|
        # ... (logic largely unchanged, but ensure check_workflow_status is included if available) ...
        halt 503, "Redis unavailable." unless @redis
        key = agent_redis_key(name)
        redis_agent_data = @redis.hmget(key, 'description', 'tools', 'model')
        description = redis_agent_data[0]
        tools_json_string = redis_agent_data[1]
        loaded_model = redis_agent_data[2] || ADK::Agent::DEFAULT_MODEL
        unless description then halt 404, slim(:error_404, locals: { title: "Agent Not Found", message: "Definition for '#{name}' not found." }); end

        is_running = @agents.key?(name)
        @view_agent_data = { name: name, description: description, running: is_running, model: loaded_model }
        configured_tool_names_str = []; begin tools_json_string && configured_tool_names_str = JSON.parse(tools_json_string) rescue []; end

        # --- Include check_workflow_status tool info if available ---
        all_available_tools_list = ADK::ToolRegistry.list_tools
        if ADK::ToolRegistry.find_class(:check_workflow_status) && !configured_tool_names_str.include?("check_workflow_status")
          check_tool_info = all_available_tools_list.find { |t| t[:name] == :check_workflow_status }
          # Add it implicitly for display if not explicitly configured? Or rely on registry listing? Let's rely on registry.
        end
        # ---

        @configured_tool_info = configured_tool_names_str.map { |tn|
           all_available_tools_list.find { |t| t[:name].to_s == tn }
        }.compact
        logger.debug("Agent '#{name}' configured tool info: #{@configured_tool_info.inspect}")


        if is_running
           @agent = @agents[name]; @view_agent_data[:model] = @agent.model_name
        else
           # Create a temporary agent instance for display purposes
           temp_agent_for_view = ADK::Agent.new(name: name, description: description, model_name: loaded_model)
           configured_tool_names_str.map(&:to_sym).each { |tool_name|
              inst = ADK::ToolRegistry.create_instance(tool_name);
              if inst then temp_agent_for_view.add_tool(inst); else logger.warn("Tool '#{tool_name}' not found for display."); end
           }
           @agent = temp_agent_for_view # Assign for view, but it's not in @agents
        end
        slim :agent
      end

      # --- Agent Inline Editing Routes (Unchanged) ---
      get '/agents/:name/edit/:field' do |name, field|
        # ... (unchanged route) ...
      end
      get '/agents/:name/display/:field' do |name, field|
         # ... (unchanged route) ...
      end
      put '/agents/:name/update/:field' do |name, field|
        # ... (unchanged route) ...
      end

      # --- Agent Runtime Routes ---
      post '/agents/:name/start' do
        # ... (start logic unchanged) ...
      end
      post '/agents/:name/start/detail' do
        # ... (start detail logic unchanged) ...
      end
      post '/agents/:name/stop' do
        # ... (stop logic unchanged) ...
      end
      post '/agents/:name/stop/detail' do
        # ... (stop detail logic unchanged) ...
      end

      # --- Agent Interaction Routes (REFACTORED for Session) ---
      get '/agents/:name/chat' do |name|
         # ... (chat GET logic unchanged) ...
      end
      post '/agents/:name/chat' do |name|
          # ... (chat POST logic uses updated format helper, otherwise unchanged) ...
          content_type :html
          @agent = @agents[name] # Agent must be running
          user_message = params['message']&.strip
          session_id = session[:adk_session_id] # Get session ID from Sinatra session

          locals = { user_message: user_message || "[Empty Message]", agent_result: nil, agent_name: @agent ? @agent.name : name }

          unless session_id && (adk_session = @session_service.get_session(session_id: session_id))
            logger.error("Chat POST Error: Missing or invalid session ID (#{session_id}). Redirecting.")
            session.delete(:adk_session_id); redirect "/agents/#{name}/chat"
          end
          unless @agent
            locals[:agent_result] = { status: :error, error_message: "[Error: Agent '#{name}' is not running.]" }
            halt 400, slim(:_chat_message, layout: false, locals: locals)
          end
          if user_message.nil? || user_message.empty?
            locals[:agent_result] = { status: :error, error_message: "[Error: Message cannot be empty.]" }
            halt 400, slim(:_chat_message, layout: false, locals: locals)
          end

          begin
            logger.info("Agent '#{name}' processing chat in session '#{session_id}': #{user_message}")
            final_event_or_error = @agent.run_task(session_id: session_id, user_input: user_message, session_service: @session_service)
            logger.info("Agent '#{name}' task processing complete. Final result: #{final_event_or_error.inspect}")
            # Pass the raw event or error hash, the partial handles formatting based on content
            locals[:agent_result] = final_event_or_error
            slim :_chat_message, layout: false, locals: locals
          rescue => e
            logger.error("Error processing chat for agent #{name}: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
            locals[:agent_result] = { status: :error, error_message: "[Internal Error executing task: #{e.message}]" }
            halt 500, slim(:_chat_message, layout: false, locals: locals)
          end
      end

      # Execute Agent Task Directly (JSON Input) - REFACTORED for Session & Context
      post '/agents/:name/execute' do
        name = params[:name]; content_type :html
        agent = @agents[name] # Agent must be running

        html_error = lambda do |message, code = 400|
                       halt code, format_execution_result_html({ status: :error, error_message: message }); end

        html_error.call("Error: Agent '#{name}' not found or not running.", 400) unless agent
        json_string = params['task_json'];
        html_error.call("Error: Missing 'task_json' data.", 400) unless json_string && !json_string.empty?
        task = nil;
        begin data = JSON.parse(json_string); task = data['task'];
              html_error.call("Error: Missing 'task' key in JSON.", 400) unless task;
        rescue JSON::ParserError => e; logger.error("Invalid JSON: #{e.message}"); html_error.call("Error: Invalid JSON format.", 400); end

        temp_session = nil # Define outside begin for ensure block
        begin
          logger.info("Agent '#{name}' executing direct task: #{task}")
          # Create temporary session using the IN-MEMORY service for direct execution
          temp_session = @session_service.create_session(app_name: name, user_id: 'direct_execute')
          # Call run_task with session context
          final_event_or_error = agent.run_task(session_id: temp_session.id, user_input: task, session_service: @session_service)
          logger.info("Agent '#{name}' direct execution result: #{final_event_or_error.inspect}")

          # Extract content hash directly from event for formatting
          content_to_display = final_event_or_error.is_a?(ADK::Event) ? final_event_or_error.content : final_event_or_error

          format_execution_result_html(content_to_display) # Format the content hash

        rescue => e
          logger.error "Error during direct agent execution for '#{name}': #{e.message}\n#{e.backtrace.join("\n")}"
          html_error.call("Error: Internal server error during task execution: #{e.message}", 500)
        ensure
          # Clean up temporary session
          @session_service.delete_session(session_id: temp_session.id) if temp_session
        end
      end

      # --- Tool Routes ---
      get('/tools') { @tools_list = ADK::ToolRegistry.list_tools; slim :tools }
      get('/tools/:name') { |n|
        @tool = ADK::ToolRegistry.create_instance(n.to_sym);
        if @tool then slim :tool else halt 404, slim(:error_404, locals: { title: "Tool Not Found", message: "Tool '#{n}' not found." }); end
      }
      # Updated Tool Execute Route
      post '/tools/:name/execute' do |n|
        content_type :html; tool_name_sym = n.to_sym; logger.info("Executing Tool '#{n}' via form")
        # params.delete('_csrf') # Remove if using CSRF protection
        submitted_params = params.reject { |k, _| ['splat', 'captures', 'name'].include?(k) }
        logger.debug("Params: #{submitted_params.inspect}")
        tool = ADK::ToolRegistry.create_instance(tool_name_sym)
        unless tool; err_msg = "Tool '#{Rack::Utils.escape_html(n)}' not found."; halt 404, format_execution_result_html({ status: :error, error_message: err_msg }); end

        # --- Create dummy context for direct execution ---
        dummy_context = ADK::ToolContext.new(session_id: "web_direct_#{SecureRandom.hex(4)}", user_id: 'web_user', app_name: 'web_tool_exec')

        begin
          # Convert string keys from form to symbols for tool execute
          symbolized_params = submitted_params.transform_keys(&:to_sym)
          logger.info("Attempting tool.execute: #{symbolized_params.inspect}")
          # --- Pass context ---
          result_hash = tool.execute(symbolized_params, dummy_context) # <-- PASS CONTEXT

          logger.info("Tool execute returned: #{result_hash.inspect}")
          format_execution_result_html(result_hash) # Use helper

        rescue ADK::Error, ArgumentError => e;
          logger.warn("Tool Error: #{e.message}");
          format_execution_result_html({ status: :error, error_message: e.message });
        rescue StandardError => e;
          logger.error("Unexpected Tool Error: #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}");
          format_execution_result_html({ status: :error, error_message: "Unexpected error: #{e.message}" }); end
      end


      # --- API Endpoints (Unchanged) ---
      get('/api/agents') {
        # ... (unchanged route) ...
      }
      get('/api/tools') { content_type :json; json tools: ADK::ToolRegistry.list_tools } # Ensure check_workflow_status shows up

    end # End App class
  end # End Web module
end # End ADK module
```
You are absolutely correct! My apologies for the incomplete response. Let's pick up right where we left off, starting with the remaining Web UI view updates and then covering the necessary spec tests and documentation details.

---

**(Continuing from previous response...)**

**11. Update Web UI Views (Continued)**

*   **File:** `lib/adk/web/views/agent.slim`
*   **Action:** No direct changes needed. This view uses the `format_execution_result_html` helper within the `#task-result` div. The helper has already been updated to handle the `:pending` status, so results from long-running tasks initiated via the "Execute Task (JSON Input)" section will display correctly.

    ```slim
    / File: lib/adk/web/views/agent.slim
    / NO CHANGES NEEDED HERE - Relies on updated format_execution_result_html helper

    .content
      / --- Pass @view_agent_data as agent_data local ---
      div(id="agent-name-display")
        == slim :_display_agent_name, locals: { agent_data: @view_agent_data }

      / --- Pass @view_agent_data as agent_data local ---
      div(id="agent-description-display" hx-swap="innerHTML")
        == slim :_display_agent_description, locals: { agent_data: @view_agent_data }

      / --- Pass @view_agent_data as agent_data local ---
      div(id="agent-model-display" hx-swap="innerHTML")
        == slim :_display_agent_model, locals: { agent_data: @view_agent_data }

    / Status Box
    .box.mb-5
      h2.title.is-4 Status & Control
      / This already passes locals correctly
      == slim :_agent_status_controls, locals: { agent_data: @view_agent_data }

    / Execute Task box
    .box.mb-5
      h2.title.is-4 Execute Task (JSON Input)
      form( hx-post="/agents/#{@view_agent_data[:name]}/execute"
            hx-target="#task-result"
            hx-swap="innerHTML"
            hx-indicator="#task-spinner" )
        .field
          label.label Task (JSON Format: {"task": "your task description"})
          .control
            textarea.textarea(name="task_json" placeholder='{"task": "Describe your task here..."}' required=true rows="3")
        .field.is-grouped.is-grouped-right
          .control
            span.icon.is-small.htmx-indicator#task-spinner style="margin-right: 8px; vertical-align: middle;"
              i.fas.fa-spinner.fa-spin
          .control
            button.button( type="button"
                           _='on click put "<p class=\"has-text-grey\">Task results will appear here.</p>" into #task-result' )
              span.icon.is-small
                i.fas.fa-eraser
              span Clear Result
          .control
            button.button.is-primary(type="submit" id="execute-task-button" disabled=!@view_agent_data[:running])
              span.icon.is-small
                i.fas.fa-play-circle
              span Execute (Requires Start)

      #task-result.mt-4
        p.has-text-grey Task results will appear here.

    / --- Tools Container ---
    div(id="agent-tools-display" hx-swap="innerHTML")
      / --- Pass @view_agent_data and @configured_tool_info as locals ---
      == slim :_display_agent_tools, locals: { agent_data: @view_agent_data, configured_tools: @configured_tool_info }

    / Link back to the main agents list
    .mt-4
      a.button(href="/agents") ← Back to Agents List

    ```

*   **File:** `lib/adk/web/views/tool.slim`
*   **Action:** No direct changes needed. This view uses the `format_execution_result_html` helper within the `#tool-result` div. The helper has already been updated to handle the `:pending` status, so results from long-running tools initiated via the "Try it out" section will display correctly.

    ```slim
    / File: lib/adk/web/views/tool.slim
    / NO CHANGES NEEDED HERE - Relies on updated format_execution_result_html helper

    .content
      h1.title = @tool.name
      p.subtitle = @tool.description

    .box
      h2.title.is-4 Parameters
      table.table
        thead
          tr
            th Name
            th Type
            th Required
            th Description
        tbody
          - if @tool.parameters.empty?
            tr
              td(colspan="4") This tool takes no parameters.
          - else
            - @tool.parameters.each do |name, info|
              tr
                td = name
                td = info[:type]
                td = info[:required] ? 'Yes' : 'No'
                td = info[:description]

    .box
      h2.title.is-4 Try it out
      form( hx-post="/tools/#{@tool.name}/execute" hx-target="#tool-result" hx-swap="innerHTML" hx-indicator="#tool-spinner" )
        - @tool.parameters.each do |name, info|
          .field
            label.label = name
            .control
              input.input(type="text" name=name.to_s placeholder=info[:description] required=info[:required])
        .field.is-grouped.is-grouped-right
          .control
            span.icon.is-small.htmx-indicator#tool-spinner style="margin-right: 8px; vertical-align: middle;"
              i.fas.fa-spinner.fa-spin
          .control
            button.button( type="button"
                           _='on click put "" into #tool-result' )
              span.icon.is-small
                i.fas.fa-eraser
              span Clear Result
          .control
            button.button.is-primary(type="submit")
              span.icon.is-small
                i.fas.fa-play-circle
              span Execute

      #tool-result.mt-4
        / Result will be rendered here by format_execution_result_html

    / Link back to the main tools list
    .mt-4
      a.button(href="/tools") ← Back to Tools List
    ```

**12. Add Spec Tests**

*   **File:** `spec/adk/tools/base_long_running_tool_spec.rb` (New File)

    ```ruby
    # File: spec/adk/tools/base_long_running_tool_spec.rb
    require 'spec_helper'
    require 'temporalio/testing' # Required for mocking Temporal client/errors if needed

    # --- Dummy Workflow Class for Testing ---
    class DummyTemporalWorkflow < Temporalio::Workflow::Definition
      def execute(arg1, context_hash) end # Define execute to match potential signature
    end

    # --- Dummy Tool Implementation ---
    class MyLongRunningTool < ADK::Tools::BaseLongRunningTool
      define_metadata(name: :my_long_runner, description: 'Starts a dummy task', parameters: { input_data: { type: :string, required: true } })

      def temporal_workflow_class; DummyTemporalWorkflow; end
      def temporal_task_queue; 'test-queue'; end
      def prepare_workflow_input(params, context); [params[:input_data], context.to_h]; end # Pass input and context hash
      # Keep default workflow_id generation
    end

    RSpec.describe ADK::Tools::BaseLongRunningTool do
      subject(:tool) { MyLongRunningTool.new }
      let(:params) { { input_data: 'some_value' } }
      let(:session_id) { 'sess_abc' }
      let(:user_id) { 'user_1' }
      let(:app_name) { 'test_app' }
      let(:context) { ADK::ToolContext.new(session_id: session_id, user_id: user_id, app_name: app_name) }
      let(:workflow_id) { "my_long_runner-#{session_id}-#{SecureRandom.uuid}" } # Match default pattern roughly
      let(:mock_temporal_client) { instance_double(Temporalio::Client) }
      let(:mock_workflow_handle) { instance_double(Temporalio::Client::WorkflowHandle, id: workflow_id) }

      before do
        # Stub the global client getter
        allow(ADK).to receive(:temporal_client).and_return(mock_temporal_client)
        # Mock SecureRandom for predictable workflow ID testing if needed
        allow(SecureRandom).to receive(:uuid).and_return('mockuuid')
        @expected_workflow_id = "my_long_runner-#{session_id}-mockuuid"

        # Default successful start_workflow mock
        allow(mock_temporal_client).to receive(:start_workflow)
          .with(
            DummyTemporalWorkflow,
            params[:input_data], # Arg 1 from prepare_workflow_input
            context.to_h,       # Arg 2 from prepare_workflow_input
            id: @expected_workflow_id,
            task_queue: 'test-queue',
            execution_timeout: 3600,
            run_timeout: 3600,
            task_timeout: 60
          ).and_return(mock_workflow_handle)
      end

      it 'requires subclasses to implement temporal_workflow_class' do
        abstract_tool = described_class.new # Cannot instantiate directly, use dummy below
        class AbstractSubclass < ADK::Tools::BaseLongRunningTool; end
        expect { AbstractSubclass.new.send(:temporal_workflow_class) }.to raise_error(NotImplementedError)
      end

      it 'requires subclasses to implement temporal_task_queue' do
         class AbstractSubclass < ADK::Tools::BaseLongRunningTool; end
         expect { AbstractSubclass.new.send(:temporal_task_queue) }.to raise_error(NotImplementedError)
      end

       it 'requires subclasses to implement prepare_workflow_input' do
         class AbstractSubclass < ADK::Tools::BaseLongRunningTool; end
         expect { AbstractSubclass.new.send(:prepare_workflow_input, {}, context) }.to raise_error(NotImplementedError)
       end

      describe '#perform_execution' do
        it 'calls ADK.temporal_client' do
          expect(ADK).to receive(:temporal_client).and_return(mock_temporal_client)
          tool.send(:perform_execution, params, context)
        end

        it 'calls prepare_workflow_input with params and context' do
          expect(tool).to receive(:prepare_workflow_input).with(params, context).and_call_original
          tool.send(:perform_execution, params, context)
        end

        it 'calls generate_workflow_id' do
          expect(tool).to receive(:generate_workflow_id).with(params, context).and_call_original
          tool.send(:perform_execution, params, context)
        end

        it 'calls client.start_workflow with correct class, args, and options' do
          expect(mock_temporal_client).to receive(:start_workflow)
            .with(
              DummyTemporalWorkflow,
              params[:input_data],
              context.to_h,
              id: @expected_workflow_id,
              task_queue: 'test-queue',
              execution_timeout: 3600, run_timeout: 3600, task_timeout: 60
            ).and_return(mock_workflow_handle)
          tool.send(:perform_execution, params, context)
        end

        it 'returns a :pending status hash with the workflow_id on success' do
          result = tool.send(:perform_execution, params, context)
          expect(result).to eq({ status: :pending, workflow_id: @expected_workflow_id })
        end

        context 'when temporal client is not configured' do
          before { allow(ADK).to receive(:temporal_client).and_return(nil) }
          it 'returns an error hash' do
            result = tool.send(:perform_execution, params, context)
            expect(result[:status]).to eq(:error)
            expect(result[:error_message]).to include('Temporal client not configured')
          end
        end

        context 'when start_workflow raises Temporalio::Error::ClientError' do
          before do
             allow(mock_temporal_client).to receive(:start_workflow).and_raise(Temporalio::Error::ClientError, "Connection refused")
          end
          it 'returns an error hash' do
             result = tool.send(:perform_execution, params, context)
             expect(result[:status]).to eq(:error)
             expect(result[:error_message]).to include('Failed to start Temporal Workflow', 'Connection refused')
          end
        end

         context 'when start_workflow raises unexpected StandardError' do
          before do
             allow(mock_temporal_client).to receive(:start_workflow).and_raise(StandardError, "Something unexpected")
          end
          it 'returns an error hash' do
             result = tool.send(:perform_execution, params, context)
             expect(result[:status]).to eq(:error)
             expect(result[:error_message]).to include('Unexpected error starting Temporal Workflow', 'Something unexpected')
          end
        end
      end
    end
    ```

*   **File:** `spec/adk/tools/check_workflow_status_tool_spec.rb` (New File)

    ```ruby
    # File: spec/adk/tools/check_workflow_status_tool_spec.rb
    require 'spec_helper'
    require 'temporalio/testing' # Required for mocking Temporal client/errors/enums

    RSpec.describe ADK::Tools::CheckWorkflowStatusTool do
      subject(:tool) { described_class.new }
      let(:workflow_id) { 'wf-test-123' }
      let(:params) { { workflow_id: workflow_id } }
      let(:context) { ADK::ToolContext.new(session_id: 's', user_id: 'u', app_name: 'a') } # Context needed for execute signature
      let(:mock_temporal_client) { instance_double(Temporalio::Client) }
      let(:mock_workflow_handle) { instance_double(Temporalio::Client::WorkflowHandle) }
      let(:mock_description) { instance_double(Temporalio::Api::Workflow::V1::WorkflowExecutionInfo) } # Use correct type

      before do
        # Stub global client
        allow(ADK).to receive(:temporal_client).and_return(mock_temporal_client)
        # Stub handle lookup
        allow(mock_temporal_client).to receive(:workflow_handle).with(workflow_id).and_return(mock_workflow_handle)
        # Stub description call
        allow(mock_workflow_handle).to receive(:describe).and_return(mock_description)
        # Stub result call (will be overridden in specific contexts)
        allow(mock_workflow_handle).to receive(:result).and_return("Workflow Result")
      end

      it 'has correct metadata' do
        expect(tool.name).to eq(:check_workflow_status)
        expect(tool.parameters).to have_key(:workflow_id)
        expect(tool.parameters[:workflow_id][:required]).to be true
      end

      describe '#perform_execution' do
        context 'when temporal client is not configured' do
           before { allow(ADK).to receive(:temporal_client).and_return(nil) }
           it 'returns an error hash' do
             result = tool.send(:perform_execution, params, context)
             expect(result).to eq({ status: :error, error_message: 'Temporal client not configured. Cannot check workflow status.' })
           end
        end

        context 'when workflow_id is missing' do
          it 'returns an error hash' do
            result = tool.send(:perform_execution, { wrong_param: 'x' }, context)
            expect(result).to eq({ status: :error, error_message: 'Missing required parameter: workflow_id' })
          end
        end

        context 'when workflow is RUNNING' do
          before { allow(mock_description).to receive(:status).and_return(:RUNNING) }
          it 'returns a pending status hash' do
             result = tool.send(:perform_execution, params, context)
             expect(result).to eq({ status: :pending, workflow_id: workflow_id, message: "Task is still running." })
          end
        end

        context 'when workflow is COMPLETED' do
          before do
             allow(mock_description).to receive(:status).and_return(:COMPLETED)
             allow(mock_workflow_handle).to receive(:result).with(timeout: ADK::Tools::CheckWorkflowStatusTool::RESULT_FETCH_TIMEOUT).and_return("Final Success")
          end
          it 'fetches result and returns a success hash' do
             result = tool.send(:perform_execution, params, context)
             expect(result).to eq({ status: :success, result: "Final Success" })
          end
        end

        context 'when workflow is COMPLETED but result fetch times out' do
           before do
             allow(mock_description).to receive(:status).and_return(:COMPLETED)
             allow(mock_workflow_handle).to receive(:result).with(timeout: ADK::Tools::CheckWorkflowStatusTool::RESULT_FETCH_TIMEOUT).and_raise(Timeout::Error)
           end
           it 'returns a pending status hash with a timeout message' do
              result = tool.send(:perform_execution, params, context)
              expect(result[:status]).to eq(:pending)
              expect(result[:workflow_id]).to eq(workflow_id)
              expect(result[:message]).to include("timed out fetching result")
           end
        end

         context 'when workflow is COMPLETED but result fetch fails unexpectedly' do
           before do
             allow(mock_description).to receive(:status).and_return(:COMPLETED)
             allow(mock_workflow_handle).to receive(:result).with(timeout: ADK::Tools::CheckWorkflowStatusTool::RESULT_FETCH_TIMEOUT).and_raise(StandardError, "Fetch failed")
           end
           it 'returns an error hash' do
              result = tool.send(:perform_execution, params, context)
              expect(result[:status]).to eq(:error)
              expect(result[:error_message]).to include("failed to fetch result: StandardError - Fetch failed")
           end
        end

        context 'when workflow is FAILED' do
          let(:workflow_failure) { Temporalio::Error::WorkflowFailure.new("Workflow failed", cause: StandardError.new("Root cause failure")) }
           before do
              allow(mock_description).to receive(:status).and_return(:FAILED)
              # Simulate handle.result raising the failure
              allow(mock_workflow_handle).to receive(:result).and_raise(workflow_failure)
           end
           it 'returns an error hash indicating failure' do
              result = tool.send(:perform_execution, params, context)
              expect(result[:status]).to eq(:error)
              expect(result[:error_message]).to include("Workflow finished with status: failed")
              expect(result[:error_message]).to include("Cause: StandardError - Root cause failure")
           end
        end

        context 'when workflow is CANCELED' do
           before { allow(mock_description).to receive(:status).and_return(:CANCELED) }
           it 'returns an error hash indicating cancellation' do
              # Mock result raising canceled error or just check status string
              allow(mock_workflow_handle).to receive(:result).and_raise(Temporalio::Error::WorkflowFailure.new("Canceled")) # Simulate how failure might present
              result = tool.send(:perform_execution, params, context)
              expect(result[:status]).to eq(:error)
              expect(result[:error_message]).to include("Workflow finished with status: canceled")
           end
        end

        context 'when workflow has unexpected status' do
           before { allow(mock_description).to receive(:status).and_return(:UNKNOWN_STATUS) }
           it 'returns an error hash' do
             result = tool.send(:perform_execution, params, context)
             expect(result[:status]).to eq(:error)
             expect(result[:error_message]).to include("unexpected status: UNKNOWN_STATUS")
           end
        end

        context 'when workflow handle is not found' do
           before { allow(mock_temporal_client).to receive(:workflow_handle).with(workflow_id).and_raise(Temporalio::Error::NotFound.new("Workflow not found")) }
           it 'returns an error hash' do
             result = tool.send(:perform_execution, params, context)
             expect(result[:status]).to eq(:error)
             expect(result[:error_message]).to include("Temporal Workflow ID '#{workflow_id}' not found.")
           end
        end

         context 'when Temporal client interaction fails' do
           before { allow(mock_workflow_handle).to receive(:describe).and_raise(Temporalio::Error::ClientError.new("gRPC error")) }
           it 'returns an error hash' do
             result = tool.send(:perform_execution, params, context)
             expect(result[:status]).to eq(:error)
             expect(result[:error_message]).to include("Error interacting with Temporal", "gRPC error")
           end
         end
      end
    end
    ```

*   **File:** `spec/adk/agent_spec.rb`
*   **Action:** Update tests involving `execute_step` to pass a mock `ToolContext`. Add tests for handling `:pending` results.

    ```ruby
    # File: spec/adk/agent_spec.rb
    require 'spec_helper'

    RSpec.describe ADK::Agent do
      # --- Test Subjects ---
      let(:name) { 'test_agent' }
      let(:description) { 'A test agent' }
      let(:model_name) { 'gemini-test-model' }
      let(:default_model) { ADK::Agent::DEFAULT_MODEL }

      # --- Mocks / Doubles ---
      let(:mock_planner) { instance_double(ADK::Planner, plan: []) } # Default stub
      let(:mock_logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
      let(:mock_session_service) { instance_double(ADK::SessionService::InMemory) }
      let(:session_id) { 'sid-123' }
      let(:user_id) { 'user-test' } # Define user_id
      let(:app_name) { name } # Define app_name
      # --- Mock Session with more details ---
      let(:mock_session) { instance_double(ADK::Session, id: session_id, user_id: user_id, app_name: app_name, events: []) }
      # --- Mock Tool Context ---
      let(:mock_context) { instance_double(ADK::ToolContext, session_id: session_id, user_id: user_id, app_name: app_name, to_h: { session_id: session_id, user_id: user_id, app_name: app_name}) }


      # Tools
      let(:mock_tool_a) { instance_double(ADK::Tool, name: :tool_a) }
      let(:mock_tool_b) { instance_double(ADK::Tool, name: :tool_b) }

      # Results
      let(:success_hash_a) { { status: :success, result: 'Result A' } }
      let(:success_hash_b) { { status: :success, result: 'Result B' } }
      let(:pending_hash) { { status: :pending, workflow_id: 'wf-abc', message: 'Running...' } } # <-- ADDED
      let(:error_hash) { { status: :error, error_message: 'Something failed' } }

      # Events
      let(:user_input) { "Test user input" }
      # ... other event doubles ...

      # --- Agent Instance ---
      let!(:agent) do
        allow(ADK::Planner).to receive(:new).and_return(mock_planner)
        # --- Mock ToolContext creation ---
        allow(ADK::ToolContext).to receive(:new).with(session_id: session_id, user_id: user_id, app_name: app_name).and_return(mock_context)
        described_class.new( name: name, description: description, model_name: model_name, logger: mock_logger )
      end

      # --- General Setup ---
      before do
        allow(mock_tool_a).to receive(:is_a?).with(ADK::Tool).and_return(true)
        allow(mock_tool_b).to receive(:is_a?).with(ADK::Tool).and_return(true)
        allow(mock_session_service).to receive(:get_session).with(session_id: session_id).and_return(mock_session)
        allow(mock_session_service).to receive(:append_event).and_return(true)
        allow(ADK::Event).to receive(:new).and_call_original
        allow(ADK.logger).to receive(:level=) unless RSpec.current_example.metadata[:log_level]
        # ... silence other logger methods ...
      end

      # --- Tests ---

      describe '#initialize' do
        # ... (existing initialize tests) ...
        it 'automatically adds check_workflow_status tool if Temporal is configured' do
          # Simulate temporal client being available
          mock_temporal = instance_double(Temporalio::Client)
          allow(ADK).to receive(:temporal_client).and_return(mock_temporal)
          mock_status_tool = instance_double(ADK::Tools::CheckWorkflowStatusTool, name: :check_workflow_status)
          allow(mock_status_tool).to receive(:is_a?).with(ADK::Tool).and_return(true)
          allow(ADK::ToolRegistry).to receive(:create_instance).with(:check_workflow_status).and_return(mock_status_tool)

          # Re-initialize agent within this context
          allow(ADK::Planner).to receive(:new).and_return(mock_planner)
          agent_with_temporal = described_class.new(name: name, description: description, logger: mock_logger)

          expect(agent_with_temporal.tools.map(&:name)).to include(:check_workflow_status)
        end
      end

      # ... (add_tool, start/stop tests unchanged) ...

      describe '#run_task' do
        before do
          agent.add_tool(mock_tool_a)
          agent.add_tool(mock_tool_b)
        end

        # ... (pre-execution checks unchanged) ...

        context 'successful single-step execution' do
          let(:plan) { [{ tool: :tool_a, params: { p: 1 } }] }

          before do
            agent.start
            allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
            # --- Mock execute to expect context ---
            allow(mock_tool_a).to receive(:execute).with({ p: 1 }, mock_context).and_return(success_hash_a)
          end

          it 'records user, tool request, tool result, and agent events' do
             # Expect 4 events: user, tool_request, tool_result, agent
             expect(mock_session_service).to receive(:append_event).exactly(4).times
             agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
          end

          it 'returns the final agent event with the tool result hash' do # <-- CHANGED: Expect hash
             final_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
             expect(final_event).to be_an(ADK::Event)
             expect(final_event.role).to eq(:agent)
             expect(final_event.content).to eq(success_hash_a) # Content is the result hash now
          end
        end

        context 'successful multi-step execution with injection' do
           let(:plan) { [{ tool: :tool_a, params: { p: 1 } }, { tool: :tool_b, params: { data: '[Result from step 1]' } }] }

           before do
             agent.start
             allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
             # --- Mock execute to expect context ---
             allow(mock_tool_a).to receive(:execute).with({ p: 1 }, mock_context).and_return(success_hash_a)
             allow(mock_tool_b).to receive(:execute).with({ data: 'Result A' }, mock_context).and_return(success_hash_b)
           end

           it 'injects result from step 1 into step 2 params' do
             expect(mock_tool_b).to receive(:execute).with({ data: 'Result A' }, mock_context).and_return(success_hash_b)
             agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
           end

           it 'records events for both steps' do
             # Expect 6 events: user, req_a, res_a, req_b, res_b, agent
             expect(mock_session_service).to receive(:append_event).exactly(6).times
             agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
           end

           it 'returns the final agent event with the result hash of the last step' do # <-- CHANGED: Expect hash
             final_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
             expect(final_event).to be_an(ADK::Event)
             expect(final_event.role).to eq(:agent)
             expect(final_event.content).to eq(success_hash_b) # Content is the result hash
           end
        end

        # --- ADDED: Test for Pending Status ---
        context 'when a step returns a pending status' do
           let(:plan) { [{ tool: :tool_a, params: { p: 1 } }] }

           before do
             agent.start
             allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
             allow(mock_tool_a).to receive(:execute).with({ p: 1 }, mock_context).and_return(pending_hash)
           end

           it 'returns the final agent event with the pending hash as content' do
             final_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
             expect(final_event).to be_an(ADK::Event)
             expect(final_event.role).to eq(:agent)
             expect(final_event.content).to eq(pending_hash)
           end
        end
        # --- END ADDED ---

        # ... (error handling tests largely unchanged, but ensure context is mocked in execute calls if needed) ...
        context 'multi-step execution with error and plan halting' do
            let(:plan) { [{ tool: :tool_a, params: { p: 1 } }, { tool: :tool_b, params: { data: '[Result from step 1]' } }] }

            before do
              agent.start
              allow(mock_planner).to receive(:plan).with(user_input).and_return(plan)
              allow(mock_tool_a).to receive(:execute).with({ p: 1 }, mock_context).and_return(error_hash) # Tool A fails
              # AgentTool B should not be called
              allow(mock_tool_b).not_to receive(:execute)
            end

            it 'stops execution after the failed step' do
              expect(mock_tool_b).not_to receive(:execute)
              agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
            end

            it 'records events up to and including the failed tool result' do
              # Expect 4 events: user, tool_request_a, tool_result_a (error), final agent response (error)
              expect(mock_session_service).to receive(:append_event).exactly(4).times
              agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
            end

            it 'returns the final agent event indicating the error' do
               final_event = agent.run_task(session_id: session_id, user_input: user_input, session_service: mock_session_service)
               expect(final_event).to be_an(ADK::Event)
               expect(final_event.role).to eq(:agent)
               expect(final_event.content).to eq(error_hash) # Final content is the error hash from the failed step
            end
        end

      end
    end

    ```

*   **File:** `spec/adk/tool_spec.rb` (If it exists, or create it)
*   **Action:** Add tests for context passing in the base `Tool`.

    ```ruby
    # File: spec/adk/tool_spec.rb
    require 'spec_helper'

    # --- Dummy Tool for Testing Base Class ---
    class DummyTestTool < ADK::Tool
      define_metadata(name: :dummy, description: 'A dummy tool', parameters: { req: { required: true } })

      # Store received args for inspection
      attr_reader :received_params, :received_context

      def perform_execution(params, context)
        @received_params = params
        @received_context = context
        { status: :success, result: 'dummy success' }
      end
    end

    RSpec.describe ADK::Tool do
      let(:tool_instance) { DummyTestTool.new }
      let(:params) { { req: 'value' } }
      let(:context) { ADK::ToolContext.new(session_id: 's', user_id: 'u', app_name: 'a') }

      describe '#execute' do
        it 'validates parameters before calling perform_execution' do
          expect(tool_instance).to receive(:validate_params).with(params).ordered.and_call_original
          expect(tool_instance).to receive(:perform_execution).with(params, context).ordered.and_call_original
          tool_instance.execute(params, context)
        end

        it 'passes parameters and context to perform_execution' do
          tool_instance.execute(params, context)
          expect(tool_instance.received_params).to eq(params)
          expect(tool_instance.received_context).to eq(context)
        end

        it 'raises error if required parameters are missing' do
          expect { tool_instance.execute({}, context) }.to raise_error(ADK::Error, /Missing required parameters: req/)
        end

        it 'handles context being nil (for potential backward compatibility)' do
           expect { tool_instance.execute(params, nil) }.not_to raise_error
           expect(tool_instance.received_context).to be_nil
        end
      end

      describe '#validate_params' do
         # Add more specific tests for validate_params if needed
         it 'does not raise error if required parameters are present' do
           expect { tool_instance.validate_params(req: 'val') }.not_to raise_error
         end
      end

      describe '.define_metadata and .register_tool_class' do
         # Test metadata storage and registration side-effects
         it 'stores metadata correctly' do
           expect(DummyTestTool.tool_name).to eq(:dummy)
           expect(DummyTestTool.description).to eq('A dummy tool')
           expect(DummyTestTool.parameters_definition).to eq({ req: { required: true } })
         end

         it 'registers the tool class with the registry' do
            # Ensure registry is clean or mock it
            allow(ADK::ToolRegistry).to receive(:register)
            # Force re-evaluation if class loading order matters
            # Reloading the class definition might be needed in complex scenarios
            # For simplicity, assume registration happened during class load
            expect(ADK::ToolRegistry).to have_received(:register).with(:dummy, DummyTestTool)
         end
      end
    end
    ```

**13. Documentation**

*   **File:** `README.md`
    *   Add `temporalio` to the dependency list.
    *   Briefly mention the new capability for long-running tasks under "Features" or a new "Advanced Features" section.
    *   Link to the new detailed documentation page (`docs/long_running_tools.md`).
    *   Mention the requirement for a running Temporal Server and separate Temporal Workers.
    *   Update configuration section to include Temporal ENV variables (`TEMPORAL_ADDRESS`, `TEMPORAL_NAMESPACE`).
*   **File:** `docs/long_running_tools.md` (New File)
    *   **Title:** Handling Long-Running Tasks with Temporal
    *   **Introduction:** Explain the problem of long-running synchronous tools and how the Temporal integration provides a solution for asynchronous execution. Mention the start/check pattern.
    *   **Prerequisites:**
        *   Running Temporal Server (link to Temporal docs for setup: `temporal server start-dev`).
        *   `temporalio` gem added to the project.
        *   Configured ADK Temporal client (via `ADK.configure` or ENV vars).
    *   **Implementing the Temporal Logic:**
        *   Explain that the core task logic lives in a standard Temporal Workflow and potentially Activities.
        *   Provide a simple Ruby example of a Temporal Workflow class (e.g., `MyLongTaskWorkflow`) that accepts arguments (including context), performs work (e.g., `sleep`, calls Activities), and returns a result or raises an error. Show how to access the ADK context passed as an argument.
        *   Explain that this workflow/activity code needs to be registered with and run by a separate Temporal Worker process (provide a minimal `worker.rb` example).
    *   **Implementing the ADK Tool (`BaseLongRunningTool`):**
        *   Explain the purpose of `ADK::Tools::BaseLongRunningTool`.
        *   Show how to subclass it.
        *   Detail the required methods to override: `temporal_workflow_class`, `temporal_task_queue`, `prepare_workflow_input`.
        *   Explain optional overrides: `temporal_workflow_options`, `generate_workflow_id`.
        *   Provide a complete `MyLongTaskTool < ADK::Tools::BaseLongRunningTool` example corresponding to the Temporal Workflow example.
    *   **Using the Tools in an Agent:**
        *   Show how to register *both* `MyLongTaskTool` and the built-in `:check_workflow_status` tool with an `ADK::Agent`.
        *   Explain that the agent's planner needs to be instructed (via prompt engineering) to:
            1.  Call `MyLongTaskTool` with the initial input.
            2.  Receive the `{ status: :pending, workflow_id: ... }` result.
            3.  Store the `workflow_id`.
            4.  Periodically (or when asked) call `:check_workflow_status` with the stored `workflow_id`.
            5.  Continue polling until the status is `:success` or `:error`.
            6.  Present the final `:result` or `:error_message` to the user.
        *   Provide an example agent prompt incorporating this logic.
    *   **CLI and Web UI:** Explain how the `:pending` status is displayed in the CLI output and Web UI execution results, including the `workflow_id`.
    *   **Example Scenario:** Walk through a complete example: User asks agent -> Agent plans to use `MyLongTaskTool` -> Tool returns pending + ID -> Agent plans to use `check_workflow_status` -> Tool returns pending -> Agent waits/polls -> Tool returns success + result -> Agent presents result.

This completes the detailed plan and code changes required to implement long-running tool support using Temporal in `adk-ruby`. Remember to run `bundle install` after updating the `Gemfile` and `gemspec`.