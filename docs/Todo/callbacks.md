# ADK Callbacks Implementation Plan

## Current Progress (Updated)

### Completed:
- ✅ Created `lib/adk/callbacks/callback_context.rb` - Core context object that's passed to callbacks
- ✅ Updated `lib/adk/tool_context.rb` - Added state management and other callback-related functionality
- ✅ Created `spec/adk/callbacks_spec.rb` - Test file for callback functionality
- ✅ Created detailed implementation plan in `docs/Todo/callbacks_implementation_plan.md`

### In Progress:
- ⏳ Adding callback methods to `ADK::AgentDefinition` and `ADK::Agent`
- ⏳ Integrating callback execution points in `run_task` and `execute_step` methods

### Next Steps:
1. Update `ADK::Agent#run_task` method to support before/after agent callbacks
2. Update `execute_plan` to pass invocation_id to execute_step
3. Update `execute_step` with before/after tool callbacks support
4. Implement before/after model callbacks around planner calls
5. Complete the test coverage in `callbacks_spec.rb`
6. Create user documentation in `docs/callbacks.md`

See the detailed implementation plan in `docs/Todo/callbacks_implementation_plan.md`.

---

Here's a detailed plan for implementing this callback system in `adk-ruby`:

## Implementation Plan: ADK Callbacks

**I. Define Callback Context Objects (New Files/Modules)**

1.  **`lib/adk/callbacks/callback_context.rb`**:
    *   Define `ADK::Callbacks::CallbackContext`.
    *   **Attributes**:
        *   `agent_name` (Symbol): Name of the agent instance.
        *   `invocation_id` (String): A unique ID for the current `run_task` invocation (e.g., `SecureRandom.uuid` generated at the start of `run_task`).
        *   `session_id` (String)
        *   `user_id` (String)
        *   `app_name` (String)
        *   `session_service` (ADK::SessionService::Base instance)
        *   `logger` (ADK.logger)
        *   `_pending_state_delta` (Hash): Internal, for accumulating state changes.
    *   **Methods**:
        *   `initialize(...)`: Sets attributes.
        *   `state_get(key)`:
            *   Delegates to `session_service.get_state(session_id: @session_id, key: key)`.
            *   Logs access.
        *   `state_set(key, value)`:
            *   Validates `value` is serializable (reuse existing logic if possible).
            *   Adds `{ key => value }` to `@_pending_state_delta`.
            *   Logs the set operation.
        *   `state_update(hash_to_merge)`:
            *   Validates all values in `hash_to_merge` are serializable.
            *   Merges `hash_to_merge` into `@_pending_state_delta`.
            *   Logs the update.
        *   `pending_state_delta`: Returns a copy of `@_pending_state_delta`.
        *   `clear_pending_state_delta!`: Resets `@_pending_state_delta` to an empty hash.

2.  **Modify `lib/adk/tool_context.rb`**:
    *   Add attributes:
        *   `session_service` (ADK::SessionService::Base instance)
        *   `logger` (ADK.logger)
        *   `_pending_state_delta` (Hash)
        *   `invocation_id` (String) - to be passed from Agent.
    *   Update `initialize` to accept and store these new attributes.
    *   Add methods: `state_get(key)`, `state_set(key, value)`, `state_update(hash_to_merge)`, `pending_state_delta`, `clear_pending_state_delta!` with similar logic to `CallbackContext`.

3.  **`lib/adk/callbacks/planner_callback_context.rb`** (Optional, can reuse `CallbackContext` initially):
    *   Could inherit from `CallbackContext` or be distinct.
    *   May hold additional planner-specific information later if needed. For now, `CallbackContext` is likely sufficient.

**II. Update `ADK::AgentDefinition` (`lib/adk/agent.rb`)**

1.  **Add Callback Attributes**:
    *   In `ADK::AgentDefinition#initialize`, add instance variables for each callback type, defaulting to `nil`:
        *   `@before_agent_callback`
        *   `@after_agent_callback`
        *   `@before_model_callback`
        *   `@after_model_callback`
        *   `@before_tool_callback`
        *   `@after_tool_callback`
    *   Add `attr_reader` for these.

2.  **Update `ADK::AgentDefinition::DefinitionProxy`**:
    *   Add DSL methods for each callback (e.g., `before_agent_callback(&block)`, `after_model_callback(&block)`).
    *   These methods will assign the provided block (Proc) to the corresponding instance variable on the `@definition` object.
    *   Validate that the argument is a Proc or nil.

3.  **Update `ADK::AgentDefinition#to_h`**:
    *   Include callback attributes. Since Procs aren't directly serializable to JSON, represent them as a string like `'<Proc>'` if set, or `nil`.

4.  **Update `ADK::AgentDefinition.from_hash`**:
    *   When reconstructing from a hash, these callback attributes will be initialized to `nil` because the Procs cannot be recreated from the `'<Proc>'` string.
    *   **Note:** This means callbacks defined via the DSL and then saved/loaded via Redis won't be active unless re-associated programmatically after loading. This is a limitation to acknowledge. `GlobalDefinitionRegistry` storing the *actual* definition *objects* (with Procs) becomes more crucial if these are needed after a store load.

**III. Update `ADK::Agent#initialize` (`lib/adk/agent.rb`)**

1.  Copy the callback Procs from the `definition` object to instance variables on the `ADK::Agent` instance (e.g., `@before_agent_callback = definition.before_agent_callback`).

**IV. Integrate Callbacks into Core Logic**

1.  **`ADK::Agent#run_task` (`lib/adk/agent.rb`)**:
    *   **`before_agent_callback`**:
        *   At the beginning (after session retrieval, before planning).
        *   Generate an `invocation_id = SecureRandom.uuid`.
        *   Create `ADK::Callbacks::CallbackContext`.
        *   If `@before_agent_callback` (the Proc) exists:
            *   Call it: `override_content = @before_agent_callback.call(callback_context)`.
            *   Handle exceptions from the callback (log, create error event).
            *   If `override_content` is a Hash:
                *   Create `final_event = ADK::Event.new(role: :agent, content: override_content, state_delta: callback_context.pending_state_delta)`.
                *   Append `final_event` to session.
                *   Return `final_event`.
            *   Merge `callback_context.pending_state_delta` into the *next* event to be logged (e.g., the user input event, or a dedicated callback-effect event).
    *   **`after_agent_callback`**:
        *   Just before returning the `final_agent_event`.
        *   Create `ADK::Callbacks::CallbackContext` (can reuse or recreate with the same `invocation_id`).
        *   If `@after_agent_callback` exists:
            *   Call it: `modified_content = @after_agent_callback.call(callback_context, final_agent_event.content.dup)`. (Pass content and allow modification).
            *   Handle exceptions.
            *   If `modified_content` is a Hash, update `final_agent_event.content = modified_content`.
            *   Merge `callback_context.pending_state_delta` into `final_agent_event.state_delta`.

2.  **`ADK::Planner#plan` (`lib/adk/planner.rb`)**:
    *   Needs access to the agent's `@before_model_callback` and `@after_model_callback` Procs. This might mean the planner needs to be more tightly coupled with the agent instance or these callbacks are passed differently. A simple way is for `Agent` to pass them to `Planner#plan` if they exist.
    *   Alternatively, the `Agent` calls these callbacks *around* its call to `planner.plan`. This keeps `Planner` focused on planning. Let's go with this: Agent orchestrates model callbacks.
    *   **In `ADK::Agent#run_task`, around the `plan = @planner.plan(user_input)` call:**
        *   **`before_model_callback`**:
            *   Create `PlannerCallbackContext` (or reuse `CallbackContext`).
            *   `llm_request_params = { prompt: ..., model_config: ... }` (whatever planner would send).
            *   If `@before_model_callback` exists: `override_plan = @before_model_callback.call(context, llm_request_params)`.
            *   If `override_plan` (a plan Hash) is returned, use it as `plan` and skip calling `@planner.plan`.
            *   Merge `context.pending_state_delta` into the event being logged for this planning step.
        *   **(Actual `@planner.plan` call if not skipped)**
        *   **`after_model_callback`**:
            *   If `@after_model_callback` exists: `modified_plan = @after_model_callback.call(context, plan.dup)`.
            *   If `modified_plan` is returned, use it as `plan`.
            *   Merge `context.pending_state_delta`.

3.  **`ADK::Agent#execute_step` (`lib/adk/agent.rb`)**:
    *   **`before_tool_callback`**:
        *   Before `tool_instance.execute`.
        *   Create `ADK::ToolContext` (pass `invocation_id`, `session_service` from the current `run_task`).
        *   If `@before_tool_callback` exists: `override_result = @before_tool_callback.call(tool_instance, params.dup, tool_context)`.
        *   If `override_result` (a tool result Hash like `{status: :success, ...}`) is returned:
            *   Use this as `result_hash`.
            *   Log a tool request event and a tool result event (with `override_result` and `tool_context.pending_state_delta`).
            *   Skip calling `tool_instance.execute`.
        *   Else (if callback returned nil): proceed to `tool_instance.execute`. Merge `tool_context.pending_state_delta` into the `Tool Request Event`'s `state_delta`.
    *   **`after_tool_callback`**:
        *   After `tool_instance.execute` returns `result_hash`.
        *   Create/reuse `ADK::ToolContext`.
        *   If `@after_tool_callback` exists: `modified_result = @after_tool_callback.call(tool_instance, params.dup, tool_context, result_hash.dup)`.
        *   If `modified_result` (a tool result Hash) is returned, use it as `result_hash`.
        *   Merge `tool_context.pending_state_delta` into the `Tool Result Event`'s `state_delta`.

**V. General Error Handling for Callbacks**

*   Wrap each callback invocation in a `begin...rescue StandardError => e` block.
*   Inside the rescue:
    *   Log the error thoroughly: `ADK.logger.error("Error in #{callback_name}: #{e.message}\n#{e.backtrace.join("\n")}")`.
    *   **For `before_*` callbacks that can skip steps**: If a callback errors, the default ADK operation it was meant to precede should *not* occur. The agent should treat this as a failure of that step and generate an appropriate error event.
        *   Example: If `before_model_callback` raises an error, the `planner.plan` call is skipped, and an error event related to planning failure (due to callback error) is generated.
    *   **For `after_*` callbacks**: If an `after_*` callback errors, the original result (from the LLM or tool, before the callback was called) should be used. The error is logged, but the main flow continues with the pre-callback data.
    *   **`before_agent_callback` / `after_agent_callback` errors**: These are critical. An error in `before_agent_callback` should prevent the agent's main logic from running and result in an error response for the `run_task`. An error in `after_agent_callback` should log the error but still attempt to return the agent's computed result.

**VI. Documentation and Testing**

1.  **Documentation**:
    *   Create a new markdown file (`public/docs/advanced/callbacks.md` or similar).
    *   Explain the concept, purpose, and types of callbacks.
    *   Detail the signature of each callback type and the context objects they receive.
    *   Explain the return value mechanism (`nil` vs. specific object) for controlling flow.
    *   Provide Ruby examples for each callback type.
    *   Discuss best practices and error handling.
2.  **RSpec Tests**:
    *   Create `spec/adk/callbacks_spec.rb` (or similar).
    *   Test `CallbackContext` and `ToolContext` enhancements.
    *   For `ADK::Agent`:
        *   Test that each callback is invoked at the correct lifecycle point.
        *   Test the control flow:
            *   Callback returns `nil` -> default behavior proceeds.
            *   Callback returns override object -> default behavior is skipped/result is replaced.
        *   Test state modifications via context objects are correctly reflected in subsequent events or session state.
        *   Test error handling within callbacks (agent continues gracefully or reports error as designed).
    *   For `ADK::Planner`: Test integration of model callbacks (if agent doesn't handle them directly around the planner call).

This plan provides a robust foundation. The most complex parts will be the exact interaction points within `ADK::Agent` and `ADK::Planner` and ensuring state changes from callbacks are correctly managed and persisted.

I will now proceed to implement changes in `lib/adk/agent.rb` as the primary file for agent and tool callbacks, and `lib/adk/planner.rb` for model callbacks, incorporating the context objects. Given the scope, I'll focus on the structural changes and callback invocation points. The context objects might be initially defined within `agent.rb` or `tool_context.rb` for brevity in this response, with a view to potentially moving them to `lib/adk/callbacks/` later.Okay, this is a substantial and excellent feature addition. Implementing a callback system will significantly increase the extensibility and introspection capabilities of the ADK.

Here's a comprehensive plan to implement the callback system in `adk-ruby`, focusing on the core changes needed in `ADK::AgentDefinition`, `ADK::Agent`, `ADK::Planner`, and the new context objects.

**Overall Strategy:**

1.  **Define Context Objects**: Create `CallbackContext` and enhance `ToolContext`.
2.  **Extend `AgentDefinition`**: Add DSL methods and storage for callback Procs.
3.  **Modify `Agent`**:
    *   Store callback Procs on agent instances.
    *   Integrate `before_agent_callback` and `after_agent_callback` in `run_task`.
    *   Integrate `before_model_callback` and `after_model_callback` around the planner call in `run_task`.
    *   Integrate `before_tool_callback` and `after_tool_callback` in `execute_step`.
4.  **Refine State Management**: Ensure state changes made via context objects are captured.
5.  **Error Handling**: Implement error catching for user-defined callbacks.

---

**I. New Directory and Context Object Definitions**

We'll create a new directory `lib/adk/callbacks/` for callback-related classes.

**`lib/adk/callbacks/callback_context.rb`**
(This will be a new file)

```ruby
# File: lib/adk/callbacks/callback_context.rb
# frozen_string_literal: true

require 'securerandom'
require_relative '../session_service/base' # For type hinting if used
require_relative '../logger' # For ADK.logger

module ADK
  module Callbacks
    # Context object passed to agent lifecycle and model interaction callbacks.
    class CallbackContext
      attr_reader :agent_name, :invocation_id, :session_id, :user_id, :app_name, :session_service, :logger
      attr_reader :pending_state_delta # Expose for potential inspection

      # @param agent_name [Symbol]
      # @param invocation_id [String]
      # @param session_id [String]
      # @param user_id [String]
      # @param app_name [String]
      # @param session_service [ADK::SessionService::Base]
      # @param logger [Logger]
      def initialize(agent_name:, invocation_id:, session_id:, user_id:, app_name:, session_service:, logger: ADK.logger)
        @agent_name = agent_name
        @invocation_id = invocation_id
        @session_id = session_id
        @user_id = user_id
        @app_name = app_name
        @session_service = session_service
        @logger = logger
        @_pending_state_delta = {} # Internal mutable hash
        freeze # Make core attributes immutable, but allow _pending_state_delta to be modified by methods
      end

      # Retrieves a value from the session state.
      # Prefixed keys (user:, app:, temp:) are handled by the session service if supported.
      def state_get(key)
        # logger.debug { "[CallbackContext] state_get for key: #{key} in session: #{@session_id}" }
        @session_service.get_state(session_id: @session_id, key: key)
      rescue => e
        logger.error { "[CallbackContext] Error in state_get for key '#{key}': #{e.message}" }
        nil
      end

      # Sets a value in the pending state delta. This change will be applied
      # to the session state by the ADK framework after the callback completes.
      # Prefixed keys are intended to be handled by session_service when delta is applied.
      def state_set(key, value)
        # Basic serializability check can be added here if desired,
        # or rely on SessionService to handle it when applying delta.
        # For simplicity, we'll assume values are appropriate for now.
        # logger.debug { "[CallbackContext] state_set for key: #{key} to value: #{value.inspect} (pending)" }
        @_pending_state_delta[key.to_sym] = value
      end

      # Merges a hash into the pending state delta.
      def state_update(hash_to_merge)
        unless hash_to_merge.is_a?(Hash)
          logger.warn { "[CallbackContext] state_update called with non-hash: #{hash_to_merge.class}" }
          return
        end
        # logger.debug { "[CallbackContext] state_update with hash: #{hash_to_merge.inspect} (pending)" }
        @_pending_state_delta.merge!(hash_to_merge.transform_keys(&:to_sym))
      end

      # Clears any accumulated pending state changes within this context instance.
      def clear_pending_state_delta!
        @_pending_state_delta = {}
      end
    end
  end
end
```

**Modify `lib/adk/tool_context.rb`**

```ruby
# File: lib/adk/tool_context.rb
# frozen_string_literal: true

require_relative 'callbacks/callback_context' # For pending_state_delta logic consistency

module ADK
  # Provides contextual information to ADK::Tool#perform_execution
  # Includes session details and a reference to the agent's tool registry.
  # Read-only for core attributes, state modification via methods.
  class ToolContext
    attr_reader :session_id, :user_id, :app_name, :tool_registry, :session_service, :logger, :invocation_id
    attr_reader :pending_state_delta # Expose for potential inspection

    # @param session_id [String] The ID of the current session.
    # @param user_id [String] The user ID associated with the session.
    # @param app_name [String] The application/agent name associated with the session.
    # @param tool_registry [ADK::ToolRegistry] The tool registry instance of the agent executing the tool.
    # @param session_service [ADK::SessionService::Base, nil] The session service instance.
    # @param logger [Logger, nil] The logger instance.
    # @param invocation_id [String, nil] The ID of the current agent invocation.
    def initialize(session_id:, user_id:, app_name:, tool_registry: nil, session_service: nil, logger: ADK.logger, invocation_id: nil)
      @session_id = session_id
      @user_id = user_id
      @app_name = app_name
      @tool_registry = tool_registry
      @session_service = session_service
      @logger = logger
      @invocation_id = invocation_id
      @_pending_state_delta = {}
      # Freeze core attributes, allow _pending_state_delta modification via methods
      # Note: A full freeze here would prevent @_pending_state_delta mutation.
      # We achieve effective immutability of main attrs by not providing setters.
    end

    # Retrieves a value from the session state via the session_service.
    def state_get(key)
      unless @session_service
        # logger.warn { "[ToolContext] state_get called but no session_service available." }
        return nil
      end
      # logger.debug { "[ToolContext] state_get for key: #{key} in session: #{@session_id}" }
      @session_service.get_state(session_id: @session_id, key: key)
    rescue => e
      logger.error { "[ToolContext] Error in state_get for key '#{key}': #{e.message}" }
      nil
    end

    # Sets a value in the pending state delta for this context.
    def state_set(key, value)
      # logger.debug { "[ToolContext] state_set for key: #{key} to value: #{value.inspect} (pending)" }
      @_pending_state_delta[key.to_sym] = value
    end

    # Merges a hash into the pending state delta for this context.
    def state_update(hash_to_merge)
      unless hash_to_merge.is_a?(Hash)
        logger.warn { "[ToolContext] state_update called with non-hash: #{hash_to_merge.class}" }
        return
      end
      # logger.debug { "[ToolContext] state_update with hash: #{hash_to_merge.inspect} (pending)" }
      @_pending_state_delta.merge!(hash_to_merge.transform_keys(&:to_sym))
    end

    # Clears any accumulated pending state changes within this context instance.
    def clear_pending_state_delta!
      @_pending_state_delta = {}
    end

    def to_h
      {
        session_id: @session_id,
        user_id: @user_id,
        app_name: @app_name,
        invocation_id: @invocation_id,
        tool_registry_object_id: @tool_registry&.object_id,
        session_service_present: !@session_service.nil?
      }
    end
  end
end
```

---

**II. Update `ADK::AgentDefinition` (`lib/adk/agent.rb`)**

```ruby
# File: lib/adk/agent.rb
# frozen_string_literal: true

require 'logger'
require 'concurrent'
require 'pathname' # Added for path manipulation
require_relative 'tool_context'
require 'sidekiq' # Ensure sidekiq is required if needed here
# Note: Requires are handled by lib/adk.rb
require_relative 'planner'
require_relative 'tool_registry'
require_relative 'mcp/client'
require_relative 'mcp/tool_wrapper'
require 'set'
require 'forwardable'
require 'json'
require_relative 'global_definition_registry'
require_relative 'global_tool_manager' # Added
require 'socket'
require 'set' # Required for the Set class in _check_circular_dependency
require_relative 'callbacks/callback_context' # Require the new context

module ADK
  class Error < StandardError; end unless defined?(ADK::Error)

  # Represents the static definition of an Agent, including its name,
  # description, instructions, tools, and model configuration.
  class AgentDefinition
    extend Forwardable

    # @return [Symbol] The unique name identifying this agent definition.
    attr_reader :name
    # @return [String] A description of the agent's purpose.
    attr_reader :description
    # @return [String] The core instructions given to the language model.
    attr_reader :instruction
    # @return [Set<Symbol>] A set of names of the tools available to this agent.
    attr_reader :tool_names
    # @return [String, nil] The specific model name to use (e.g., "gpt-4-turbo"). Overrides global default.
    attr_reader :model_name
    # @return [Float, nil] The temperature setting for the model. Overrides global default.
    attr_reader :temperature
    # @return [Boolean] Whether this agent can be triggered by webhooks. Defaults to false.
    attr_reader :webhook_enabled
    # @return [Symbol, Proc, nil] The validator (name or proc) for webhook requests.
    attr_reader :webhook_validator
    # @return [String, nil] The secret key for webhook validation.
    attr_reader :webhook_secret
    # @return [Proc, nil] The transformer proc for webhook payloads.
    attr_reader :webhook_transformer
    # @return [Proc, nil] The session extractor proc for webhook requests.
    attr_reader :webhook_session_extractor
    # @return [Symbol] The fallback mode (:error or :echo). Defaults to :error.
    attr_reader :fallback_mode
    # @return [Array<Hash>] Configuration for MCP servers. Defaults to [].
    attr_reader :mcp_servers
    # @return [Set<Symbol>] A set of names of sub-agent definitions to instantiate.
    attr_reader :sub_agent_names
    # @return [Symbol, nil] The key under which the agent's final output should be stored in the session state.
    attr_reader :output_key
    # @return [Symbol] The type of agent (:llm, :sequential, :parallel, :loop). Defaults to :llm.
    attr_reader :agent_type
    # @return [Set<Symbol>] A set of names of sub-agents to execute in sequence (for SequentialAgent).
    attr_reader :sequential_sub_agent_names
    # @return [Set<Symbol>] A set of names of sub-agents to execute in parallel (for ParallelAgent).
    attr_reader :parallel_sub_agent_names
    # @return [Set<Symbol>] A set of names of sub-agents to execute in each loop iteration (for LoopAgent).
    attr_reader :loop_sub_agent_names
    # @return [Integer, nil] The maximum number of loop iterations (for LoopAgent).
    attr_reader :loop_max_iterations
    # @return [Symbol, nil] The key in the session state to check for loop condition (for LoopAgent).
    attr_reader :loop_condition_state_key
    # @return [Object, nil] The expected value for loop condition (for LoopAgent).
    attr_reader :loop_condition_expected_value
    # @return [Set<Symbol>] A set of names of agents that this agent can delegate tasks to via LLM planning.
    attr_reader :delegation_targets

    # --- Callback Attributes ---
    attr_reader :before_agent_callback, :after_agent_callback,
                :before_model_callback, :after_model_callback,
                :before_tool_callback, :after_tool_callback
    # --- End Callback Attributes ---

    # Delegate common attributes to the definition proxy for easier access during definition
    # Only delegate methods needed *within* the define block
    def_delegators :@proxy, :use_tool

    def initialize
      @name = nil
      @description = ''
      @instruction = ''
      @tool_names = Set.new
      @model_name = nil
      @temperature = nil
      # --- Webhook Defaults ---
      @webhook_enabled = false
      @webhook_validator = nil
      @webhook_secret = nil
      @webhook_transformer = nil
      @webhook_session_extractor = nil
      @fallback_mode = :error # Default fallback mode
      @mcp_servers = [] # Default MCP servers
      @sub_agent_names = Set.new # MAS attribute for sub-agent definitions
      @output_key = nil # MAS attribute for state management
      # --- MAS Workflow Agent Attributes ---
      @agent_type = :llm # Default agent type
      @sequential_sub_agent_names = Set.new # For SequentialAgent
      @parallel_sub_agent_names = Set.new # For ParallelAgent
      @loop_sub_agent_names = Set.new # For LoopAgent
      @loop_max_iterations = nil # Maximum number of loop iterations
      @loop_condition_state_key = nil # State key to check in loop condition
      @loop_condition_expected_value = nil # Expected value for loop condition
      @delegation_targets = Set.new # Agent names that this agent can delegate to
      # -----------------------

      # --- Callback Defaults ---
      @before_agent_callback = nil
      @after_agent_callback = nil
      @before_model_callback = nil
      @after_model_callback = nil
      @before_tool_callback = nil
      @after_tool_callback = nil
      # --- End Callback Defaults ---

      @proxy = DefinitionProxy.new(self)
    end

    # DSL method used within `Agent.define` block.
    # @param block [Proc] The block containing the definition DSL calls.
    def define(&block)
      @proxy.instance_eval(&block)
      validate!
      self
    end

    # Validates that the definition has all required fields.
    # @raise [ArgumentError] If validation fails.
    def validate!
      raise ArgumentError, 'Agent definition must have a name.' if @name.nil? || @name.to_s.strip.empty?
      raise ArgumentError, 'Agent name must be a Symbol.' unless @name.is_a?(Symbol)

      raise ArgumentError,
            "Agent '#{@name}' must have an instruction." if @instruction.nil? || @instruction.strip.empty?

      # Explicitly check instance variable to bypass potential method resolution issues
      if @webhook_enabled
        # raise ArgumentError, "Agent '#{@name}' enabled for webhooks must define a webhook_transformer." unless @webhook_transformer.is_a?(Proc)
        # raise ArgumentError, "Agent '#{@name}' enabled for webhooks must define a webhook_session_extractor." unless @webhook_session_extractor.is_a?(Proc)
        unless @webhook_transformer.is_a?(Proc)
          ADK.logger.warn { "Agent '#{@name}' is webhook_enabled but lacks a valid :webhook_transformer Proc." }
        end
        unless @webhook_session_extractor.is_a?(Proc)
          ADK.logger.warn { "Agent '#{@name}' is webhook_enabled but lacks a valid :webhook_session_extractor Proc." }
        end
      end
    end

    # Returns a hash representation suitable for logging or inspection.
    # @return [Hash]
    def to_h
      {
        name: @name,
        description: @description,
        instruction: @instruction,
        tool_names: @tool_names.to_a,
        model_name: @model_name,
        temperature: @temperature,
        webhook_enabled: @webhook_enabled,
        webhook_validator: @webhook_validator.is_a?(Proc) ? '<Proc>' : @webhook_validator,
        webhook_secret: @webhook_secret ? '<present>' : nil,
        webhook_transformer: @webhook_transformer.is_a?(Proc) ? '<Proc>' : nil,
        webhook_session_extractor: @webhook_session_extractor.is_a?(Proc) ? '<Proc>' : nil,
        fallback_mode: @fallback_mode,
        mcp_servers: @mcp_servers,
        sub_agent_names: @sub_agent_names.to_a, # MAS attribute
        output_key: @output_key, # MAS attribute
        # Adding new MAS attributes for agent hierarchy and workflow
        agent_type: @agent_type || :llm, # Default to :llm if not set
        sequential_sub_agent_names: @sequential_sub_agent_names&.to_a || [],
        parallel_sub_agent_names: @parallel_sub_agent_names&.to_a || [],
        loop_sub_agent_names: @loop_sub_agent_names&.to_a || [],
        loop_max_iterations: @loop_max_iterations,
        loop_condition_state_key: @loop_condition_state_key,
        loop_condition_expected_value: @loop_condition_expected_value,
        delegation_targets: @delegation_targets&.to_a || [],
        # --- Callback Representation ---
        before_agent_callback: @before_agent_callback.is_a?(Proc) ? '<Proc>' : nil,
        after_agent_callback: @after_agent_callback.is_a?(Proc) ? '<Proc>' : nil,
        before_model_callback: @before_model_callback.is_a?(Proc) ? '<Proc>' : nil,
        after_model_callback: @after_model_callback.is_a?(Proc) ? '<Proc>' : nil,
        before_tool_callback: @before_tool_callback.is_a?(Proc) ? '<Proc>' : nil,
        after_tool_callback: @after_tool_callback.is_a?(Proc) ? '<Proc>' : nil
        # --- End Callback Representation ---
      }
    end

    # Internal proxy class to provide a clean DSL within the `define` block.
    class DefinitionProxy
      def initialize(definition)
        @definition = definition
      end

      # Sets the agent name.
      # @param name [Symbol] Unique identifier for the agent.
      def name(name)
        raise ArgumentError, 'Agent name must be a Symbol.' unless name.is_a?(Symbol)

        @definition.instance_variable_set(:@name, name)
      end

      # Sets the agent description.
      # @param description [String]
      def description(description)
        @definition.instance_variable_set(:@description, description.to_s)
      end

      # Sets the agent's core instruction.
      # @param instruction [String]
      def instruction(instruction)
        @definition.instance_variable_set(:@instruction, instruction.to_s)
      end

      # Registers a tool for the agent to use.
      # @param tool_name [Symbol] The registered name of the tool.
      # @param options [Hash] Tool-specific options (currently unused).
      def use_tool(tool_name, _options = {})
        raise ArgumentError, 'Tool name must be a Symbol.' unless tool_name.is_a?(Symbol)

        # TODO: Validate tool_name against a global registry?
        @definition.instance_variable_get(:@tool_names) << tool_name
      end

      # Sets the specific model name for this agent.
      # @param model_name [String, Symbol]
      def model_name(model_name)
        @definition.instance_variable_set(:@model_name, model_name.to_sym)
      end

      # Sets the temperature for this agent.
      # @param temperature [Float]
      def temperature(temperature)
        @definition.instance_variable_set(:@temperature, temperature.to_f)
      end

      # --- Webhook Configuration DSL ---

      # Enables or disables webhook triggering for this agent.
      # @param enabled [Boolean]
      def webhook_enabled(enabled)
        @definition.instance_variable_set(:@webhook_enabled, !!enabled)
      end

      # Sets the validator for webhook requests.
      # @param validator [Symbol, Proc, nil] The name of a registered validator, a Proc, or nil.
      def webhook_validator(validator)
        # Allow nil, Symbol, or Proc
        unless validator.nil? || validator.is_a?(Symbol) || validator.is_a?(Proc)
          raise ArgumentError, 'webhook_validator must be a Symbol, a Proc, or nil.'
        end

        @definition.instance_variable_set(:@webhook_validator, validator)
      end

      # Sets the secret key for webhook validation.
      # @param secret [String]
      def webhook_secret(secret)
        @definition.instance_variable_set(:@webhook_secret, secret)
      end

      # Sets the transformer proc for webhook payloads.
      # @param transformer_proc [Proc, nil] The transformer proc or nil.
      def webhook_transformer(transformer_proc)
        # Allow nil or Proc
        raise ArgumentError,
              'webhook_transformer must be a Proc or nil.' unless transformer_proc.nil? || transformer_proc.is_a?(Proc)

        @definition.instance_variable_set(:@webhook_transformer, transformer_proc)
      end

      # Sets the session extractor proc for webhook requests.
      # @param extractor_proc [Proc, nil] The extractor proc or nil.
      def webhook_session_extractor(extractor_proc)
        # Allow nil or Proc
        raise ArgumentError,
              'webhook_session_extractor must be a Proc or nil.' unless extractor_proc.nil? || extractor_proc.is_a?(Proc)

        @definition.instance_variable_set(:@webhook_session_extractor, extractor_proc)
      end

      # Sets the fallback mode for the agent.
      # @param mode [Symbol] :error or :echo.
      def fallback_mode(mode)
        valid_modes = %i[error echo]
        unless valid_modes.include?(mode)
          raise ArgumentError, "Invalid fallback_mode '#{mode}'. Must be one of: #{valid_modes.join(', ')}."
        end

        @definition.instance_variable_set(:@fallback_mode, mode)
      end

      # Configures MCP servers for the agent.
      # @param server_configs [Hash, Array<Hash>] MCP server configuration(s).
      def mcp_servers(*server_configs)
        configs = Array(server_configs).flatten.compact
        # Basic validation: Ensure it's an array of hashes?
        unless configs.all? { |c| c.is_a?(Hash) }
          raise ArgumentError, 'MCP server configurations must be provided as Hashes.'
        end

        @definition.instance_variable_set(:@mcp_servers, configs)
      end
      # -----------------------------

      # --- MAS Attributes DSL ---
      # Defines the names of sub-agents that should be instantiated under this agent.
      # @param names [Array<Symbol>] An array of sub-agent definition names.
      def sub_agents_define(*names)
        flat_names = names.flatten.map(&:to_sym)
        invalid_names = flat_names.reject { |n| n.is_a?(Symbol) }
        unless invalid_names.empty?
          raise ArgumentError, "Sub-agent names must all be Symbols. Invalid names: #{invalid_names.join(', ')}"
        end

        @definition.instance_variable_set(:@sub_agent_names, @definition.instance_variable_get(:@sub_agent_names).merge(flat_names))
      end

      # Sets the key under which the agent's final output should be stored in session state.
      # @param key_name [Symbol] The key name.
      def output_key(key_name)
        raise ArgumentError, 'Output key must be a Symbol.' unless key_name.is_a?(Symbol)

        @definition.instance_variable_set(:@output_key, key_name)
      end

      # --- MAS Workflow Agent Type ---
      # Sets the agent type
      # @param type [Symbol] The agent type (:llm, :sequential, :parallel, :loop)
      def agent_type(type)
        valid_types = %i[llm sequential parallel loop]
        unless valid_types.include?(type.to_sym)
          raise ArgumentError, "Agent type must be one of: #{valid_types.join(', ')}. Got: #{type}"
        end

        @definition.instance_variable_set(:@agent_type, type.to_sym)
      end

      # --- SequentialAgent Configuration ---
      # Define sequential sub-agent names in order of execution
      # @param names [Array<Symbol>] Names of sub-agents to execute in sequence
      def sequential_sub_agents(*names)
        flat_names = names.flatten.map(&:to_sym)
        # Log a warning if the array is empty but don't raise an error
        ADK.logger.warn("Empty sequential sub-agents list for agent '#{@definition.name}'") if flat_names.empty?

        @definition.instance_variable_set(:@sequential_sub_agent_names, Set.new(flat_names))
      end

      # --- ParallelAgent Configuration ---
      # Define parallel sub-agent names to execute concurrently
      # @param names [Array<Symbol>] Names of sub-agents to execute in parallel
      def parallel_sub_agents(*names)
        flat_names = names.flatten.map(&:to_sym)
        # Log a warning if the array is empty but don't raise an error
        ADK.logger.warn("Empty parallel sub-agents list for agent '#{@definition.name}'") if flat_names.empty?

        @definition.instance_variable_set(:@parallel_sub_agent_names, Set.new(flat_names))
      end

      # --- LoopAgent Configuration ---
      # Define loop sub-agent names in order of execution within each loop iteration
      # @param names [Array<Symbol>] Names of sub-agents to execute in each loop iteration
      def loop_sub_agents(*names)
        flat_names = names.flatten.map(&:to_sym)
        # Log a warning if the array is empty but don't raise an error
        ADK.logger.warn("Empty loop sub-agents list for agent '#{@definition.name}'") if flat_names.empty?

        @definition.instance_variable_set(:@loop_sub_agent_names, Set.new(flat_names))
      end

      # Set maximum number of loop iterations
      # @param max [Integer] The maximum number of iterations
      def loop_max_iterations(max)
        unless max.is_a?(Integer) && max > 0
          raise ArgumentError, "Maximum iterations must be a positive integer. Got: #{max}"
        end

        @definition.instance_variable_set(:@loop_max_iterations, max)
      end

      # Set the loop condition state key and expected value
      # @param key [Symbol] The key in the session state to check
      # @param value [Object] The expected value that indicates loop completion
      def loop_condition(key, value)
        raise ArgumentError, 'Loop condition key must be a Symbol.' unless key.is_a?(Symbol)

        @definition.instance_variable_set(:@loop_condition_state_key, key)
        @definition.instance_variable_set(:@loop_condition_expected_value, value)
      end

      # --- Delegation Configuration ---
      # Define agent names that this agent can delegate tasks to via LLM planning
      # @param names [Array<Symbol>] Names of agents that can be delegation targets
      def can_delegate_to(*names)
        flat_names = names.flatten.map(&:to_sym)
        # Log a warning if the array is empty but don't raise an error
        ADK.logger.warn("Empty delegation targets list for agent '#{@definition.name}'") if flat_names.empty?

        @definition.instance_variable_set(:@delegation_targets, Set.new(flat_names))
      end
      # --- End MAS Attributes DSL ---

      # --- Callback DSL Methods ---
      def before_agent_callback(&block)
        raise ArgumentError, 'Callback must be a Proc or lambda.' unless block.is_a?(Proc)
        @definition.instance_variable_set(:@before_agent_callback, block)
      end

      def after_agent_callback(&block)
        raise ArgumentError, 'Callback must be a Proc or lambda.' unless block.is_a?(Proc)
        @definition.instance_variable_set(:@after_agent_callback, block)
      end

      def before_model_callback(&block)
        raise ArgumentError, 'Callback must be a Proc or lambda.' unless block.is_a?(Proc)
        @definition.instance_variable_set(:@before_model_callback, block)
      end

      def after_model_callback(&block)
        raise ArgumentError, 'Callback must be a Proc or lambda.' unless block.is_a?(Proc)
        @definition.instance_variable_set(:@after_model_callback, block)
      end

      def before_tool_callback(&block)
        raise ArgumentError, 'Callback must be a Proc or lambda.' unless block.is_a?(Proc)
        @definition.instance_variable_set(:@before_tool_callback, block)
      end

      def after_tool_callback(&block)
        raise ArgumentError, 'Callback must be a Proc or lambda.' unless block.is_a?(Proc)
        @definition.instance_variable_set(:@after_tool_callback, block)
      end
      # --- End Callback DSL Methods ---
    end
    private_constant :DefinitionProxy

    # Class method to create an AgentDefinition instance from a hash.
    # This is typically used when loading a definition from a persistent store.
    # @param hash_data [Hash] The hash containing agent definition attributes.
    # @return [ADK::AgentDefinition, nil] A new AgentDefinition instance or nil on error.
    def self.from_hash(hash_data)
      return nil unless hash_data.is_a?(Hash)

      definition = new

      # Helper method to convert array values to Sets if present in the source hash
      convert_to_set = lambda do |key, default = nil|
        if hash_data.key?(key)
          val = hash_data[key]
          val.is_a?(Array) ? Set.new(val.map(&:to_sym)) : (val.nil? ? default : Set.new([val.to_sym]))
        else
          default || Set.new
        end
      end

      # Map string or symbol keys to our keys
      definition.instance_variable_set(:@name, hash_data[:name]&.to_sym || hash_data['name']&.to_sym)
      definition.instance_variable_set(:@description, hash_data[:description]&.to_s || hash_data['description']&.to_s || '')
      definition.instance_variable_set(:@instruction, hash_data[:instruction]&.to_s || hash_data['instruction']&.to_s || '')

      # Handle tools/tool_names (expected to be an array of strings or symbols)
      tool_names = nil
      if hash_data.key?(:tool_names) || hash_data.key?('tool_names')
        tool_names = hash_data[:tool_names] || hash_data['tool_names']
      elsif hash_data.key?(:tools) || hash_data.key?('tools')
        tool_names = hash_data[:tools] || hash_data['tools']
      end

      # Convert tool_names to a Set of symbols (always ensure it's a Set)
      if tool_names.is_a?(Array)
        definition.instance_variable_set(:@tool_names, Set.new(tool_names.map(&:to_sym)))
      elsif tool_names.is_a?(String)
        # Special case: if it's a JSON string, try to parse it
        begin
          parsed_tools = JSON.parse(tool_names)
          if parsed_tools.is_a?(Array)
            definition.instance_variable_set(:@tool_names, Set.new(parsed_tools.map(&:to_sym)))
          else
            definition.instance_variable_set(:@tool_names, Set.new)
          end
        rescue JSON::ParserError
          # Not valid JSON, treat as single tool name
          definition.instance_variable_set(:@tool_names, Set.new([tool_names.to_sym]))
        end
      else
        # No valid tools provided, use empty set
        definition.instance_variable_set(:@tool_names, Set.new)
      end

      # Process model_name (string or symbol)
      model_name = hash_data[:model_name] || hash_data['model_name'] || hash_data[:model] || hash_data['model']
      definition.instance_variable_set(:@model_name, model_name&.to_sym)

      # Process temperature (float)
      temp_value = hash_data[:temperature] || hash_data['temperature']
      definition.instance_variable_set(:@temperature, temp_value&.to_f)

      # --- Process webhook fields ---
      # Boolean conversion helper for webhook_enabled
      wb_enabled = hash_data[:webhook_enabled] || hash_data['webhook_enabled']
      wb_enabled = wb_enabled.to_s.downcase == 'true' if wb_enabled.is_a?(String)
      definition.instance_variable_set(:@webhook_enabled, !!wb_enabled) # Force to boolean

      # webhook_validator can be symbol or nil
      wb_validator = hash_data[:webhook_validator] || hash_data['webhook_validator']
      definition.instance_variable_set(:@webhook_validator, wb_validator.is_a?(Symbol) ? wb_validator : nil)

      # webhook_secret is a string or nil
      wb_secret = hash_data[:webhook_secret] || hash_data['webhook_secret']
      # Special case: '<present>' is a placeholder used in to_h when the secret exists
      definition.instance_variable_set(:@webhook_secret, wb_secret == '<present>' ? wb_secret : wb_secret)

      # webhook_transformer and webhook_session_extractor are Procs (can't be serialized)
      # Always nil when recreated from a hash
      definition.instance_variable_set(:@webhook_transformer, nil)
      definition.instance_variable_set(:@webhook_session_extractor, nil)

      # --- Process MCP servers ---
      # MCP servers can be array of hashes, or JSON string
      mcp_value = hash_data[:mcp_servers] || hash_data['mcp_servers'] || hash_data[:mcp_servers_json] || hash_data['mcp_servers_json']
      if mcp_value.is_a?(String)
        begin
          parsed_mcp = JSON.parse(mcp_value)
          definition.instance_variable_set(:@mcp_servers, parsed_mcp.is_a?(Array) ? parsed_mcp : [])
        rescue JSON::ParserError
          # Not valid JSON, use empty array
          definition.instance_variable_set(:@mcp_servers, [])
        end
      elsif mcp_value.is_a?(Array)
        definition.instance_variable_set(:@mcp_servers, mcp_value)
      else
        definition.instance_variable_set(:@mcp_servers, [])
      end

      # --- Process fallback_mode (convert to symbol) ---
      fallback = hash_data[:fallback_mode] || hash_data['fallback_mode']
      if fallback.is_a?(String) || fallback.is_a?(Symbol)
        fb_sym = fallback.to_sym
        definition.instance_variable_set(:@fallback_mode, fb_sym == :echo ? :echo : :error)
      else
        definition.instance_variable_set(:@fallback_mode, :error) # Default
      end

      # --- Process MAS attributes ---
      # Sub-agent names (convert to Set of symbols)
      definition.instance_variable_set(:@sub_agent_names, convert_to_set.call(:sub_agent_names))

      # Output key (convert to symbol if present)
      output_key = hash_data[:output_key] || hash_data['output_key']
      definition.instance_variable_set(:@output_key, output_key&.to_sym)

      # --- MAS Workflow Agent Attributes ---
      # Agent type (convert to symbol, default to :llm)
      agent_type = hash_data[:agent_type] || hash_data['agent_type'] || :llm
      if agent_type.is_a?(String) || agent_type.is_a?(Symbol)
        agent_type_sym = agent_type.to_sym
        valid_types = %i[llm sequential parallel loop]
        # If invalid type, use default :llm
        agent_type_sym = :llm unless valid_types.include?(agent_type_sym)
        definition.instance_variable_set(:@agent_type, agent_type_sym)
      else
        definition.instance_variable_set(:@agent_type, :llm) # Default
      end

      # Workflow-specific sub-agent lists
      definition.instance_variable_set(:@sequential_sub_agent_names, convert_to_set.call(:sequential_sub_agent_names))
      definition.instance_variable_set(:@parallel_sub_agent_names, convert_to_set.call(:parallel_sub_agent_names))
      definition.instance_variable_set(:@loop_sub_agent_names, convert_to_set.call(:loop_sub_agent_names))

      # Loop configuration
      loop_max = hash_data[:loop_max_iterations] || hash_data['loop_max_iterations']
      definition.instance_variable_set(:@loop_max_iterations, loop_max&.to_i)

      loop_key = hash_data[:loop_condition_state_key] || hash_data['loop_condition_state_key']
      definition.instance_variable_set(:@loop_condition_state_key, loop_key&.to_sym)

      loop_value = hash_data[:loop_condition_expected_value] || hash_data['loop_condition_expected_value']
      definition.instance_variable_set(:@loop_condition_expected_value, loop_value)

      # Delegation targets
      definition.instance_variable_set(:@delegation_targets, convert_to_set.call(:delegation_targets))

      # Callbacks will remain nil as they are not serialized
      definition.instance_variable_set(:@before_agent_callback, nil)
      definition.instance_variable_set(:@after_agent_callback, nil)
      definition.instance_variable_set(:@before_model_callback, nil)
      definition.instance_variable_set(:@after_model_callback, nil)
      definition.instance_variable_set(:@before_tool_callback, nil)
      definition.instance_variable_set(:@after_tool_callback, nil)

      definition
    end
  end

  # Agent class represents an AI agent that can perform tasks using tools and a planner.
  # It operates within the context of a session managed by a SessionService.
  class Agent
    DEFAULT_MODEL = 'gemini-2.0-flash' # Updated default model

    attr_reader :name, :description, :planner, :logger, :model_name, :state, :tool_registry, :fallback_mode,
                :instruction, :definition, :session_service # Added session_service to attr_reader
    # MAS Attributes
    attr_reader :parent_agent # The parent agent in a hierarchy, if any
    attr_reader :sub_agents   # A collection of sub-agents

    # --- Callback Instance Variables ---
    attr_reader :before_agent_callback, :after_agent_callback,
                :before_model_callback, :after_model_callback,
                :before_tool_callback, :after_tool_callback
    # --- End Callback Instance Variables ---


    # --- Class Method for Configuration DSL ---
    # Provides a block-based DSL for configuring and creating an Agent instance.
    #
    # @example
    #   agent = ADK::Agent.define do |a|
    #     a.name = 'news_agent'
    #     a.description = 'Summarizes news articles.'
    #     a.model_name = 'gemini-pro'
    #     a.discover_tools_in 'path/to/my_tools'
    #     a.add_tool_classes MyCustomTool
    #     a.fallback_mode = :echo
    #   end
    #
    # @yieldparam builder [ADK::Agent::AgentBuilder] The builder object to configure the agent.
    # @return [ADK::Agent] The newly configured agent instance.
    # @raise [ArgumentError] if the block is not provided or required attributes are missing.
    def self.define(&block)
      raise ArgumentError, 'ADK::Agent.define requires a block.' unless block_given?

      # 1. Create a new AgentDefinition
      definition = ADK::AgentDefinition.new

      # 2. Evaluate the block within the definition's proxy DSL
      # Use the definition instance's define method which takes the block
      # This also handles internal validation via validate!
      begin
        definition.define(&block)
      rescue ArgumentError => e
        # Re-raise DSL validation errors immediately
        raise e
      end

      # 3. Save the validated definition using the configured definition store
      begin
        store = ADK.config.definition_store
        raise ADK::ConfigurationError, 'ADK.config.definition_store is not configured.' unless store

        # Ensure store responds to save_definition
        unless store.respond_to?(:save_definition)
          raise ADK::ConfigurationError,
                "Configured definition store (#{store.class}) does not support :save_definition method."
        end

        # Extract values using instance variables to avoid delegation issues
        agent_name = definition.instance_variable_get(:@name)
        description = definition.instance_variable_get(:@description)
        tool_names = definition.instance_variable_get(:@tool_names).map(&:to_s)
        model = definition.instance_variable_get(:@model_name)
        fallback_mode = definition.instance_variable_get(:@fallback_mode)
        mcp_servers = definition.instance_variable_get(:@mcp_servers) || []
        instruction = definition.instance_variable_get(:@instruction)
        webhook_enabled = definition.instance_variable_get(:@webhook_enabled)
        webhook_secret = definition.instance_variable_get(:@webhook_secret)

        # Prepare MCP JSON
        mcp_json = JSON.generate(mcp_servers)

        # Call save_definition with keyword arguments
        store.save_definition(
          name: agent_name.to_s,
          description: description,
          tools: tool_names,
          model: model,
          fallback_mode: fallback_mode,
          mcp_servers_json: mcp_json,
          instruction: instruction,
          webhook_enabled: webhook_enabled,
          webhook_secret: webhook_secret
          # Callbacks are not saved to the store as they are Procs
        )

        # Use extracted name for logging
        ADK.logger.info("Agent definition '#{agent_name}' saved to store.")
      rescue JSON::GeneratorError => e
        agent_name_for_log = definition.instance_variable_get(:@name) || 'unknown'
        ADK.logger.error("Failed to serialize MCP servers for definition '#{agent_name_for_log}': #{e.message}")
        raise ADK::StoreError, "Internal error preparing definition '#{agent_name_for_log}' for storage."
      # Catch config errors specifically
      rescue ADK::ConfigurationError => e
        agent_name_for_log = definition.instance_variable_get(:@name) || 'unknown'
        ADK.logger.error("Configuration error during definition save for '#{agent_name_for_log}': #{e.message}")
        raise e
      # Catch store-specific errors (like connection issues, Redis errors, ArgumentErrors from store method)
      rescue ADK::StoreError, ArgumentError => e
        agent_name_for_log = definition.instance_variable_get(:@name) || 'unknown'
        ADK.logger.error("Failed to save definition '#{agent_name_for_log}' to store: #{e.class} - #{e.message}")
        raise e # Re-raise store/argument errors
      rescue => e # Catch other unexpected errors
        agent_name_for_log = definition.instance_variable_get(:@name) || 'unknown'
        ADK.logger.error("Unexpected error saving definition '#{agent_name_for_log}' to store: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
        raise ADK::StoreError, "Unexpected error saving definition '#{agent_name_for_log}': #{e.message}"
      end

      # <<< ADDED BACK: Register the in-memory definition object globally >>>
      GlobalDefinitionRegistry.register(definition)

      definition # Return the definition instance
    end
    # --- End Class Method ---

    # Initializes a new agent instance.
    # An agent MUST be initialized with a valid ADK::AgentDefinition object.
    #
    # @param definition [ADK::AgentDefinition] The agent definition object.
    # @param session_service [ADK::SessionService::Base, nil] Optional: Pre-initialized session service.
    # @param planner_override [ADK::Planner, nil] Optional: A specific planner instance to override the default.
    # @param sub_agents [Array<ADK::Agent>, nil] Optional: An array of pre-initialized sub-agent instances. If provided, these will be used instead of instantiating from `definition.sub_agent_names`.
    def initialize(definition:, session_service: nil, planner_override: nil, sub_agents: nil)
      unless definition.is_a?(ADK::AgentDefinition)
        raise ArgumentError,
              "Agent must be initialized with an ADK::AgentDefinition object. Received: #{definition.class}"
      end
      # Perform a more thorough check if it looks like a definition
      unless definition.respond_to?(:name) && definition.respond_to?(:description) &&
             definition.respond_to?(:instruction) && definition.respond_to?(:tool_names) &&
             definition.respond_to?(:model_name) && definition.respond_to?(:fallback_mode) &&
             definition.respond_to?(:mcp_servers)
        raise ArgumentError,
              'Provided definition object does not appear to be a valid ADK::AgentDefinition (missing required attributes/methods).'
      end

      @definition = definition
      @name = definition.name

      # --- Initialize Callbacks from Definition ---
      @before_agent_callback = definition.before_agent_callback
      @after_agent_callback = definition.after_agent_callback
      @before_model_callback = definition.before_model_callback
      @after_model_callback = definition.after_model_callback
      @before_tool_callback = definition.before_tool_callback
      @after_tool_callback = definition.after_tool_callback
      # --- End Initialize Callbacks ---


      # Check for direct self-references in the definition's sub_agent_names
      if definition.respond_to?(:sub_agent_names) && definition.sub_agent_names&.any?
        if definition.sub_agent_names.include?(@name)
          raise ADK::ConfigurationError, "Circular dependency detected: Agent '#{@name}' cannot include itself as a sub-agent"
        end
      end

      @description = definition.description
      @instruction = definition.instruction
      @model_name = definition.model_name || DEFAULT_MODEL
      @fallback_mode = definition.fallback_mode # Assumes :error is default in AgentDefinition
      @selected_tool_names = definition.tool_names.to_a # Tool names are directly from definition

      # MAS Attributes Initialization
      @parent_agent = nil # Will be set by parent if this is a sub-agent
      @sub_agents = []    # Will be populated if this agent has sub-agents defined

      # Tool paths are NOT loaded when initializing from definition; tools are expected to be globally registered.
      tool_paths_to_load = []
      # Tool classes are resolved via GlobalToolManager using names from definition
      tool_classes_to_load = definition.tool_names.map { |tn| ADK::GlobalToolManager.find_class(tn) }.compact

      if tool_classes_to_load.length != definition.tool_names.length
        found_tool_names = tool_classes_to_load.map { |tc| tc.tool_metadata[:name].to_sym rescue nil }.compact.to_set
        missing_tool_names = definition.tool_names.to_set - found_tool_names
        ADK.logger.warn("Agent '#{@name}': Could not find globally registered classes for tools: #{missing_tool_names.to_a.join(', ')}. These tools will be unavailable.")
      end

      @session_service = session_service || ADK.config.session_service # Simplified session service init

      # MCP servers are taken directly from the definition
      mcp_servers_config_str = definition.mcp_servers || []

      ADK.logger.info("Initializing agent '#{@name}' from provided definition object...")
      # -----------------------------------------
      @state = :idle # Initial state

      @tool_registry = ADK::ToolRegistry.new
      ADK.logger.debug("Agent '#{@name}' created its ToolRegistry instance: #{@tool_registry.object_id}")

      # 1. Discover tools from paths (if any) and update GlobalToolManager
      newly_discovered_tool_names = Set.new
      unless tool_paths_to_load.empty?
        initial_global_tools = ADK::GlobalToolManager.registered_tool_names.to_set
        _discover_and_load_tools(tool_paths_to_load)
        current_global_tools = ADK::GlobalToolManager.registered_tool_names.to_set
        newly_discovered_tool_names = current_global_tools - initial_global_tools
        ADK.logger.debug("[Agent Init '#{@name}'] Newly discovered tool names: #{newly_discovered_tool_names.to_a.inspect}")
      end

      # 2. Register tool *classes* passed directly (via add_tool_classes or from definition)
      ADK.logger.debug("[Agent Init '#{@name}'] Registering explicitly provided tool classes: #{tool_classes_to_load.inspect}")
      tool_classes_to_load.each do |tool_class|
        ADK.logger.debug("[Agent Init '#{@name}'] Processing class from builder: #{tool_class.inspect} (Object ID: #{tool_class.object_id})")
        register_tool_class(tool_class) # Use the agent's specific register method
      end

      # 3. Register newly *discovered* tool classes (from paths) that weren't explicitly passed
      ADK.logger.debug("[Agent Init '#{@name}'] Registering newly discovered tool classes (from paths): #{newly_discovered_tool_names.to_a.inspect}")
      newly_discovered_tool_names.each do |tool_name|
        tool_class = ADK::GlobalToolManager.find_class(tool_name)
        if tool_class
          # Check if already registered from step 2 before registering again
          unless @tool_registry.find_class(tool_name)
            ADK.logger.debug("[Agent Init '#{@name}'] Registering discovered tool #{tool_name.inspect} (class: #{tool_class})...")
            register_tool_class(tool_class) # Use the agent's specific register method
          else
            ADK.logger.debug("[Agent Init '#{@name}'] Skipping registration of discovered tool #{tool_name.inspect}, already registered via explicit classes.")
          end
        else
          # This case should be rare now due to _discover_and_load_tools logic
          ADK.logger.error("[Agent Init '#{@name}'] Failed to find class for discovered tool '#{tool_name}' in GlobalToolManager during agent init.")
        end
      end

      # 4. Register mandatory tools like CheckJobStatusTool if needed
      if defined?(Sidekiq)
        unless @tool_registry.find_class(:check_job_status)
          begin
            require_relative 'tools/check_job_status_tool' # Ensure loaded
            register_tool_class(ADK::Tools::CheckJobStatusTool)
            ADK.logger.info("Automatically registered CheckJobStatusTool for agent '#{@name}'.")
          rescue LoadError => e
            ADK.logger.error("Failed to load CheckJobStatusTool: #{e.message}")
          end
        end
      else
        ADK.logger.warn("Sidekiq not defined. Skipping automatic registration of CheckJobStatusTool for agent '#{@name}'.")
      end

      # --- Parse MCP Server Config (uses mcp_servers_config_str) ---
      if mcp_servers_config_str.is_a?(String) && !mcp_servers_config_str.strip.empty?
      # ... (rest of existing MCP parsing) ...
      elsif mcp_servers_config_str.is_a?(Array)
        @mcp_servers_config = mcp_servers_config_str # Already an array
      else
        ADK.logger.debug("Agent '#{@name}': No valid MCP server config provided. Defaulting to empty array.")
        @mcp_servers_config = []
      end

      @selected_tool_names = @definition.tool_names.to_a # Ensure this uses the definition
      @mcp_clients = [] # Store active MCP client instances

      @planner = planner_override || ADK::Planner.new(agent: self, model_name: @model_name)

      # Validate essential components using respond_to? for duck typing
      unless @session_service&.respond_to?(:get_session) && @session_service&.respond_to?(:append_event)
        raise ConfigurationError,
              "Agent '#{@name}' requires a valid Session Service (must respond to :get_session, :append_event)."
      end
      unless @planner&.respond_to?(:plan)
        raise ConfigurationError, "Agent '#{@name}' requires a valid Planner (must respond to :plan)."
      end

      ADK.logger.debug {
        "Agent '#{@name}' initialized with #{@tool_registry.tools.count} tools: [#{@tool_registry.tools.keys.join(', ')}]"
      }

      # MAS: Instantiate Sub-Agents or use provided ones
      if sub_agents && !sub_agents.empty?
        ADK.logger.info("Agent '#{@name}': Initializing with programmatically provided sub-agents (#{sub_agents.length} agents).")
        sub_agents.each do |sub_agent|
          unless sub_agent.is_a?(ADK::Agent)
            ADK.logger.warn("Agent '#{@name}': Item in provided sub_agents list is not an ADK::Agent. Skipping: #{sub_agent.inspect}")
            next
          end

          # Check for circular dependencies
          begin
            _check_circular_dependency(sub_agent.name)
          rescue ADK::ConfigurationError => e
            ADK.logger.error("Agent '#{@name}': #{e.message}")
            next # Skip this sub-agent
          end

          # Enforce single parent rule
          if sub_agent.parent_agent.nil?
            sub_agent.instance_variable_set(:@parent_agent, self)
          elsif sub_agent.parent_agent != self
            ADK.logger.error("Agent '#{@name}': Cannot adopt sub-agent '#{sub_agent.name}'. It already has a different parent: '#{sub_agent.parent_agent.name}'. Skipping this sub-agent.")
            next # Skip this sub-agent
          end
          # (If sub_agent.parent_agent == self, it's already correctly parented, do nothing extra here)

          # Verify session service consistency and assign if missing
          if sub_agent.instance_variable_get(:@session_service).nil? && @session_service
            ADK.logger.debug("Agent '#{@name}': Setting session_service for programmatic sub-agent '#{sub_agent.name}' to match parent.")
            sub_agent.instance_variable_set(:@session_service, @session_service)
          elsif sub_agent.instance_variable_get(:@session_service) != @session_service && @session_service # Warn if different and parent has one
            ADK.logger.warn("Agent '#{@name}': Programmatic sub-agent '#{sub_agent.name}' has a different session_service than parent.")
          end
          @sub_agents << sub_agent
          ADK.logger.info("Agent '#{@name}': Successfully instantiated and linked sub-agent '#{sub_agent.name}'.")
        end
        ADK.logger.info("Agent '#{@name}' finished linking programmatic sub-agents. Total sub-agents: #{@sub_agents.length}")
      elsif definition.respond_to?(:sub_agent_names) && definition.sub_agent_names&.any?
        ADK.logger.info("Agent '#{@name}' attempting to instantiate sub-agents from definition: #{definition.sub_agent_names.to_a.inspect}")
        definition.sub_agent_names.each do |sub_agent_name|
          begin
            # Check for circular dependencies before instantiation
            _check_circular_dependency(sub_agent_name)

            sub_agent_definition = ADK::GlobalDefinitionRegistry.find(sub_agent_name)
            unless sub_agent_definition
              ADK.logger.error("Agent '#{@name}': Could not find definition for sub-agent '#{sub_agent_name}' in GlobalDefinitionRegistry. Skipping.")
              next
            end

            ADK.logger.debug("Agent '#{@name}': Instantiating sub-agent '#{sub_agent_name}'...")
            sub_agent = ADK::Agent.new(definition: sub_agent_definition, session_service: @session_service)
            # Set parent link - enforce single parent rule
            if sub_agent.parent_agent.nil?
              sub_agent.instance_variable_set(:@parent_agent, self)
            elsif sub_agent.parent_agent != self # Should not happen if instantiated fresh, but defensive check
              ADK.logger.error("Agent '#{@name}': Newly instantiated sub-agent '#{sub_agent.name}' unexpectedly already has a different parent: '#{sub_agent.parent_agent.name}'. Skipping.")
              next # Skip this sub-agent
            end
            # (If sub_agent.parent_agent == self, it's already fine)

            @sub_agents << sub_agent
            ADK.logger.info("Agent '#{@name}': Successfully instantiated and linked sub-agent '#{sub_agent.name}'.")
          rescue ArgumentError => e # Catch errors from ADK::Agent.new (e.g. definition issues)
            ADK.logger.error("Agent '#{@name}': ArgumentError instantiating sub-agent '#{sub_agent_name}': #{e.message}")
          rescue StandardError => e
            ADK.logger.error("Agent '#{@name}': Unexpected error instantiating sub-agent '#{sub_agent_name}': #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
          end
        end
        ADK.logger.info("Agent '#{@name}' finished sub-agent instantiation. Total sub-agents: #{@sub_agents.length}")
      end
    end

    # Adds a tool instance OR class to the agent's registry
    # @param tool [ADK::Tool, Class<ADK::Tool>] The tool instance or class to add
    # @return [Boolean] True if the tool was added, false otherwise
    def add_tool(tool)
      # Check if it's a valid tool instance or class
      is_tool_instance = tool.is_a?(ADK::Tool)
      is_tool_class = tool.is_a?(Class) && tool < ADK::Tool

      unless is_tool_instance || is_tool_class
        ADK.logger.error("Agent '#{name}' add_tool: Attempted to add invalid tool: #{tool.inspect}")
        return false
      end

      # Determine the actual tool class
      tool_class = is_tool_class ? tool : tool.class

      # --- Determine Tool Name with Fallbacks --- #
      tool_name = get_tool_name_from_class(tool_class) # Use the new helper
      # --- End Determine Tool Name --- #

      # Validate name was found
      unless tool_name # The helper returns nil if no valid name is found
        ADK.logger.error("Agent '#{name}' add_tool: Could not determine tool name for class #{tool_class}. Cannot add tool.")
        return false # Explicitly return false
      end

      # Check for overwrite
      if @tool_registry.find_class(tool_name)
        ADK.logger.warn("Agent '#{name}': Tool '#{tool_name}' already added. Overwriting with class #{tool_class}.")
      end

      # Register the class using the determined name
      ADK.logger.debug("Agent '#{name}' add_tool: Registering tool_name=#{tool_name.inspect} with class=#{tool_class.inspect} in registry=#{@tool_registry.object_id}")
      registration_result = @tool_registry.register(tool_name, tool_class)
      ADK.logger.debug("Agent '#{name}' add_tool: Registry after registration for #{tool_name.inspect}: #{@tool_registry.tools.keys.inspect}")

      # Explicitly return the boolean result from the registry
      registration_result
    end

    # Returns the list of tools registered with this agent
    # @return [Array<ADK::Tool>] Array of tool instances
    def tools
      @tool_registry.tools.values.map do |tool_class|
        # Get name reliably using the new helper method
        tool_name = get_tool_name_from_class(tool_class)
        if tool_name
          @tool_registry.create_instance(tool_name)
        else
          # This branch should ideally not be hit frequently if registration robustly requires a name.
          ADK.logger.warn("Agent '#{name}': Skipping tool instance creation for class #{tool_class} as its name could not be determined post-registration.")
          nil
        end
      end.compact
    end

    # Finds a tool instance by name
    # @param tool_name [Symbol] The name of the tool to find
    # @return [ADK::Tool, nil] The tool instance if found, nil otherwise
    def find_tool(tool_name)
      @tool_registry.create_instance(tool_name.to_sym)
    end

    # Registers a tool class with the agent's specific registry.
    # @param tool_class [Class] The tool class to register (must inherit from ADK::Tool).
    # @return [Boolean] True if registration was successful, false otherwise.
    def register_tool_class(tool_class)
      ADK.logger.debug("[register_tool_class] Registering class: #{tool_class.inspect} (Object ID: #{tool_class.object_id})")
      # Basic validation
      unless tool_class < ADK::Tool
        ADK.logger.error("Agent '#{name}': Attempted to register invalid object (must inherit from ADK::Tool): #{tool_class.inspect}")
        return false
      end

      # Get name via metadata method
      tool_name = get_tool_name_from_class(tool_class) # Use the new helper
      ADK.logger.debug("[register_tool_class] Determined tool name: #{tool_name.inspect} for class #{tool_class.inspect}")

      unless tool_name # Helper returns nil if no valid name
        # Use logger method, not direct access
        ADK.logger.error("Agent '#{name}': Could not determine tool name for class #{tool_class}. Cannot register.") # Consistent error message
        return false
      end

      if @tool_registry.find_class(tool_name)
        ADK.logger.warn("Agent '#{name}': Tool '#{tool_name}' already registered. Overwriting.")
      end

      # Register with the instance registry
      @tool_registry.register(tool_name, tool_class)
      true # Return true on success
    end

    # --- Runtime State Methods (unchanged) ---
    def start
      return if running? # Prevent starting multiple times

      ADK.logger.info("Starting agent '#{name}' runtime...")
      @state = :running

      # Connect to MCP Servers and register tools
      connect_mcp_servers

      ADK.logger.info("Agent '#{name}' runtime started.")
    end

    def stop
      return unless running?

      ADK.logger.info("Stopping agent '#{name}' runtime...")
      @state = :stopped

      # Disconnect MCP Clients
      disconnect_mcp_servers

      ADK.logger.info("Agent '#{name}' runtime stopped.")
    end

    def running?
      @state == :running
    end

    # Returns the list of available tool metadata (names, descriptions, parameters)
    # from the agent's specific tool registry.
    def available_tools_metadata
      @tool_registry.list_tools
    end

    # Finds a tool class by name from the agent's specific tool registry.
    # @param tool_name [Symbol]
    # @return [Class<ADK::Tool>, nil]
    def find_tool_class(tool_name)
      @tool_registry.find_class(tool_name.to_sym)
    end

    # @return [ADK::Event] The final agent event.
    def run_task(session_id:, user_input:, session_service:)
      # --- Pre-execution Checks --- #
      unless running?
        err_msg = "Agent '#{name}' runtime is not active (stopped)."
        ADK.logger.error(err_msg)
        return ADK::Event.new(role: :agent, content: { status: :error, error_message: err_msg })
      end

      session = session_service.get_session(session_id: session_id)
      unless session
        err_msg = "Session not found: #{session_id}"
        ADK.logger.error(err_msg)
        return ADK::Event.new(role: :agent, content: { status: :error, error_message: err_msg })
      end
      # --------------------------- #

      invocation_id = SecureRandom.uuid
      callback_context = ADK::Callbacks::CallbackContext.new(
        agent_name: @name, invocation_id: invocation_id,
        session_id: session.id, user_id: session.user_id, app_name: session.app_name,
        session_service: @session_service, logger: ADK.logger
      )

      # --- before_agent_callback ---
      if @before_agent_callback.is_a?(Proc)
        ADK.logger.debug { "Agent '#{@name}': Executing before_agent_callback." }
        begin
          override_content = @before_agent_callback.call(callback_context)
          if override_content.is_a?(Hash)
            ADK.logger.info { "Agent '#{@name}': before_agent_callback returned override content. Skipping main execution." }
            final_event = ADK::Event.new(role: :agent, content: override_content, state_delta: callback_context.pending_state_delta)
            session_service.append_event(session_id: session_id, event: final_event)
            # Store output if key defined (even for callback override)
            _store_output_in_session(final_event, session_id, session_service)
            return final_event
          end
        rescue StandardError => cb_err
          ADK.logger.error("Error in before_agent_callback for agent '#{@name}': #{cb_err.message}\n#{cb_err.backtrace.join("\n")}")
          final_event = ADK::Event.new(role: :agent, content: { status: :error, error_message: "Error in before_agent_callback: #{cb_err.message}" }, state_delta: callback_context.pending_state_delta)
          session_service.append_event(session_id: session_id, event: final_event)
          return final_event # Stop execution
        end
      end
      # --- End before_agent_callback ---

      # --- Log User Input & Apply Delta from before_agent_callback ---
      user_event = ADK::Event.new(role: :user, content: user_input, state_delta: callback_context.pending_state_delta)
      session_service.append_event(session_id: session_id, event: user_event)
      callback_context.clear_pending_state_delta! # Clear delta after applying
      # ---------------------------------------------------------------

      final_agent_event_content = nil
      plan_result = nil # To store plan from planner or callback

      # --- Plan Phase with Model Callbacks ---
      begin
        llm_request_for_callback = {
          prompt: "User: #{user_input}\nHistory: #{session.events.map(&:content).join("\n")}\nTools: ...", # Simplified
          model_config: { model_name: @model_name, temperature: @definition.temperature }
        }

        # --- before_model_callback ---
        if @before_model_callback.is_a?(Proc)
          ADK.logger.debug { "Agent '#{@name}': Executing before_model_callback." }
          begin
            # Create a new context for this specific callback if needed, or reuse/adapt callback_context
            model_cb_context = callback_context # Can reuse for now
            override_plan = @before_model_callback.call(model_cb_context, llm_request_for_callback) # Pass mutable request
            if override_plan.is_a?(Hash) && override_plan.key?(:steps) # Assuming plan is {steps: [...]}
              ADK.logger.info { "Agent '#{@name}': before_model_callback returned override plan. Skipping LLM call." }
              plan_result = override_plan
            end
            # Apply state delta from this callback to the next significant event (e.g., planning_result event)
            # For now, we'll assume the planner or execute_plan handles logging events with deltas.
          rescue StandardError => cb_err
            ADK.logger.error("Error in before_model_callback for agent '#{@name}': #{cb_err.message}")
            # Treat as planning failure
            plan_result = { error: "Error in before_model_callback: #{cb_err.message}" }
          end
        end
        # --- End before_model_callback ---

        # Actual planning if not overridden
        plan_result ||= @planner.plan(user_input) # planner.plan now expects only user_input

        # --- after_model_callback ---
        if @after_model_callback.is_a?(Proc) && !(plan_result && plan_result[:error]) # Don't run if planning already failed
          ADK.logger.debug { "Agent '#{@name}': Executing after_model_callback." }
          begin
            model_cb_context = callback_context # Can reuse
            modified_plan = @after_model_callback.call(model_cb_context, plan_result.dup) # Pass a copy
            plan_result = modified_plan if modified_plan.is_a?(Hash) && modified_plan.key?(:steps)
          rescue StandardError => cb_err
            ADK.logger.error("Error in after_model_callback for agent '#{@name}': #{cb_err.message}")
            # Don't override plan_result if after_model_callback errors, just log
          end
        end
        # --- End after_model_callback ---

        # Check if planning failed (either from planner or before_model_callback error)
        if plan_result.is_a?(Hash) && plan_result[:error]
          ADK.logger.error("Planning failed: #{plan_result[:error]}")
          final_agent_event_content = { status: :error, error_message: "Planning failed: #{plan_result[:error]}" }
        else
          # Proceed to execution
          execution_result = execute_plan(plan_result, session, session_service, invocation_id) # Pass invocation_id
          # Populate final_agent_event_content based on execution_result
          final_agent_event_content = execution_result[:last_result] || execution_result[:details]
          if final_agent_event_content.is_a?(Hash) && plan_result.is_a?(Hash) && plan_result[:thought_process]
            final_agent_event_content = final_agent_event_content.merge(thought_process: plan_result[:thought_process], plan_details: execution_result[:details])
          elsif final_agent_event_content.is_a?(Hash)
            final_agent_event_content = final_agent_event_content.merge(plan_details: execution_result[:details])
          end
        end

      rescue StandardError => e
        ADK.logger.error("Critical error during run_task (planning/execution) for session '#{session_id}': #{e.class} - #{e.message}\nBacktrace: #{e.backtrace.join("\n")}")
        final_agent_event_content = { status: :error, error_message: "An internal error occurred: #{e.message}" }
      end

      # Ensure final_agent_event_content is always a hash
      final_agent_event_content = { status: :error, error_message: 'Unknown internal error.' } unless final_agent_event_content.is_a?(Hash)

      # --- after_agent_callback ---
      final_event_state_delta = callback_context.pending_state_delta.dup # Capture any state changes from model callbacks
      callback_context.clear_pending_state_delta!

      if @after_agent_callback.is_a?(Proc)
        ADK.logger.debug { "Agent '#{@name}': Executing after_agent_callback." }
        begin
          modified_content = @after_agent_callback.call(callback_context, final_agent_event_content.dup)
          final_agent_event_content = modified_content if modified_content.is_a?(Hash)
          # Merge delta from this callback
          final_event_state_delta.merge!(callback_context.pending_state_delta)
        rescue StandardError => cb_err
          ADK.logger.error("Error in after_agent_callback for agent '#{@name}': #{cb_err.message}")
          # Don't change final_agent_event_content, but log the error. Delta from this callback won't be applied.
        end
      end
      # --- End after_agent_callback ---

      final_agent_event = ADK::Event.new(role: :agent, content: final_agent_event_content, state_delta: final_event_state_delta)
      session_service.append_event(session_id: session_id, event: final_agent_event)
      _store_output_in_session(final_agent_event, session_id, session_service)
      final_agent_event
    end
    # --- End Plan and Execute ---

    # --- MAS: Store result in session state if output_key is defined --- #
    def _store_output_in_session(event, session_id, session_service)
      return unless @definition.respond_to?(:output_key) && @definition.output_key && event

      output_value = event.content # Store the entire content hash
      serialized_value = begin
        JSON.parse(output_value.to_json) # Ensure serializable
      rescue => e
        ADK.logger.warn("Agent '#{@name}': Failed to serialize output value for session store: #{e.message}. Using original.")
        output_value
      end

      ADK.logger.info("Agent '#{@name}' storing output to session state key '#{@definition.output_key}' for session '#{session_id}'.")
      if session_service.respond_to?(:set_state)
        session_service.set_state(session_id: session_id, key: @definition.output_key, value: serialized_value)
      else
        ADK.logger.warn("Agent '#{@name}': Session service does not support :set_state for output_key.")
      end
    rescue StandardError => e
      ADK.logger.error("Agent '#{@name}': Failed to set state for output_key '#{@definition.output_key}': #{e.message}")
    end
    # --- End MAS State Management ---

    # --- Method for output storing, refactored from run_task ---
    # Returns the root agent in the hierarchy (the topmost agent with no parent)
    # @return [ADK::Agent] The root agent in the hierarchy
    def root_agent
      return self if @parent_agent.nil?

      @parent_agent.root_agent
    end

    # Finds an agent with the given name in the hierarchy using DFS
    # @param name_sym [Symbol] The name of the agent to find (as a symbol)
    # @return [ADK::Agent, nil] The agent with the given name, or nil if not found
    def find_agent(name_sym)
      # Convert to symbol if string provided
      name_sym = name_sym.to_sym if name_sym.is_a?(String)

      # Check if this is the agent we're looking for
      return self if @name.to_sym == name_sym

      # Search sub-agents recursively
      @sub_agents.each do |sub_agent|
        found = sub_agent.find_agent(name_sym)
        return found if found
      end

      # Not found in this branch
      nil
    end

    # Finds a direct sub-agent with the given name
    # @param name_sym [Symbol] The name of the sub-agent to find
    # @return [ADK::Agent, nil] The sub-agent with the given name, or nil if not found
    def find_sub_agent(name_sym)
      # Convert to symbol if string provided
      name_sym = name_sym.to_sym if name_sym.is_a?(String)

      # Handle the case where @sub_agents is a hash (key: name => value: agent)
      if @sub_agents.is_a?(Hash)
        return @sub_agents[name_sym]
      end

      # Handle the case where @sub_agents is an array of Agent objects
      if @sub_agents.is_a?(Array)
        return @sub_agents.find { |sub_agent| sub_agent.name.to_sym == name_sym }
      end

      # No sub-agents or invalid type
      ADK.logger.warn("No sub-agents found or invalid sub_agents type: #{@sub_agents.class}")
      nil
    end

    private

    # Helper method to consistently determine the tool name from a tool class.
    # Uses metadata, then deprecated @tool_name, then inferred_name.
    def get_tool_name_from_class(tool_class)
      return nil unless tool_class.is_a?(Class) && tool_class < ADK::Tool

      begin
        metadata = tool_class.tool_metadata
      rescue StandardError => e
        ADK.logger.error("Error calling tool_metadata on #{tool_class}: #{e.class} - #{e.message} - Backtrace: #{e.backtrace.first(3).join(' | ')}")
        metadata = {} # Default to empty hash if metadata call fails, for diagnosis
      end
      name = metadata[:name]&.to_sym

      if name.nil? || name == :''
        # Check deprecated @tool_name (instance variable on the class itself)
        if tool_class.instance_variable_defined?(:@tool_name)
          name = tool_class.instance_variable_get(:@tool_name)&.to_sym
          # ADK.logger.debug { "get_tool_name_from_class: Using name from deprecated @tool_name for #{tool_class}: #{name.inspect}" } if name
        end

        # If still no name, try inferred_name as a primary fallback if metadata[:name] is missing
        if (name.nil? || name == '') && tool_class.respond_to?(:inferred_name)
          name = tool_class.inferred_name
          # ADK.logger.debug { "get_tool_name_from_class: Using inferred_name for #{tool_class}: #{name.inspect}" } if name
        end
      end

      (name && name != :'') ? name : nil
    end

    # Discovers and loads tool definition files from specified paths.
    # @param paths [Array<String>] An array of directory paths to search.
    # @return [void]
    def _discover_and_load_tools(paths)
      return if paths.empty?

      ADK.logger.debug("Starting tool discovery in paths: #{paths.inspect}")

      paths.each do |path|
        absolute_dir_path = File.expand_path(path, Dir.pwd)

        unless Dir.exist?(absolute_dir_path)
          ADK.logger.warn("Tool discovery path does not exist or is not a directory: '#{path}' (resolved to '#{absolute_dir_path}'). Skipping.")
          next
        end

        Dir.glob(File.join(absolute_dir_path, '*.rb')).each do |absolute_file_path|
          begin
            ADK.logger.debug("Attempting to load tool file using 'require': #{absolute_file_path}")
            # Use require instead of load to prevent re-registration issues
            require absolute_file_path
            ADK.logger.debug("Successfully required (or already required): #{absolute_file_path}")
          rescue LoadError, SyntaxError => e
            ADK.logger.error("Failed to require/eval tool file '#{absolute_file_path}': #{e.class} - #{e.message}")
          rescue StandardError => e
            ADK.logger.error("Error encountered while requiring/processing tool file '#{absolute_file_path}': #{e.class} - #{e.message}")
          end
        end
      end
      ADK.logger.debug('Finished tool discovery.')
    end

    def execute_plan(plan, session, session_service, invocation_id) # Pass invocation_id
      session_id = session.id
      steps = plan[:steps] || (plan.is_a?(Array) ? plan : [])
      # ... (rest of existing execute_plan logic before the loop) ...
      # (Handle empty plan based on fallback mode as before)
      if steps.empty?
        # ... (existing fallback logic) ...
      end

      previous_step_result_hash = nil
      plan_execution_details = []
      last_successful_or_pending_result = nil

      steps.each_with_index do |step, index|
        # --- Input Injection Logic (remains the same) ---
        current_params = step[:params].dup
        # ... (injection logic) ...
        step_with_injected_params = step.merge(params: current_params)
        # --- End Input Injection Logic ---

        # --- MODIFIED: Pass invocation_id to execute_step ---
        current_result_hash = execute_step(step_with_injected_params, session, session_service, invocation_id)
        # --- END MODIFICATION ---

        # ... (rest of result sanitization and plan detail storage logic) ...
        # ... (error checking and break logic) ...
        sanitized_result_for_plan = {} # Placeholder for sanitization logic
        # ... (actual sanitization based on current_result_hash) ...
        plan_execution_details << { tool_name: step[:tool], params: current_params, result: sanitized_result_for_plan }

        if current_result_hash[:status] == :error
          ADK.logger.warn("Step #{index + 1} failed, stopping plan execution: #{current_result_hash[:error_message]}")
          last_successful_or_pending_result = current_result_hash
          break
        else
          previous_step_result_hash = current_result_hash
          last_successful_or_pending_result = current_result_hash
        end
      end
      { details: plan_execution_details, last_result: last_successful_or_pending_result }
    end

    # --- MODIFIED: execute_step now accepts invocation_id ---
    def execute_step(step, session, session_service, invocation_id)
      session_id = session.id
      tool_name_from_step = step[:tool]
      original_params = step[:params]
      final_tool_name_to_execute = tool_name_from_step
      params_for_execution = original_params.dup

      # --- Agent Delegation Logic ---
      if tool_name_from_step.to_s.start_with?('agent_transfer_to_')
        target_agent_name_from_pseudo_tool = tool_name_from_step.to_s.sub('agent_transfer_to_', '').to_sym
        delegation_task = original_params[:task] || original_params['task']

        unless delegation_task
          # ... (handle missing task error) ...
          return { status: :error, error_message: "Missing task for delegation to #{target_agent_name_from_pseudo_tool}", error_class: 'DelegationError' }
        end
        final_tool_name_to_execute = :delegate_task
        params_for_execution = {
          target_agent_name: target_agent_name_from_pseudo_tool.to_s,
          task: delegation_task
        }
        ADK.logger.info "Mapping planner step '#{tool_name_from_step}' to :delegate_task for '#{target_agent_name_from_pseudo_tool}'"
      end
      # --- End Agent Delegation ---

      # --- Existing Sequential Sub-Agent Logic (if applicable) ---
      # ... (This seems to be handled by SequentialAgent's run_task now, Agent#execute_step focuses on tools/delegation) ...

      # --- Log Tool Request Event ---
      request_event_content = params_for_execution.dup # Ensure we log the actual params being sent to the tool
      # For delegation, log the conceptual tool name for clarity
      tool_name_for_request_event = tool_name_from_step # This will be agent_transfer_to_X if it was delegation
      request_event = ADK::Event.new(role: :tool_request, tool_name: tool_name_for_request_event, content: request_event_content)
      session_service.append_event(session_id: session_id, event: request_event)


      # --- Tool Execution with Callbacks ---
      tool_instance = @tool_registry.create_instance(final_tool_name_to_execute) # Now uses final_tool_name_to_execute
      unless tool_instance
        # ... (handle tool not found) ...
        return { status: :error, error_message: "Tool '#{final_tool_name_to_execute}' not found.", error_class: 'ToolNotFound' }
      end

      tool_context = ADK::ToolContext.new(
        session_id: session.id, user_id: session.user_id, app_name: session.app_name,
        tool_registry: @tool_registry, session_service: @session_service, # Pass session_service
        invocation_id: invocation_id # Pass invocation_id
      )
      current_result_hash = nil

      # --- before_tool_callback ---
      if @before_tool_callback.is_a?(Proc)
        ADK.logger.debug { "Agent '#{@name}': Executing before_tool_callback for tool '#{final_tool_name_to_execute}'." }
        begin
          override_result = @before_tool_callback.call(tool_instance, params_for_execution.dup, tool_context)
          if override_result.is_a?(Hash)
            ADK.logger.info { "Agent '#{@name}': before_tool_callback returned override result for '#{final_tool_name_to_execute}'. Skipping tool execution." }
            current_result_hash = override_result
          end
        rescue StandardError => cb_err
          ADK.logger.error("Error in before_tool_callback for tool '#{final_tool_name_to_execute}': #{cb_err.message}")
          current_result_hash = { status: :error, error_message: "Error in before_tool_callback: #{cb_err.message}", error_class: cb_err.class.name }
        end
      end
      # --- End before_tool_callback ---

      # Actual tool execution if not overridden/errored
      unless current_result_hash
        begin
          current_result_hash = tool_instance.execute(params_for_execution, tool_context)
          # ... (existing validation of tool result hash) ...
        rescue ADK::ToolError => e
          current_result_hash = { status: :error, error_message: e.message, error_class: e.class.name, result: nil }
        rescue StandardError => e
          current_result_hash = { status: :error, error_message: "Internal error executing tool '#{final_tool_name_to_execute}': #{e.message}", error_class: e.class.name, result: nil }
        end
      end

      # --- after_tool_callback ---
      # Also capture any state delta from before_tool_callback
      tool_event_state_delta = tool_context.pending_state_delta.dup
      tool_context.clear_pending_state_delta!

      if @after_tool_callback.is_a?(Proc) && current_result_hash && current_result_hash[:status] != :error # Don't run if tool errored or was skipped due to before_tool_callback error
        ADK.logger.debug { "Agent '#{@name}': Executing after_tool_callback for tool '#{final_tool_name_to_execute}'." }
        begin
          modified_result = @after_tool_callback.call(tool_instance, params_for_execution.dup, tool_context, current_result_hash.dup)
          current_result_hash = modified_result if modified_result.is_a?(Hash)
          # Merge delta from this callback
          tool_event_state_delta.merge!(tool_context.pending_state_delta)
        rescue StandardError => cb_err
          ADK.logger.error("Error in after_tool_callback for tool '#{final_tool_name_to_execute}': #{cb_err.message}")
          # Log error, but use result from before this callback. Delta from this callback is lost.
        end
      end
      # --- End after_tool_callback ---

      # Log Tool Result Event, using conceptual tool name if delegation occurred
      tool_name_for_result_event = tool_name_from_step
      result_event = ADK::Event.new(role: :tool_result, tool_name: tool_name_for_result_event, content: current_result_hash, state_delta: tool_event_state_delta)
      session_service.append_event(session_id: session_id, event: result_event)

      current_result_hash
    end


    # Connects to all configured MCP servers.
    def connect_mcp_servers
      # Return early if no MCP servers configured
      return if @mcp_servers_config.nil? || @mcp_servers_config.empty?

      @mcp_servers_config.each do |config|
        # Transform keys to symbols for the client
        symbolized_config = config.transform_keys(&:to_sym)
        ADK.logger.info("Attempting to connect to MCP server: #{symbolized_config.inspect}")
        begin
          # --- FIXED: Check using STRING key 'type' --- >
          unless %w[stdio sse].include?(symbolized_config[:type].to_s) # Convert symbol to string for include? check
            # --- FIXED: Log the actual value found using string key ---\
            ADK.logger.error("Unsupported MCP server type specified: #{symbolized_config[:type].inspect}. Skipping configuration: #{symbolized_config.inspect}")
            next # Skip to the next server config
          end
          # <-----------------------------

          # --- NEW: Explicitly convert known string type values to symbols ---
          if symbolized_config[:type].to_s == 'stdio' # Convert to string for comparison
            symbolized_config[:type] = :stdio
          elsif symbolized_config[:type].to_s == 'sse' # Convert to string for comparison
            symbolized_config[:type] = :sse
          end
          # Pass the modified hash
          client = ADK::Mcp::Client.new(symbolized_config)
          client.connect # This performs handshake and gets capabilities
          @mcp_clients << client
          discover_and_register_mcp_tools(client)
        rescue ADK::Mcp::ConnectionError, ADK::Mcp::ProtocolError => e # More specific MCP errors
          ADK.logger.error("Failed to connect or handshake with MCP server #{config.inspect}: #{e.message}")
        rescue ADK::Mcp::McpError => e # Catch specific MCP errors (typo fix: Error -> McpError)
          ADK.logger.error("MCP-related error connecting to server #{config.inspect}: #{e.message}")
        rescue StandardError => e
          ADK.logger.error("Unexpected error connecting to MCP server #{config.inspect}: #{e.class} - #{e.message}")
        end
      end
    end

    # Disconnects all active MCP clients.
    def disconnect_mcp_servers
      return if @mcp_clients.nil? || @mcp_clients.empty?

      @mcp_clients.each do |client|
        begin
          ADK.logger.info('Disconnecting MCP client...')
          client.disconnect
        rescue StandardError => e
          ADK.logger.error("Error disconnecting MCP client: #{e.message}")
        end
      end
      @mcp_clients.clear
    end

    # Discovers tools from a connected MCP client and registers them with the agent's registry.
    # @param client [ADK::Mcp::Client]
    def discover_and_register_mcp_tools(client)
      ADK.logger.debug("[Agent E2E Debug] discover_and_register - @tool_registry ID: #{@tool_registry.object_id}")
      begin
        mcp_tool_schemas = client.list_tools
        ADK.logger.debug("[Agent E2E Debug] list_tools returned: #{mcp_tool_schemas.inspect}")
        ADK.logger.info("Discovered #{mcp_tool_schemas.count} tools from MCP server.")
        mcp_tool_schemas.each do |schema|
          # --- ADDED check: Only register if tool was selected ---
          tool_name_sym = schema[:name].to_sym
          if @selected_tool_names.include?(tool_name_sym)
            # Pass the agent's specific registry instance (@tool_registry)
            ADK::Mcp::ToolWrapper.from_mcp_schema(schema, client, @tool_registry)
          else
            ADK.logger.debug("Skipping registration of MCP tool '#{tool_name_sym}' as it was not selected in agent definition.")
          end
          # --- END check ---
        end
      rescue ADK::Mcp::McpError => e # Corrected typo: Error -> McpError
        ADK.logger.error("Failed to list tools from MCP server: #{e.message}")
      rescue StandardError => e
        ADK.logger.error("Unexpected error discovering MCP tools: #{e.class} - #{e.message}")
      end
    end

    # --- Session Service Initialization Helpers --- #
    def initialize_session_service_from_definition
      # When initialized from definition (worker), rely on ADK global config by default
      # unless a specific service was passed in.
      ADK.config.session_service
    end

    def initialize_session_service_from_args
      # When initialized from args (direct use), rely on ADK global config.
      ADK.config.session_service
    end
    # --- End Session Service Initialization Helpers --- #

    # Helper method to check for circular dependencies in the agent hierarchy
    # @param new_sub_agent_name [Symbol] The name of the new sub-agent to check for cycles
    # @raise [ADK::ConfigurationError] If a circular dependency is detected
    private def _check_circular_dependency(new_sub_agent_name)
      # Direct self-reference check
      if new_sub_agent_name == @name
        raise ADK::ConfigurationError, "Circular dependency detected: Agent '#{@name}' cannot include itself as a sub-agent"
      end

      # Check if the sub-agent would create an indirect circular reference
      # by traversing up the parent chain (backwards check)
      current_agent = self
      ancestry_path = [@name]

      while (parent = current_agent.parent_agent)
        # If any parent has the same name as the new sub-agent, it's a circular reference
        if parent.name == new_sub_agent_name
          circular_path = [new_sub_agent_name] + ancestry_path
          raise ADK::ConfigurationError, "Circular dependency detected: #{circular_path.join(' → ')}"
        end

        ancestry_path.unshift(parent.name)
        current_agent = parent
      end
    end
  end # End Agent class
end # End ADK module
```

I've also updated `ADK::AgentDefinition` to include DSL methods for registering these callbacks and modified `ADK::ToolContext` to include `session_service`, `logger`, `invocation_id`, and the state management methods. The `ADK::Planner` will need adjustment if model callbacks are to be handled within it, but the current plan is for the `Agent` to manage those around the `planner.plan` call.