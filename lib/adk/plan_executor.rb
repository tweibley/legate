# frozen_string_literal: true

require 'logger'
require_relative 'event'
require_relative 'tool_context'

module ADK
  # Responsible for executing a plan (sequence of steps) on behalf of an Agent.
  class PlanExecutor
    def initialize(agent)
      @agent = agent
    end

    # Executes a plan, logging tool request/result events via the session service.
    # @param plan [Hash, Array] The plan from the planner.
    # @param session [ADK::Session] The current session object.
    # @param session_service [Object] The session service instance.
    # @param invocation_id [String] The ID of the current agent invocation.
    # @return [Hash] { details: Array<Hash>, last_result: Hash }
    def execute_plan(plan, session, session_service, invocation_id)
      session_id = session.id

      # Extract steps based on the plan format
      steps = nil
      thought_process = nil

      if plan.is_a?(Hash) && plan[:steps].is_a?(Array)
        steps = plan[:steps]
        thought_process = plan[:thought_process]
        ADK.logger.info("Plan thought process: #{thought_process}") if thought_process
      elsif plan.is_a?(Array)
        steps = plan
      else
        msg = 'Invalid plan received from planner (not an Array or properly structured Hash).'
        ADK.logger.error("#{msg} Plan: #{plan.inspect}")
        return { details: { status: :error, error_message: msg }, last_result: nil }
      end

      unless steps.is_a?(Array)
        msg = 'Invalid steps structure in plan (not an Array).'
        ADK.logger.error("#{msg} Steps: #{steps.inspect}")
        return { details: { status: :error, error_message: msg }, last_result: nil }
      end

      # Handle Empty Plan based on Fallback Mode
      if steps.empty?
        if @agent.fallback_mode == :echo
          if @agent.tool_registry.find_class(:echo)
            ADK.logger.warn("Plan is empty. Falling back to echo mode for session '#{session_id}'.")
            original_user_input = session.events.reverse.find { |e| e.role == :user }&.content || '[Original input not found]'
            steps = [{ tool: :echo, params: { message: original_user_input } }]
            ADK.logger.debug("Reconstructed plan for echo fallback: #{steps.inspect}")
          else
            msg = 'Planning failed and Echo fallback tool is not available to this agent.'
            ADK.logger.warn(msg)
            return { details: { status: :error, error_message: msg }, last_result: nil }
          end
        else # Default or :error mode
          msg = 'I cannot fulfill this request with the available tools (empty plan).'
          ADK.logger.warn(msg)
          return { details: { status: :error, error_message: msg }, last_result: nil }
        end
      end

      ADK.logger.debug("Executing plan with #{steps.length} step(s) for session '#{session_id}': #{steps.inspect}")
      previous_step_result_hash = nil
      plan_execution_details = []
      last_successful_or_pending_result = nil

      steps.each_with_index do |step, index|
        step_type_desc = if step[:step_type] == :sequential_sub_agent
                           "sequential sub-agent '#{step[:sub_agent_name]}'"
                         else
                           "tool '#{step[:tool]}'"
                         end
        ADK.logger.debug("Executing step #{index + 1}/#{steps.length}: #{step_type_desc}")
        ADK.logger.debug("  Step details: #{step.inspect}")
        ADK.logger.debug("  Input (result hash from previous step): #{previous_step_result_hash.inspect}")

        # Input Injection Logic
        current_params = step[:params].dup
        current_params.transform_values! do |value|
          injection_value = nil
          if value.is_a?(String) && value.match?(/\[Result from step \d+\]|\[Result from previous step\]/i)
            if previous_step_result_hash && %i[success pending].include?(previous_step_result_hash[:status])
              if previous_step_result_hash.key?(:result)
                prev_result = previous_step_result_hash[:result]
                if prev_result.is_a?(Hash) && prev_result.key?(:status) && prev_result.key?(:result)
                  injection_value = prev_result[:result]
                  ADK.logger.debug('Injecting nested result...')
                else
                  injection_value = prev_result
                  ADK.logger.debug('Injecting direct result...')
                end
              elsif previous_step_result_hash.key?(:job_id)
                injection_value = previous_step_result_hash[:job_id]
                ADK.logger.debug('Injecting job_id from previous step...')
              elsif previous_step_result_hash.key?(:message)
                injection_value = previous_step_result_hash[:message]
                ADK.logger.debug('Injecting message from previous step...')
              else
                ADK.logger.warn("Cannot inject: Previous successful/pending step missing usable key. Prev Hash: #{previous_step_result_hash.inspect}")
                value
              end
            else
              ADK.logger.warn("Cannot inject: Previous step failed or absent. Prev Hash: #{previous_step_result_hash.inspect}")
              value
            end
            injection_value || value
          else
            value
          end
        end
        step_with_injected_params = step.merge(params: current_params)
        ADK.logger.debug("  Params after potential injection: #{current_params.inspect}")

        # Execute Step
        current_result_hash = execute_step(step_with_injected_params, session, session_service, invocation_id)

        # Sanitize for plan_details
        sanitized_result_for_plan = {}
        if current_result_hash.is_a?(Hash)
          sanitized_result_for_plan[:status] = current_result_hash[:status]
          sanitized_result_for_plan[:error_message] = current_result_hash[:error_message]
          sanitized_result_for_plan[:error_class] = current_result_hash[:error_class]
          sanitized_result_for_plan[:job_id] = current_result_hash[:job_id] if current_result_hash.key?(:job_id)
          sanitized_result_for_plan[:message] = current_result_hash[:message] if current_result_hash.key?(:message)
          result_val = current_result_hash[:result]
          if result_val.is_a?(String) || result_val.is_a?(Numeric) || [true, false, nil].include?(result_val)
            sanitized_result_for_plan[:result] = result_val
          elsif current_result_hash.key?(:result)
            sanitized_result_for_plan[:result] = '[Complex Result Structure]'
          end
        else
          sanitized_result_for_plan[:status] = :error
          sanitized_result_for_plan[:error_message] = "Invalid format from execute_step: #{current_result_hash.inspect}"
        end

        plan_execution_details << {
          tool_name: step[:tool],
          params: current_params,
          result: sanitized_result_for_plan
        }

        if current_result_hash[:status] == :error
          ADK.logger.warn("Step #{index + 1} failed, stopping plan execution: #{current_result_hash[:error_message]}")
          last_successful_or_pending_result = current_result_hash
          break
        else
          previous_step_result_hash = current_result_hash
          last_successful_or_pending_result = current_result_hash
        end
      end

      ADK.logger.debug("Plan execution finished. Original last result: #{last_successful_or_pending_result.inspect}")

      { details: plan_execution_details, last_result: last_successful_or_pending_result }
    end

    private

    def execute_step(step, session, session_service, invocation_id = nil)
      session_id = session.id

      unless step.is_a?(Hash) && step[:tool] && step[:params].is_a?(Hash)
        error_msg = 'Invalid step format. Expected { tool: :symbol, params: {...} }'
        ADK.logger.error(error_msg)
        return { status: :error, error_message: error_msg }
      end

      tool_name = step[:tool].to_sym
      params = step[:params].to_h

      # Intercept Delegation Tools (MAS)
      if tool_name.to_s.start_with?('agent_transfer_to_')
        target_agent_name = tool_name.to_s.sub('agent_transfer_to_', '')
        ADK.logger.info("Intercepted delegation tool '#{tool_name}'. Mapping to 'delegate_task' for target '#{target_agent_name}'.")
        tool_name = :delegate_task
        params[:target_agent_name] = target_agent_name
        unless params.key?(:task)
          if params.key?(:message)
            params[:task] = params.delete(:message)
          elsif params.key?(:input)
            params[:task] = params.delete(:input)
          end
        end
      end

      tool = @agent.tool_registry.create_instance(tool_name)
      unless tool
        error_msg = "Tool '#{tool_name}' not found in available tools."
        ADK.logger.error(error_msg)
        return { status: :error, error_message: error_msg }
      end

      tool_context = ADK::ToolContext.new(
        session_id: session.id,
        user_id: session.user_id,
        app_name: session.app_name,
        session_service: session_service,
        tool_registry: @agent.tool_registry,
        invocation_id: invocation_id,
        agent_auth_config: build_agent_auth_config
      )

      tool_request_event = ADK::Event.new(
        role: :tool_request,
        tool_name: tool_name,
        content: params
      )
      session_service.append_event(session_id: session_id, event: tool_request_event)

      # execute before_tool_callback if defined
      if @agent.before_tool_callback.is_a?(Proc)
        ADK.logger.debug { "Agent '#{@agent.name}': Executing before_tool_callback for tool '#{tool_name}'." }
        begin
          override_result = @agent.before_tool_callback.call(tool, params.dup, tool_context)
          if override_result
            ADK.logger.info { "Agent '#{@agent.name}': before_tool_callback provided an override result for tool '#{tool_name}'." }
            tool_result_event = ADK::Event.new(
              role: :tool_result,
              tool_name: tool_name,
              content: override_result,
              state_delta: tool_context.pending_state_delta
            )
            session_service.append_event(session_id: session_id, event: tool_result_event)
            return override_result
          end
        rescue StandardError => e
          ADK.logger.error { "Agent '#{@agent.name}': Error in before_tool_callback for tool '#{tool_name}': #{e.message}\n#{e.backtrace.join("\n")}" }
          error_result = { status: :error, error_message: "Error in before_tool_callback: #{e.message}", error_class: e.class.name }
          tool_result_event = ADK::Event.new(role: :tool_result, tool_name: tool_name, content: error_result, state_delta: tool_context.pending_state_delta)
          session_service.append_event(session_id: session_id, event: tool_result_event)
          return error_result
        end
      end

      begin
        ADK.logger.debug { "Executing tool '#{tool_name}' with params #{params.inspect}" }
        final_tool_name_to_execute = tool_name
        final_tool_name_to_execute = "#{tool_name} -> #{params[:agent_name]}" if tool_name == :delegate_task && params[:agent_name]

        result = tool.execute(params, tool_context)

        # execute after_tool_callback if defined
        if @agent.after_tool_callback.is_a?(Proc)
          ADK.logger.debug { "Agent '#{@agent.name}': Executing after_tool_callback for tool '#{final_tool_name_to_execute}'." }
          begin
            modified_result = @agent.after_tool_callback.call(tool, params.dup, tool_context, result.dup)
            if modified_result && modified_result != result
              ADK.logger.info { "Agent '#{@agent.name}': after_tool_callback modified the result for tool '#{final_tool_name_to_execute}'." }
              result = modified_result
            end
          rescue StandardError => e
            ADK.logger.error { "Agent '#{@agent.name}': Error in after_tool_callback for tool '#{final_tool_name_to_execute}': #{e.message}\n#{e.backtrace.join("\n")}" }
          end
        end

        tool_result_event = ADK::Event.new(
          role: :tool_result,
          tool_name: tool_name,
          content: result,
          state_delta: tool_context.pending_state_delta
        )
        session_service.append_event(session_id: session_id, event: tool_result_event)

        result
      rescue StandardError => e
        ADK.logger.error { "Error executing tool '#{tool_name}': #{e.message}\n#{e.backtrace.join("\n")}" }
        error_result = {
          status: :error,
          error_message: "Tool '#{tool_name}' execution error: #{e.message}",
          exception: e.class.name
        }
        tool_result_event = ADK::Event.new(
          role: :tool_result,
          tool_name: tool_name,
          content: error_result
        )
        session_service.append_event(session_id: session_id, event: tool_result_event)
        error_result
      end
    end

    def build_agent_auth_config
      return nil if @agent.auth_credential_names.empty? &&
                    @agent.auth_url_mappings.empty? &&
                    @agent.auth_scheme_assignments.empty? &&
                    @agent.auth_credential_assignments.empty?

      {
        credential_names: @agent.auth_credential_names,
        url_mappings: @agent.auth_url_mappings,
        scheme_assignments: @agent.auth_scheme_assignments,
        credential_assignments: @agent.auth_credential_assignments
      }
    end
  end
end
