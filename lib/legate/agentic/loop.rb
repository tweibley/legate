# File: lib/legate/agentic/loop.rb
# frozen_string_literal: true

require_relative 'decision'

module Legate
  module Agentic
    # Drives the observe -> think -> act loop: ask the planner for the next
    # single action, run it via the executor, feed the result back as an
    # observation, and repeat until the model gives a final answer or the
    # iteration cap is hit.
    #
    # Returns the same { details:, last_result: } shape as
    # PlanExecutor#execute_plan, so Agent#run_task builds the final event
    # identically for both execution strategies.
    class Loop
      DEFAULT_MAX_ITERATIONS = 8
      # Long string tool results are truncated to this many characters before
      # being fed back, so one big output doesn't dominate the prompt each turn.
      MAX_OBSERVATION_CHARS = 2_000

      # @param planner [#reason_next_action] returns a Decision for the next step
      # @param executor [#execute_step] runs one tool step (e.g. a PlanExecutor)
      # @param logger [Logger, nil]
      # @param max_iterations [Integer]
      def initialize(planner:, executor:, logger: nil, max_iterations: DEFAULT_MAX_ITERATIONS)
        @planner = planner
        @executor = executor
        @logger = logger || Legate.logger
        @max_iterations = max_iterations
      end

      # @return [Hash] { details: <observations>, last_result: <result hash> }
      def run(user_input:, session:, session_service:, invocation_id: nil)
        observations = []

        @max_iterations.times do |i|
          decision = @planner.reason_next_action(user_input, observations, invocation_id)

          return success(decision.answer, observations) if decision.final?

          if decision.invalid?
            @logger.warn("Agentic loop: model returned an unusable decision at step #{i + 1}; stopping.")
            return error('The agent could not decide on a valid next action.', observations)
          end

          result = execute(decision, session, session_service, invocation_id)
          observation = { tool: decision.tool, params: decision.params, result: sanitize(result) }
          spinning = observation == observations.last
          observations << observation

          # Loop-breaker: the model just repeated the exact same action and got
          # the exact same result — re-running won't make progress, so stop and
          # summarize rather than burn the rest of the iteration budget.
          next unless spinning

          @logger.warn("Agentic loop: repeated action '#{decision.tool}' with no change; stopping to avoid spinning.")
          return finish_without_final(user_input, observations, invocation_id,
                                      fallback: "Stopped after repeating the same action ('#{decision.tool}') without progress.")
        end

        @logger.warn("Agentic loop: reached the #{@max_iterations}-iteration cap without a final answer.")
        finish_without_final(user_input, observations, invocation_id,
                             fallback: "Stopped after #{@max_iterations} steps without a final answer.")
      end

      private

      # The loop stopped without the model giving a final answer. Try one
      # best-effort summary of the observations; fall back to an error result if
      # the planner can't summarize (no adapter, failure, or empty answer).
      def finish_without_final(user_input, observations, invocation_id, fallback:)
        summary = summarize(user_input, observations, invocation_id)
        return success(summary, observations) if summary

        error(fallback, observations)
      end

      def summarize(user_input, observations, invocation_id)
        return nil unless @planner.respond_to?(:summarize_final)

        answer = @planner.summarize_final(user_input, observations, invocation_id)
        answer if answer.is_a?(String) && !answer.empty?
      rescue StandardError => e
        @logger.error("Agentic loop: summary failed: #{e.class}: #{e.message}")
        nil
      end

      def execute(decision, session, session_service, invocation_id)
        @executor.execute_step(decision.to_step, session, session_service, invocation_id)
      rescue StandardError => e
        # A hard tool failure becomes an observation the model can react to on
        # the next turn — it does not abort the loop.
        @logger.error("Agentic loop: tool '#{decision.tool}' raised: #{e.class}: #{e.message}")
        { status: :error, error_message: "Tool '#{decision.tool}' raised: #{e.message}" }
      end

      def success(answer, observations)
        { details: observations, last_result: { status: :success, result: answer } }
      end

      def error(message, observations)
        { details: observations, last_result: { status: :error, error_message: message } }
      end

      # Keep large tool outputs from blowing the context fed back to the model
      # (mirrors PlanExecutor#execute_plan's per-step sanitization).
      def sanitize(result)
        return result unless result.is_a?(Hash)

        out = { status: result[:status] }
        out[:error_message] = result[:error_message] if result.key?(:error_message)
        out[:job_id] = result[:job_id] if result.key?(:job_id)
        out[:message] = result[:message] if result.key?(:message)

        val = result[:result]
        if val.is_a?(String)
          out[:result] = truncate(val)
        elsif val.is_a?(Numeric) || [true, false, nil].include?(val)
          out[:result] = val
        elsif result.key?(:result)
          out[:result] = '[Complex Result Structure]'
        end
        out
      end

      def truncate(str)
        return str if str.length <= MAX_OBSERVATION_CHARS

        "#{str[0, MAX_OBSERVATION_CHARS]}… [truncated #{str.length - MAX_OBSERVATION_CHARS} chars]"
      end
    end
  end
end
