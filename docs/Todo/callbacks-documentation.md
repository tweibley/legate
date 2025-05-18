Okay, here is the documentation for the new callback system. This will be a new file, `public/docs/advanced/callbacks.md`.

```markdown
# ADK Callbacks: Observe, Customize, and Control Agent Behavior

## Introduction: What are Callbacks and Why Use Them?

Callbacks are a cornerstone feature of the Ruby ADK, providing a powerful mechanism to hook into an agent's execution process. They allow you to observe, customize, and even control the agent's behavior at specific, predefined points without modifying the core ADK framework code.

**What are they?** In essence, callbacks are standard Ruby Procs or lambdas that you define. You then associate these functions with an agent when you create its `ADK::AgentDefinition`. The ADK framework automatically calls your functions at key stages, letting you observe or intervene. Think of it like checkpoints during the agent's process:

*   **Agent Lifecycle:**
    *   `before_agent_callback`: Executes right before the agent's main work begins for a specific `run_task` request.
    *   `after_agent_callback`: Executes right after the agent has finished all its steps for that request and has prepared the final result, but just before the result is returned from `run_task`.
*   **Model Interaction (LLM):**
    *   `before_model_callback`: Runs just before a request is made to the Large Language Model (LLM) by the `ADK::Planner`.
    *   `after_model_callback`: Runs immediately after a response is received from the LLM by the `ADK::Planner`.
*   **Tool Execution:**
    *   `before_tool_callback`: Called just before a specific tool's `execute` method is invoked by the agent.
    *   `after_tool_callback`: Called immediately after a tool's `execute` method successfully completes (before its result is further processed by the agent).

**Why use them?** Callbacks unlock significant flexibility and enable advanced agent capabilities:

*   **Observe & Debug:** Log detailed information at critical steps for monitoring and troubleshooting.
*   **Customize & Control:** Modify data flowing through the agent (like LLM requests or tool results) or even bypass certain steps entirely based on your logic.
*   **Implement Guardrails:** Enforce safety rules, validate inputs/outputs, or prevent disallowed operations.
*   **Manage State:** Read or dynamically update the agent's session state during execution via the provided context object.
*   **Integrate & Enhance:** Trigger external actions (API calls, notifications) or add features like caching.

**How are they added?** You register callbacks by assigning Procs to the relevant attributes in the `ADK::AgentDefinition` block:

```ruby
# lib/adk/callbacks/callback_context.rb (Conceptual - needs to be defined)
# module ADK
#   module Callbacks
#     class CallbackContext
#       attr_reader :agent_name, :invocation_id, :session_id, :user_id, :app_name, :session_service, :logger
#       # ... (methods like state_get, state_set)
#     end
#   end
# end

# lib/adk/tool_context.rb (Conceptual - needs to be enhanced)
# module ADK
#   class ToolContext
#     # ... (existing attributes + session_service, logger, invocation_id, state methods)
#   end
# end

# --- Define your callback function ---
my_before_model_callback_proc = lambda do |callback_context, llm_request_params|
  # callback_context is ADK::Callbacks::CallbackContext
  # llm_request_params is a Hash representing what would be sent to the LLM
  puts "[Callback] Before model call for agent: #{callback_context.agent_name}"
  # ... your custom logic here ...

  # Example: Modify the request
  llm_request_params[:prompt] = "Prefix: " + llm_request_params[:prompt]

  return nil # Allow the model call to proceed with (potentially modified) request
end

# --- Register it during AgentDefinition ---
ADK::Agent.define do |a|
  a.name :my_callback_agent
  a.model_name "gemini-2.0-flash"
  a.instruction "Be helpful."
  # ... other agent parameters ...

  a.before_model_callback(&my_before_model_callback_proc)
end
```

## The Callback Mechanism: Interception and Control

When the ADK framework encounters a point where a callback can run (e.g., just before calling the LLM), it checks if you provided a corresponding callback Proc for that agent. If you did, the framework executes your Proc.

**Context is Key:** Your callback Proc isn't called in isolation. The framework provides special context objects (`ADK::Callbacks::CallbackContext` or `ADK::ToolContext`) as arguments. These objects contain vital information about the current state of the agent's execution, including the invocation details, session state, and access to services like the session service and logger.

**Controlling the Flow (The Core Mechanism):** The most powerful aspect of callbacks lies in how their return value influences the agent's subsequent actions.

*   **`return nil` (or last expression evaluates to `nil`): Allow Default Behavior**
    *   This is the standard way to signal that your callback has finished its work (e.g., logging, inspection, minor modifications to mutable input arguments) and that the ADK agent should proceed with its normal operation.
    *   For `before_*` callbacks, returning `nil` means the next step in the sequence (running the agent logic, calling the LLM, executing the tool) will occur.
    *   For `after_*` callbacks, returning `nil` means the result just produced by the preceding step (the agent's output, the LLM's response, the tool's result) will be used as is.

*   **`return <Specific Object>` (Override Default Behavior / Replace Result):**
    *   Returning a specific type of object (instead of `nil`) is how you override the ADK agent's default behavior or replace a result.
    *   **`before_agent_callback` &rarr; `Hash` (Agent Content):** Skips the agent's main `run_task` logic. The returned Hash is treated as the agent's final output content for this turn.
    *   **`before_model_callback` &rarr; `Hash` (Planner Plan):** Skips the call to the external Large Language Model by the `ADK::Planner`. The returned Hash (expected plan structure) is used as if it were the response from the LLM.
    *   **`before_tool_callback` &rarr; `Hash` (Tool Result):** Skips the execution of the actual tool's `execute` method. The returned Hash (standard tool result format, e.g., `{status: :success, result: ...}`) is used as the result of the tool call.
    *   **`after_agent_callback` &rarr; `Hash` (Agent Content):** Replaces the content Hash that the agent's `run_task` logic just produced.
    *   **`after_model_callback` &rarr; `Hash` (Planner Plan):** Replaces the plan Hash received from the LLM.
    *   **`after_tool_callback` &rarr; `Hash` (Tool Result):** Replaces the result Hash returned by the tool's `execute` method.

**State Management in Callbacks:**
Callbacks can read from and write to the session state using methods on the `callback_context` or `tool_context` (e.g., `context.state_get(:my_key)`, `context.state_set(:my_key, 'new_value')`).
Changes made via `state_set` or `state_update` are collected in a `pending_state_delta` within the context object.
The ADK framework automatically merges this `pending_state_delta` into the `state_delta` of the *next relevant ADK::Event* that is logged to the session history. This ensures state changes are tied to specific points in the execution flow.

## Types of Callbacks

### 1. Agent Lifecycle Callbacks (`ADK::Agent`)

These callbacks hook into the overall execution of an agent's `run_task` method.

#### `before_agent_callback`

*   **When:** Called immediately *before* the agent's main `run_task` logic begins (after session retrieval but before planning or tool execution for that task).
*   **Signature:** `lambda { |callback_context| ... }`
    *   `callback_context` (`ADK::Callbacks::CallbackContext`): Provides agent name, invocation ID, session details, session service, logger, and state access methods.
*   **Purpose:**
    *   Initial setup or validation for a specific task run.
    *   Logging entry into the agent's task processing.
    *   Access control: Decide if the agent should even process the current request.
    *   Modifying initial session state for the current invocation via `callback_context.state_set`.
*   **Return Value Effect:**
    *   `nil`: Agent proceeds with its normal `run_task` logic (planning, execution).
    *   `Hash` (Agent Content, e.g., `{status: :success, result: "Handled by callback"}`): Agent's main logic for `run_task` is skipped. The returned Hash becomes the content of the final agent event for this turn.

```ruby
# Example: before_agent_callback
ADK::Agent.define do |a|
  a.name :my_guarded_agent
  # ...
  a.before_agent_callback do |context|
    if context.state_get(:user_flagged)
      puts "[Callback] User #{context.user_id} is flagged. Skipping agent run."
      context.state_set(:agent_skipped_reason, "User flagged")
      { status: :error, error_message: "Access denied for this request." } # Override
    else
      puts "[Callback] User #{context.user_id} is not flagged. Proceeding."
      nil # Proceed
    end
  end
end
```

#### `after_agent_callback`

*   **When:** Called *after* the agent's `run_task` logic has fully completed and generated its final response content, but *before* that final `ADK::Event` is returned from `run_task`.
*   **Signature:** `lambda { |callback_context, agent_response_content| ... }`
    *   `callback_context` (`ADK::Callbacks::CallbackContext`)
    *   `agent_response_content` (`Hash`): A mutable copy of the content hash that the agent is about to return (e.g., `{status: :success, result: ..., plan_details: ...}`).
*   **Purpose:**
    *   Post-processing the agent's final response.
    *   Logging the outcome of the agent's task.
    *   Final state modifications based on the agent's overall result.
    *   Adding standard disclaimers or formatting to all agent outputs.
*   **Return Value Effect:**
    *   `nil`: The `agent_response_content` (potentially modified in place by the callback) is used as the final agent event content.
    *   `Hash` (Agent Content): The returned Hash *replaces* the agent's original `agent_response_content`.

```ruby
# Example: after_agent_callback
ADK::Agent.define do |a|
  a.name :my_response_modifier_agent
  # ...
  a.after_agent_callback do |context, response_content|
    puts "[Callback] Agent finished. Original response content: #{response_content.inspect}"
    if response_content[:status] == :success
      response_content[:result] = "[MODIFIED] #{response_content[:result]}"
      context.state_set(:last_response_modified, true)
    end
    # If you return nil, the (modified) response_content is used.
    # Or, you could return a completely new Hash:
    # { status: :success, result: "New result from callback", original_was: response_content }
    nil
  end
end
```

### 2. Model Interaction Callbacks (`ADK::Planner` via `ADK::Agent`)

These callbacks hook into the `ADK::Planner`'s interaction with the LLM. The `ADK::Agent` orchestrates these callbacks around its call to the planner.

#### `before_model_callback`

*   **When:** Called just *before* the `ADK::Planner` makes a request to the LLM (e.g., to generate a plan).
*   **Signature:** `lambda { |callback_context, llm_request_params| ... }`
    *   `callback_context` (`ADK::Callbacks::CallbackContext`): Provides agent/session context.
    *   `llm_request_params` (`Hash`): A mutable hash representing the parameters that will be sent to the LLM (e.g., `{ prompt: "...", model_config: {...} }`). Modifications to this hash will affect the actual LLM call.
*   **Purpose:**
    *   Inspect or modify the prompt/request being sent to the LLM.
    *   Implement input guardrails (e.g., block certain prompts).
    *   Inject dynamic information into the prompt from session state.
    *   Implement request-level caching (return a cached plan).
*   **Return Value Effect:**
    *   `nil`: The planner proceeds to call the LLM with the (potentially modified) `llm_request_params`.
    *   `Hash` (Planner Plan, e.g., `{ steps: [...] }` or `{ error: "..." }`): The planner skips the actual LLM call and uses this returned Hash as if it were the LLM's response.

```ruby
# Example: before_model_callback
ADK::Agent.define do |a|
  a.name :my_prompt_injector_agent
  # ...
  a.before_model_callback do |context, request_params|
    user_preference = context.state_get(:user_style_preference)
    if user_preference
      request_params[:prompt] += "\nStyle hint: #{user_preference}"
    end
    
    if request_params[:prompt].include?("forbidden topic")
      puts "[Callback] Forbidden topic detected in prompt. Blocking LLM call."
      { error: "Request blocked due to content policy." } # Override
    else
      nil # Proceed
    end
  end
end
```

#### `after_model_callback`

*   **When:** Called *after* the `ADK::Planner` receives a response from the LLM, but *before* the planner fully processes this response into its internal plan structure.
*   **Signature:** `lambda { |callback_context, llm_response_data| ... }`
    *   `callback_context` (`ADK::Callbacks::CallbackContext`)
    *   `llm_response_data` (`Hash`): A mutable copy of the raw-ish response data from the LLM (e.g., the parsed JSON string that the planner will then interpret into steps).
*   **Purpose:**
    *   Inspect or modify the LLM's raw response.
    *   Sanitize LLM output.
    *   Log LLM responses for analysis or fine-tuning.
    *   Parse structured data from the LLM output and store it in session state.
*   **Return Value Effect:**
    *   `nil`: The (potentially modified in place) `llm_response_data` is used by the planner.
    *   `Hash` (Planner Plan): The returned Hash *replaces* the LLM's original response.

```ruby
# Example: after_model_callback
ADK::Agent.define do |a|
  a.name :my_llm_response_logger_agent
  # ...
  a.after_model_callback do |context, llm_response|
    puts "[Callback] LLM Response received: #{llm_response.inspect}"
    context.state_set(:last_llm_raw_output, llm_response)

    if llm_response.is_a?(Hash) && llm_response.dig(:plan, 0, :tool_name) == :risky_tool
      puts "[Callback] LLM planned risky_tool. Modifying plan to use safe_tool instead."
      llm_response[:plan][:tool_name] = :safe_tool # Modify in place
    end
    nil # Use the (potentially modified) llm_response
  end
end
```

### 3. Tool Execution Callbacks (`ADK::Agent`)

These callbacks hook into the agent's execution of individual tools.

#### `before_tool_callback`

*   **When:** Called *before* a specific tool's `execute` method is invoked by the agent.
*   **Signature:** `lambda { |tool_instance, tool_args, tool_context| ... }`
    *   `tool_instance` (`ADK::Tool`): The instance of the tool about to be executed.
    *   `tool_args` (`Hash`): A mutable hash of the arguments that will be passed to the tool.
    *   `tool_context` (`ADK::ToolContext`): Context specific to this tool execution, providing session details, access to the agent's tool registry, session service, logger, invocation ID, and state methods.
*   **Purpose:**
    *   Inspect or modify tool arguments before execution.
    *   Implement tool-specific input validation or authorization.
    *   Log tool usage attempts.
    *   Implement tool-level caching (return a cached result).
*   **Return Value Effect:**
    *   `nil`: The tool's `execute` method is called with the (potentially modified) `tool_args`.
    *   `Hash` (Tool Result, e.g. `{status: :success, result: ...}`): The tool's `execute` method is skipped. The returned Hash is used as the result of the tool call.

```ruby
# Example: before_tool_callback
ADK::Agent.define do |a|
  a.name :my_tool_caching_agent
  # ...
  a.before_tool_callback do |tool, args, context|
    if tool.name == :expensive_api_call
      cache_key = "cache:#{tool.name}:#{args.to_json}"
      cached_result = context.state_get(cache_key)
      if cached_result
        puts "[Callback] Cache hit for #{tool.name}! Returning cached result."
        return cached_result # Override: return cached result
      end
    end
    args[:timestamp] = Time.now.iso8601 # Modify args
    nil # Proceed with actual tool call
  end
end
```

#### `after_tool_callback`

*   **When:** Called *after* a tool's `execute` method successfully completes and returns its result hash, but *before* this result is further processed or logged by the agent. It does *not* run if the tool's `execute` method itself raised an unhandled exception.
*   **Signature:** `lambda { |tool_instance, tool_args, tool_context, tool_result| ... }`
    *   `tool_instance` (`ADK::Tool`)
    *   `tool_args` (`Hash`): The (potentially modified by `before_tool_callback`) arguments that were passed to the tool.
    *   `tool_context` (`ADK::ToolContext`)
    *   `tool_result` (`Hash`): A mutable copy of the result hash returned by the tool's `execute` method.
*   **Purpose:**
    *   Inspect or modify the tool's result.
    *   Log tool execution outcomes.
    *   Post-process or format tool results.
    *   Save tool results to a cache or session state.
*   **Return Value Effect:**
    *   `nil`: The (potentially modified in place) `tool_result` is used by the agent.
    *   `Hash` (Tool Result): The returned Hash *replaces* the tool's original `tool_result`.

```ruby
# Example: after_tool_callback
ADK::Agent.define do |a|
  a.name :my_tool_result_processor_agent
  # ...
  a.after_tool_callback do |tool, args, context, result|
    puts "[Callback] Tool #{tool.name} executed with #{args.inspect}. Result: #{result.inspect}"
    if tool.name == :expensive_api_call && result[:status] == :success
      cache_key = "cache:#{tool.name}:#{args.to_json}"
      context.state_set(cache_key, result.dup) # Save a copy to state for caching
      puts "[Callback] Saved result for #{tool.name} to cache."
    end

    if result[:status] == :success && result[:result].is_a?(String)
      result[:result] = result[:result].upcase # Modify result in place
    end
    nil # Use the modified result
  end
end
```

## Design Patterns and Best Practices for Callbacks

(This section would adapt the "Design Patterns and Best Practices" from your Python ADK documentation, translating concepts and examples to Ruby where appropriate. Key patterns would include Guardrails, Dynamic State Management, Logging, Caching, Request/Response Modification, Conditional Skipping, etc., with Ruby-specific syntax for Procs, Hashes, and context object interactions.)

By understanding this callback mechanism, you can precisely control the agent's execution path, making callbacks an essential tool for building sophisticated and reliable agents with the Ruby ADK.
```

This documentation should provide a solid starting point for users to understand and leverage the callback system you're planning. Remember to update the conceptual `CallbackContext` and `ToolContext` definitions in the examples once their final Ruby implementation is in place.