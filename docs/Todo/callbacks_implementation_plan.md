# ADK Callbacks Implementation Plan

## Current Status

We've completed the foundational components needed for callbacks:

1. Created `lib/adk/callbacks/callback_context.rb` - Context object passed to callbacks with state management capabilities
2. Updated `lib/adk/tool_context.rb` - Enhanced with state management similar to CallbackContext
3. Started `spec/adk/callbacks_spec.rb` - Tests for callback functionality

## Next Steps

### 1. Update `ADK::Agent#run_task` Method

The `run_task` method needs to be modified to include the following:

```ruby
def run_task(session_id:, user_input:, session_service:)
  # Existing pre-execution checks
  # ...

  # Generate invocation_id and create callback context
  invocation_id = SecureRandom.uuid
  callback_context = ADK::Callbacks::CallbackContext.new(
    agent_name: @name, 
    invocation_id: invocation_id,
    session_id: session.id, 
    user_id: session.user_id, 
    app_name: session.app_name,
    session_service: session_service, 
    logger: ADK.logger
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
        _store_output_in_session(final_event, session_id, session_service)
        return final_event
      end
    rescue StandardError => cb_err
      ADK.logger.error("Error in before_agent_callback for agent '#{@name}': #{cb_err.message}\n#{cb_err.backtrace.join("\n")}")
      final_event = ADK::Event.new(role: :agent, content: { status: :error, error_message: "Error in before_agent_callback: #{cb_err.message}" }, state_delta: callback_context.pending_state_delta)
      session_service.append_event(session_id: session_id, event: final_event)
      return final_event
    end
  end

  # Log user input and capture any state changes from before_agent_callback
  user_event = ADK::Event.new(role: :user, content: user_input, state_delta: callback_context.pending_state_delta)
  session_service.append_event(session_id: session_id, event: user_event)
  callback_context.clear_pending_state_delta!

  # --- Plan Phase with Model Callbacks ---
  begin
    # Prepare request params for model callbacks
    llm_request_params = { 
      prompt: "User: #{user_input}\nHistory: #{session.events.map(&:content).join("\n")}\nTools: ...", 
      model_config: { model_name: @model_name, temperature: @definition.temperature }
    }

    # --- before_model_callback ---
    if @before_model_callback.is_a?(Proc)
      ADK.logger.debug { "Agent '#{@name}': Executing before_model_callback." }
      begin
        override_plan = @before_model_callback.call(callback_context, llm_request_params)
        if override_plan.is_a?(Hash) && override_plan.key?(:steps)
          ADK.logger.info { "Agent '#{@name}': before_model_callback returned override plan. Skipping LLM call." }
          plan = override_plan
        end
      rescue StandardError => cb_err
        ADK.logger.error("Error in before_model_callback for agent '#{@name}': #{cb_err.message}")
        plan = { error: "Error in before_model_callback: #{cb_err.message}" }
      end
    end

    # Call the planner if we didn't get an override from before_model_callback
    plan ||= @planner.plan(user_input)

    # --- after_model_callback ---
    if @after_model_callback.is_a?(Proc) && !(plan && plan[:error])
      ADK.logger.debug { "Agent '#{@name}': Executing after_model_callback." }
      begin
        modified_plan = @after_model_callback.call(callback_context, plan.dup)
        plan = modified_plan if modified_plan.is_a?(Hash) && modified_plan.key?(:steps)
      rescue StandardError => cb_err
        ADK.logger.error("Error in after_model_callback for agent '#{@name}': #{cb_err.message}")
        # Don't override the plan if callback errors
      end
    end

    # Check if planning failed (after callbacks)
    if plan.is_a?(Hash) && plan[:error]
      ADK.logger.error("Planning failed: #{plan[:error]}")
      final_agent_event_content = { 
        status: :error, 
        error_message: "Planning failed: #{plan[:error]}" 
      }
    else
      # Execute plan with invocation_id
      execution_result = execute_plan(plan, session, session_service, invocation_id)
      
      # Create final agent content
      final_agent_event_content = execution_result[:last_result] || execution_result[:details]
      if final_agent_event_content.is_a?(Hash) && plan.is_a?(Hash) && plan[:thought_process]
        final_agent_event_content = final_agent_event_content.merge(
          thought_process: plan[:thought_process], 
          plan_details: execution_result[:details]
        )
      elsif final_agent_event_content.is_a?(Hash)
        final_agent_event_content = final_agent_event_content.merge(
          plan_details: execution_result[:details]
        )
      end
    end
  rescue StandardError => e
    ADK.logger.error("Critical error during run_task: #{e.message}\n#{e.backtrace.join("\n")}")
    final_agent_event_content = { status: :error, error_message: "An internal error occurred: #{e.message}" }
  end

  # Ensure final_agent_event_content is always a hash
  final_agent_event_content = { status: :error, error_message: 'Unknown internal error.' } unless final_agent_event_content.is_a?(Hash)

  # --- after_agent_callback ---
  final_event_state_delta = callback_context.pending_state_delta.dup
  callback_context.clear_pending_state_delta!

  if @after_agent_callback.is_a?(Proc)
    ADK.logger.debug { "Agent '#{@name}': Executing after_agent_callback." }
    begin
      modified_content = @after_agent_callback.call(callback_context, final_agent_event_content.dup)
      final_agent_event_content = modified_content if modified_content.is_a?(Hash)
      final_event_state_delta.merge!(callback_context.pending_state_delta)
    rescue StandardError => cb_err
      ADK.logger.error("Error in after_agent_callback for agent '#{@name}': #{cb_err.message}")
      # Continue with original final_agent_event_content
    end
  end

  # Create and log final event
  final_agent_event = ADK::Event.new(role: :agent, content: final_agent_event_content, state_delta: final_event_state_delta)
  session_service.append_event(session_id: session_id, event: final_agent_event)
  
  # Store output if configured
  _store_output_in_session(final_agent_event, session_id, session_service)
  
  # Return final event
  final_agent_event
end
```

### 2. Update `execute_plan` Method

The `execute_plan` method should pass along the `invocation_id` to `execute_step`:

```ruby
def execute_plan(plan, session, session_service, invocation_id)
  session_id = session.id
  steps = plan[:steps] || (plan.is_a?(Array) ? plan : [])
  
  # Existing code for empty plan handling
  # ...

  previous_step_result_hash = nil
  plan_execution_details = []
  last_successful_or_pending_result = nil

  steps.each_with_index do |step, index|
    # Existing code for input injection
    # ...
    
    # Pass invocation_id to execute_step
    current_result_hash = execute_step(step_with_injected_params, session, session_service, invocation_id)
    
    # Existing result handling code
    # ...
  end
  
  { details: plan_execution_details, last_result: last_successful_or_pending_result }
end
```

### 3. Update `execute_step` Method

The `execute_step` method needs a significant update to add the callback hooks:

```ruby
def execute_step(step, session, session_service, invocation_id)
  session_id = session.id
  tool_name_from_step = step[:tool]
  original_params = step[:params]
  final_tool_name_to_execute = tool_name_from_step
  params_for_execution = original_params.dup

  # Existing code for tool/delegation selection
  # ...
  
  # --- Log Tool Request Event ---
  request_event_content = params_for_execution.dup
  tool_name_for_request_event = tool_name_from_step
  request_event = ADK::Event.new(role: :tool_request, tool_name: tool_name_for_request_event, content: request_event_content)
  session_service.append_event(session_id: session_id, event: request_event)

  # --- Tool Execution with Callbacks ---
  tool_instance = @tool_registry.create_instance(final_tool_name_to_execute)
  unless tool_instance
    error_result = { status: :error, error_message: "Tool '#{final_tool_name_to_execute}' not found.", error_class: 'ToolNotFound' }
    error_event = ADK::Event.new(role: :tool_result, tool_name: tool_name_for_request_event, content: error_result)
    session_service.append_event(session_id: session_id, event: error_event)
    return error_result
  end

  # Create context for tool and callbacks
  tool_context = ADK::ToolContext.new(
    session_id: session.id, 
    user_id: session.user_id, 
    app_name: session.app_name,
    tool_registry: @tool_registry, 
    session_service: session_service,
    logger: ADK.logger,
    invocation_id: invocation_id
  )
  
  result_hash = nil

  # --- before_tool_callback ---
  if @before_tool_callback.is_a?(Proc)
    ADK.logger.debug { "Agent '#{@name}': Executing before_tool_callback for tool '#{final_tool_name_to_execute}'." }
    begin
      override_result = @before_tool_callback.call(tool_instance, params_for_execution.dup, tool_context)
      if override_result.is_a?(Hash)
        ADK.logger.info { "Agent '#{@name}': before_tool_callback returned override result for '#{final_tool_name_to_execute}'. Skipping tool execution." }
        result_hash = override_result
      end
    rescue StandardError => cb_err
      ADK.logger.error("Error in before_tool_callback for tool '#{final_tool_name_to_execute}': #{cb_err.message}")
      result_hash = { 
        status: :error, 
        error_message: "Error in before_tool_callback: #{cb_err.message}", 
        error_class: cb_err.class.name 
      }
    end
  end

  # Execute tool if not overridden by callback
  unless result_hash
    begin
      result_hash = tool_instance.execute(params_for_execution, tool_context)
    rescue ADK::ToolError => e
      result_hash = { 
        status: :error, 
        error_message: e.message, 
        error_class: e.class.name, 
        result: nil 
      }
    rescue StandardError => e
      result_hash = { 
        status: :error, 
        error_message: "Internal error executing tool '#{final_tool_name_to_execute}': #{e.message}", 
        error_class: e.class.name, 
        result: nil 
      }
    end
  end

  # --- after_tool_callback ---
  # Capture state delta from tool execution or before_tool_callback
  tool_event_state_delta = tool_context.pending_state_delta.dup
  tool_context.clear_pending_state_delta!

  if @after_tool_callback.is_a?(Proc) && result_hash && result_hash[:status] != :error
    ADK.logger.debug { "Agent '#{@name}': Executing after_tool_callback for tool '#{final_tool_name_to_execute}'." }
    begin
      modified_result = @after_tool_callback.call(
        tool_instance, 
        params_for_execution.dup, 
        tool_context, 
        result_hash.dup
      )
      result_hash = modified_result if modified_result.is_a?(Hash)
      # Merge new delta from this callback
      tool_event_state_delta.merge!(tool_context.pending_state_delta)
    rescue StandardError => cb_err
      ADK.logger.error("Error in after_tool_callback for tool '#{final_tool_name_to_execute}': #{cb_err.message}")
      # Use result from before callback if this one errors
    end
  end

  # Log the tool result event with accumulated state delta
  result_event = ADK::Event.new(
    role: :tool_result, 
    tool_name: tool_name_for_request_event, 
    content: result_hash, 
    state_delta: tool_event_state_delta
  )
  session_service.append_event(session_id: session_id, event: result_event)

  # Return the result hash
  result_hash
end
```

## Testing Plan

### 1. Complete `spec/adk/callbacks_spec.rb`

Expand the test file to cover:

1. **Context Objects**
   - Verify `CallbackContext` and `ToolContext` state management
   - Test serialization of values

2. **Agent Definition DSL**
   - Verify all callback registration methods
   - Test validation (must be a Proc)

3. **Agent Callback Execution**
   - Test `before_agent_callback` - both continuing and overriding execution
   - Test `after_agent_callback` - modifying result
   - Test state changes are captured in events

4. **Model Callback Execution**
   - Test `before_model_callback` - both continuing and overriding execution
   - Test `after_model_callback` - modifying plan

5. **Tool Callback Execution**
   - Test `before_tool_callback` - both continuing and overriding execution
   - Test `after_tool_callback` - modifying tool result
   - Test state changes are captured in tool result events

6. **Error Handling**
   - Test error handling for each callback type
   - Verify appropriate logging and continuation behavior

## Documentation

Create comprehensive documentation in `docs/callbacks.md` that explains:

1. Purpose and benefits of callbacks
2. Callback types and when they're executed
3. Context objects and their capabilities
4. State management through callbacks
5. Error handling behavior
6. Best practices and examples

## Implementation Order

1. Update `ADK::Agent#run_task` method with before/after agent callbacks
2. Update `execute_plan` to pass invocation_id
3. Update `execute_step` with before/after tool callbacks
4. Implement before/after model callbacks in `run_task`
5. Complete testing
6. Finalize documentation 