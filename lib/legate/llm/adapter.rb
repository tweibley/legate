# File: lib/legate/llm/adapter.rb
# frozen_string_literal: true

module Legate
  # LLM provider abstraction. The planner (and code generators) talk to an
  # Adapter rather than a specific provider client, so Legate is not hardwired to
  # one model vendor. Gemini is the first adapter; others (OpenAI, Anthropic,
  # Ollama, ...) implement the same interface.
  module LLM
    # Abstract base for LLM provider adapters.
    class Adapter
      # @return [Boolean] whether the adapter can make calls (e.g. an API key is
      #   present and the client constructed successfully).
      def available?
        false
      end

      # The resolved model identifier, or nil if the adapter is unavailable.
      # @return [String, nil]
      def model_name
        nil
      end

      # Generates a text completion for a single user prompt.
      # @param prompt [String] the user prompt
      # @param json [Boolean] request raw-JSON output where the provider supports it
      # @param schema [Hash, nil] an optional response schema (provider-native
      #   structured output) to constrain the JSON shape. Ignored by adapters
      #   that don't support it; see {#supports_structured_output?}.
      # @return [String, nil] the model's text output, or nil if unavailable
      # @raise [StandardError] on a non-retryable provider error
      def generate(prompt, json: false, schema: nil)
        raise NotImplementedError, "#{self.class} must implement #generate"
      end

      # Whether this adapter can constrain output to a schema (structured output)
      # via the `schema:` argument to {#generate}. When true, the planner uses it
      # to guarantee valid plan JSON instead of parsing it out of prose. Default
      # false (the prompt-and-parse path).
      # @return [Boolean]
      def supports_structured_output?
        false
      end

      # Whether this adapter can use the provider's native function/tool-calling
      # API. When true, the agentic loop selects its next action via
      # {#generate_with_tools} (structured, reliable) instead of parsing JSON out
      # of prose; when false it falls back to the JSON-prompt path. Default false.
      # @return [Boolean]
      def supports_function_calling?
        false
      end

      # Chooses the next action with the given tool schemas available to the
      # model, using native function calling. Only meaningful when
      # {#supports_function_calling?} is true.
      #
      # @param prompt [String] instructions + context + observation transcript
      # @param tools [Array<Hash>] each { name:, description:, parameters: <JSON Schema> }
      # @return [Hash] a provider-neutral choice, one of:
      #   * `{ kind: :tool,  name: String, arguments: Hash, thought: String }`
      #   * `{ kind: :final, text: String, thought: String }`
      # @raise [StandardError] on a non-retryable provider error
      def generate_with_tools(prompt, tools:)
        raise NotImplementedError, "#{self.class} must implement #generate_with_tools"
      end
    end
  end
end
