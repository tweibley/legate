# File: lib/legate/llm/gemini.rb
# frozen_string_literal: true

require 'gemini-ai'
require_relative '../gemini_ai_beta_patch' # Apply monkey patch for v1beta API
require_relative '../redaction'
require_relative 'adapter'

module Legate
  module LLM
    # LLM adapter backed by the gemini-ai gem (Google Gemini, v1beta endpoint).
    class Gemini < Adapter
      MAX_RETRIES = 2
      RETRY_BASE_DELAY = 1 # seconds, exponential: 1s, 2s

      # @param model [String] the Gemini model id
      # @param api_key [String, nil] defaults to ENV['GOOGLE_API_KEY'], then
      #   ENV['GEMINI_API_KEY'] — so either env var works directly (no need to go
      #   through Legate.load_environment for the alias).
      # @param logger [Logger, nil] defaults to Legate.logger
      def initialize(model:, api_key: nil, logger: nil)
        super()
        @model = model
        @api_key = api_key || ENV['GOOGLE_API_KEY'] || ENV['GEMINI_API_KEY']
        @logger = logger || Legate.logger
        @client = build_client
      end

      def available?
        !@client.nil?
      end

      def model_name
        available? ? @model : nil
      end

      # @see Legate::LLM::Adapter#generate
      def generate(prompt, json: false, schema: nil)
        return nil unless @client

        response = request_with_retry(build_text_payload(prompt, json: json, schema: schema))
        response.dig('candidates', 0, 'content', 'parts', 0, 'text')
      end

      # Gemini supports structured output via responseSchema on the v1beta endpoint.
      def supports_structured_output?
        true
      end

      # Gemini supports native function calling on the v1beta endpoint.
      def supports_function_calling?
        true
      end

      # @see Legate::LLM::Adapter#generate_with_tools
      def generate_with_tools(prompt, tools:)
        return { kind: :final, text: nil, thought: nil } unless @client

        response = request_with_retry(build_tools_payload(prompt, tools))
        parse_tool_response(response)
      end

      private

      def build_text_payload(prompt, json:, schema: nil)
        payload = { contents: [{ role: 'user', parts: { text: prompt } }] }
        # Ask Gemini to return raw JSON (v1beta field names; the gem sends the
        # payload through verbatim). A responseSchema additionally constrains the
        # output to that shape (structured output) — guaranteed-valid JSON.
        if json || schema
          config = { responseMimeType: 'application/json' }
          config[:responseSchema] = schema if schema
          payload[:generationConfig] = config
        end
        payload
      end

      def build_tools_payload(prompt, tools)
        {
          contents: [{ role: 'user', parts: { text: prompt } }],
          tools: [{ functionDeclarations: Array(tools).map { |t| function_declaration(t) } }]
        }
      end

      # Convert a neutral tool schema { name:, description:, parameters: <JSON Schema> }
      # into a Gemini functionDeclaration (OpenAPI subset, uppercase type names).
      def function_declaration(tool)
        {
          name: tool[:name].to_s,
          description: tool[:description].to_s,
          parameters: to_openapi_schema(tool[:parameters])
        }
      end

      def to_openapi_schema(schema)
        return { type: 'OBJECT', properties: {} } unless schema.is_a?(Hash)

        props = (schema[:properties] || {}).transform_values do |prop|
          out = { type: (prop[:type] || 'string').to_s.upcase }
          out[:description] = prop[:description].to_s if prop[:description]
          out[:items] = { type: (prop.dig(:items, :type) || 'string').to_s.upcase } if out[:type] == 'ARRAY'
          out
        end
        result = { type: 'OBJECT', properties: props }
        required = Array(schema[:required]).map(&:to_s)
        result[:required] = required unless required.empty?
        result
      end

      # A functionCall part -> tool choice; otherwise the text parts -> final.
      def parse_tool_response(response)
        parts = response.dig('candidates', 0, 'content', 'parts') || []
        text = parts.filter_map { |p| p['text'] }.join.strip
        text = nil if text.empty?

        call = parts.find { |p| p['functionCall'] }
        if call
          fc = call['functionCall']
          return { kind: :tool, name: fc['name'].to_s, arguments: fc['args'] || {}, thought: text }
        end

        { kind: :final, text: text, thought: nil }
      end

      def build_client
        if @api_key.nil? || @api_key.empty?
          @logger.error('GOOGLE_API_KEY not found. The Gemini LLM adapter requires an API key.')
          return nil
        end

        client = ::Gemini.new(
          credentials: { service: 'generative-language-api', api_key: @api_key },
          options: { model: @model, server_sent_events: false }
        )
        @logger.info("Gemini LLM adapter initialized with model: #{@model}")
        client
      rescue StandardError => e
        @logger.error("Failed to initialize Gemini client (model '#{@model}'): #{e.class}: #{Legate::Redaction.redact(e.message)}")
        @logger.error(Legate::Redaction.redact(e.backtrace.join("\n"))) if e.backtrace
        nil
      end

      def request_with_retry(payload)
        attempt = 0
        begin
          attempt += 1
          @client.generate_content(payload)
        rescue StandardError => e
          if attempt <= MAX_RETRIES && retryable_error?(e)
            delay = RETRY_BASE_DELAY * (2**(attempt - 1))
            @logger.warn("Gemini API attempt #{attempt}/#{MAX_RETRIES + 1} failed (#{e.class}), retrying in #{delay}s...")
            sleep(delay)
            retry
          end
          # Re-raise with the API key scrubbed from the message (the gemini-ai gem
          # embeds the full request URL, including ?key=..., in its errors).
          raise e.class, Legate::Redaction.redact(e.message), e.backtrace
        end
      end

      def retryable_error?(error)
        msg = error.message.to_s
        return true if error.is_a?(Errno::ECONNRESET) || error.is_a?(Errno::ECONNREFUSED) || error.is_a?(Errno::ETIMEDOUT)
        return true if error.is_a?(Net::OpenTimeout) || error.is_a?(Net::ReadTimeout)
        return true if msg.match?(/429|rate.limit/i)
        return true if msg.match?(/^5\d{2}\b|server.error|service.unavailable|internal.server/i)

        false
      end
    end
  end
end
