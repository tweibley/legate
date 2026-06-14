# File: lib/legate/plan_executor.rb
# frozen_string_literal: true

require 'json'
require_relative 'event'
require_relative 'tool_context'

module Legate
  # Executes a planner-produced plan for an Agent: iterates the steps, injects
  # prior-step results into parameters, runs each tool (with before/after-tool
  # callbacks and delegation interception), and logs the tool_request/tool_result
  # events. Extracted from Legate::Agent, which keeps thin execute_plan/execute_step
  # delegators (the lifecycle entry points exercised directly by specs).
  class PlanExecutor
    # @param agent [Legate::Agent] the owning agent; the executor reads its
    #   tool registry, fallback mode, tool callbacks, and auth config.
    def initialize(agent)
      @agent = agent
    end

    # Executes a plan and returns { details: [...], last_result: <hash> }.
    def execute_plan(plan, session, session_service, invocation_id)
      session_id = session.id

      # A planning failure returns a direct_result (a terminal result, no steps);
      # surface it as-is so run_task builds a clean error Event.
      return { details: [], last_result: plan[:direct_result] } if plan.is_a?(Hash) && plan[:direct_result]

      # Extract steps based on the plan format
      steps = nil
      thought_process = nil

      # Handle new plan structure with thought_process and steps
      if plan.is_a?(Hash) && plan[:steps].is_a?(Array)
        steps = plan[:steps]
        thought_process = plan[:thought_process]
        Legate.logger.info("Plan thought process: #{thought_process}") if thought_process
      elsif plan.is_a?(Array)
        # For backward compatibility with old format
        steps = plan
      else
        msg = 'Invalid plan received from planner (not an Array or properly structured Hash).'
        Legate.logger.error("#{msg} Plan: #{plan.inspect}")
        return { details: [], last_result: { status: :error, error_message: msg } }
      end

      # --- Continue with original logic, using 'steps' variable ---
      unless steps.is_a?(Array)
        msg = 'Invalid steps structure in plan (not an Array).'
        Legate.logger.error("#{msg} Steps: #{steps.inspect}")
        return { details: [], last_result: { status: :error, error_message: msg } }
      end

      # --- Handle Empty Plan based on Fallback Mode ---
      if steps.empty?
        if @agent.fallback_mode == :echo
          if @agent.tool_registry.find_class(:echo)
            Legate.logger.warn("Plan is empty. Falling back to echo mode for session '#{session_id}'.")
            # Reconstruct the plan to be a single echo step
            # We need the original user input for this - fetch it from the session
            # Find the *last* user event in case of corrections/multiple turns
            original_user_input = session.events.reverse.find { |e|
              e.role == :user
            }&.content || '[Original input not found]'
            steps = [{ tool: :echo, params: { message: original_user_input } }]
            Legate.logger.debug("Reconstructed plan for echo fallback: #{steps.inspect}")
            # Now continue execution with the modified plan
          else
            # Echo tool not available, default to error mode
            msg = 'Planning failed and Echo fallback tool is not available to this agent.'
            Legate.logger.warn(msg)
            return { details: [], last_result: { status: :error, error_message: msg } }
          end
        else # Default or :error mode
          msg = 'I cannot fulfill this request with the available tools (empty plan).'
          Legate.logger.warn(msg)
          return { details: [], last_result: { status: :error, error_message: msg } }
        end
      end
      # --- End Handle Empty Plan ---

      Legate.logger.debug("Executing plan with #{steps.length} step(s) for session '#{session_id}': #{steps.inspect}")
      previous_step_result_hash = nil
      plan_execution_details = []
      last_successful_or_pending_result = nil # <-- Store the original last hash

      steps.each_with_index do |step, index|
        # Log the step type for clarity
        step_type_desc = if step[:step_type] == :sequential_sub_agent
                           "sequential sub-agent '#{step[:sub_agent_name]}'"
                         else
                           "tool '#{step[:tool]}'"
                         end
        Legate.logger.debug("Executing step #{index + 1}/#{steps.length}: #{step_type_desc}")
        Legate.logger.debug("  Step details: #{step.inspect}")
        Legate.logger.debug("  Input (result hash from previous step): #{previous_step_result_hash.inspect}")

        # --- Input Injection Logic (Updated for job_id) ---
        current_params = JSON.parse(JSON.generate(step[:params]), symbolize_names: true)
        current_params.transform_values! do |value|
          injection_value = nil
          if value.is_a?(String) && value.match?(/\[Result from step \d+\]|\[Result from previous step\]/i)
            if previous_step_result_hash.is_a?(Hash) && %i[success pending].include?(previous_step_result_hash[:status])
              # Prioritize :result, then :job_id (was workflow_id), then :message
              if previous_step_result_hash.key?(:result)
                prev_result = previous_step_result_hash[:result]
                if prev_result.is_a?(Hash) && prev_result.key?(:status) && prev_result.key?(:result) # AgentTool nested result
                  injection_value = prev_result[:result]
                  Legate.logger.debug('Injecting nested result...')
                else
                  injection_value = prev_result
                  Legate.logger.debug('Injecting direct result...')
                end
              elsif previous_step_result_hash.key?(:job_id) # <-- CHANGED from workflow_id
                injection_value = previous_step_result_hash[:job_id]
                Legate.logger.debug('Injecting job_id from previous step...')
              elsif previous_step_result_hash.key?(:message)
                injection_value = previous_step_result_hash[:message]
                Legate.logger.debug('Injecting message from previous step...')
              else
                Legate.logger.warn("Cannot inject: Previous successful/pending step missing usable key (:result, :job_id, :message). Prev Hash: #{previous_step_result_hash.inspect}")
                value
              end
            else
              Legate.logger.warn("Cannot inject: Previous step failed or absent. Prev Hash: #{previous_step_result_hash.inspect}")
              value
            end
            injection_value || value # Use injection if found, otherwise keep original
          else
            value # Not a placeholder string, keep original value
          end
        end
        step_with_injected_params = step.merge(params: current_params)
        Legate.logger.debug("  Params after potential injection: #{current_params.inspect}")
        # --- End Input Injection Logic ---

        # --- Execute Step --- #
        current_result_hash = execute_step(step_with_injected_params, session, session_service, invocation_id)

        # --- Sanitize for plan_details --- #
        sanitized_result_for_plan = {}
        if current_result_hash.is_a?(Hash)
          sanitized_result_for_plan[:status] = current_result_hash[:status]
          # Always include error keys, defaulting to nil if not present
          sanitized_result_for_plan[:error_message] = current_result_hash[:error_message] # Defaults to nil if key missing
          sanitized_result_for_plan[:error_class] = current_result_hash[:error_class] # Defaults to nil if key missing
          # Include other relevant keys if present
          sanitized_result_for_plan[:job_id] = current_result_hash[:job_id] if current_result_hash.key?(:job_id)
          sanitized_result_for_plan[:message] = current_result_hash[:message] if current_result_hash.key?(:message)
          # Only include :result value if it's simple
          result_val = current_result_hash[:result]
          if result_val.is_a?(String) || result_val.is_a?(Numeric) || [true, false, nil].include?(result_val)
            sanitized_result_for_plan[:result] = result_val
          elsif current_result_hash.key?(:result) # It exists but is complex
            sanitized_result_for_plan[:result] = '[Complex Result Structure]'
          end
        else # Should not happen based on execute_step validation, but handle defensively
          sanitized_result_for_plan[:status] = :error
          sanitized_result_for_plan[:error_message] = "Invalid format from execute_step: #{current_result_hash.inspect}"
        end
        # --- END Sanitization ---

        # --- Store SANITIZED step detail --- #
        plan_execution_details << {
          tool_name: step[:tool],
          params: current_params,
          result: sanitized_result_for_plan
        }

        # --- Store ORIGINAL result and check for errors --- #
        if current_result_hash[:status] == :error
          Legate.logger.warn("Step #{index + 1} failed, stopping plan execution: #{current_result_hash[:error_message]}")
          last_successful_or_pending_result = current_result_hash # Store the error hash as last result
          break # Exit the loop
        else
          # Store successful or pending hash for potential injection AND final result
          previous_step_result_hash = current_result_hash
          last_successful_or_pending_result = current_result_hash
        end
        # --- End Stop on first error / Store last result --- #
      end

      Legate.logger.debug("Plan execution finished. Structured details collected: #{plan_execution_details.inspect}")
      Legate.logger.debug("Plan execution finished. Original last result: #{last_successful_or_pending_result.inspect}")

      # --- Return BOTH sanitized details AND original last result --- #
      { details: plan_execution_details, last_result: last_successful_or_pending_result }
    end

    # Executes a single step, logging :tool_request and :tool_result events via
    # the session service.
    # @return [Hash] A standard result hash { status:, result/error_message/job_id: }.
    def execute_step(step, session, session_service, invocation_id = nil)
      session_id = session.id

      # --- Basic validation ---
      unless step.is_a?(Hash) && step[:tool] && step[:params].is_a?(Hash)
        error_msg = 'Invalid step format. Expected { tool: :symbol, params: {...} }'
        Legate.logger.error(error_msg)
        return { status: :error, error_message: error_msg }
      end

      raw_tool_name = step[:tool].to_s

      # Validate tool name against known tools before converting to Symbol
      # to prevent Symbol table exhaustion from untrusted input
      known_names = @agent.tool_registry.available_tool_names.map(&:to_s)
      is_delegation = raw_tool_name.start_with?('agent_transfer_to_')
      unless known_names.include?(raw_tool_name) || is_delegation
        error_msg = "Unknown tool '#{raw_tool_name}' — not in agent's tool registry"
        Legate.logger.error(error_msg)
        return { status: :error, error_message: error_msg }
      end

      tool_name = raw_tool_name.to_sym
      params = step[:params].to_h

      # --- Intercept Delegation Tools (MAS) ---
      # If the model outputs "agent_transfer_to_xyz", map it to "delegate_task"
      if tool_name.to_s.start_with?('agent_transfer_to_')
        target_agent_name = tool_name.to_s.sub('agent_transfer_to_', '')
        Legate.logger.info("Intercepted delegation tool '#{tool_name}'. Mapping to 'delegate_task' for target '#{target_agent_name}'.")

        # Remap tool name
        tool_name = :delegate_task

        # Remap params: ensure target_agent_name is set
        params[:target_agent_name] = target_agent_name

        # Ensure 'task' param exists (model should provide it, but handle aliasing/defaults if needed)
        # The prompt says: - task (string, required)
        unless params.key?(:task)
          # Fallback: if model used a different key like 'message' or 'input', map it to 'task'
          if params.key?(:message)
            params[:task] = params.delete(:message)
          elsif params.key?(:input)
            params[:task] = params.delete(:input)
          end
        end
      end
      # --- End Delegation Interception ---

      # --- Get the tool from our registry ---
      tool = @agent.tool_registry.create_instance(tool_name)
      unless tool
        error_msg = "Tool '#{tool_name}' not found in available tools."
        Legate.logger.error(error_msg)
        return { status: :error, error_message: error_msg }
      end

      # --- Prepare tool context with invocation_id and auth config ---
      tool_context = Legate::ToolContext.new(
        session_id: session.id,
        user_id: session.user_id,
        app_name: session.app_name,
        session_service: session_service,
        tool_registry: @agent.tool_registry,
        invocation_id: invocation_id,
        agent_auth_config: @agent.send(:build_agent_auth_config)
      )

      # --- Log the tool request event ---
      tool_request_event = Legate::Event.new(
        role: :tool_request,
        tool_name: tool_name,
        content: params
      )
      session_service.append_event(session_id: session_id, event: tool_request_event)

      # --- Execute before_tool_callback if defined ---
      if @agent.before_tool_callback.is_a?(Proc)
        Legate.logger.debug { "Agent '#{@agent.name}': Executing before_tool_callback for tool '#{tool_name}'." }

        begin
          # Execute the callback and check if it returns a result
          override_result = @agent.before_tool_callback.call(tool, params.dup, tool_context)

          # If the callback returns a result (not nil), use it instead of normal tool execution
          if override_result
            Legate.logger.info { "Agent '#{@agent.name}': before_tool_callback provided an override result for tool '#{tool_name}'." }

            # Create a tool result event with the override result and any state changes
            tool_result_event = Legate::Event.new(
              role: :tool_result,
              tool_name: tool_name,
              content: override_result,
              state_delta: tool_context.pending_state_delta
            )
            session_service.append_event(session_id: session_id, event: tool_result_event)

            return override_result
          end
        rescue StandardError => e
          Legate.logger.error { "Agent '#{@agent.name}': Error in before_tool_callback for tool '#{tool_name}': #{e.message}\n#{e.backtrace.join("\n")}" }

          error_result = {
            status: :error,
            error_message: "Error in before_tool_callback: #{e.message}",
            error_class: e.class.name
          }

          # Create a tool result event with the error
          tool_result_event = Legate::Event.new(
            role: :tool_result,
            tool_name: tool_name,
            content: error_result,
            state_delta: tool_context.pending_state_delta
          )
          session_service.append_event(session_id: session_id, event: tool_result_event)

          return error_result
        end
      end

      # --- Execute the tool ---
      begin
        Legate.logger.debug { "Executing tool '#{tool_name}' with params #{params.inspect}" }
        final_tool_name_to_execute = tool_name

        # For delegate_task tool, capture the delegate to show in logs
        final_tool_name_to_execute = "#{tool_name} -> #{params[:target_agent_name]}" if tool_name == :delegate_task && params[:target_agent_name]

        result = tool.execute(params, tool_context)

        # --- Execute after_tool_callback if defined ---
        if @agent.after_tool_callback.is_a?(Proc)
          Legate.logger.debug { "Agent '#{@agent.name}': Executing after_tool_callback for tool '#{final_tool_name_to_execute}'." }

          begin
            # Execute the callback and let it modify the result if needed
            modified_result = @agent.after_tool_callback.call(tool, params.dup, tool_context, result.dup)

            # If the callback returned a modified result, use it
            if modified_result && modified_result != result
              Legate.logger.info { "Agent '#{@agent.name}': after_tool_callback modified the result for tool '#{final_tool_name_to_execute}'." }
              result = modified_result
            end
          rescue StandardError => e
            Legate.logger.error { "Agent '#{@agent.name}': Error in after_tool_callback for tool '#{final_tool_name_to_execute}': #{e.message}\n#{e.backtrace.join("\n")}" }
            # Don't override the result completely on error, just log it
          end
        end

        # --- Log the tool result event ---
        tool_result_event = Legate::Event.new(
          role: :tool_result,
          tool_name: tool_name,
          content: result,
          state_delta: tool_context.pending_state_delta
        )
        session_service.append_event(session_id: session_id, event: tool_result_event)

        result
      rescue StandardError => e
        Legate.logger.error { "Error executing tool '#{tool_name}': #{e.message}\n#{e.backtrace.join("\n")}" }

        error_result = {
          status: :error,
          error_message: "Tool '#{tool_name}' execution error: #{e.message}",
          error_class: e.class.name # consistent with every other error hash + the plan-detail sanitizer
        }

        # Create a tool result event with the error
        tool_result_event = Legate::Event.new(
          role: :tool_result,
          tool_name: tool_name,
          content: error_result
        )
        session_service.append_event(session_id: session_id, event: tool_result_event)

        error_result
      end
    end
  end
end
