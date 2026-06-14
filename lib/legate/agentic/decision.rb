# File: lib/legate/agentic/decision.rb
# frozen_string_literal: true

module Legate
  # The agentic (observe -> think -> act) execution strategy.
  module Agentic
    # One step of an agentic loop: the model either calls a tool or gives a
    # final answer. Immutable.
    #
    # @!attribute action [Symbol] :tool or :final
    # @!attribute thought [String, nil] the model's reasoning
    # @!attribute tool [Symbol, nil] the tool to call (when action == :tool)
    # @!attribute params [Hash] tool arguments (when action == :tool)
    # @!attribute answer [String, nil] the final answer (when action == :final)
    Decision = Data.define(:action, :thought, :tool, :params, :answer) do
      def self.tool(tool:, params:, thought: nil)
        new(action: :tool, thought: thought, tool: tool.to_sym, params: params || {}, answer: nil)
      end

      def self.final(answer:, thought: nil)
        new(action: :final, thought: thought, tool: nil, params: {}, answer: answer)
      end

      # An unusable decision (the model returned neither a valid tool call nor a
      # final answer).
      def self.invalid(thought: nil)
        new(action: :invalid, thought: thought, tool: nil, params: {}, answer: nil)
      end

      def final?
        action == :final
      end

      def tool?
        action == :tool && !tool.nil? && !tool.to_s.empty?
      end

      def invalid?
        !final? && !tool?
      end

      # The plan step hash that PlanExecutor#execute_step expects.
      # @return [Hash]
      def to_step
        { tool: tool, params: params }
      end
    end
  end
end
