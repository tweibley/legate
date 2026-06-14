# File: lib/legate/llm/ollama.rb
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require_relative 'adapter'

module Legate
  module LLM
    # LLM adapter backed by a local Ollama server (https://ollama.com).
    #
    # Talks to Ollama's /api/generate HTTP endpoint — no API key, no cost, fully
    # local. Configure the host via the :host option or the OLLAMA_HOST env var
    # (default http://localhost:11434). Wire it up globally with:
    #
    #   Legate::LLM.default_adapter_factory = lambda do |model:, **|
    #     Legate::LLM::Ollama.new(model: model)
    #   end
    class Ollama < Adapter
      DEFAULT_HOST = 'http://localhost:11434'

      # @param model [String] the Ollama model tag, e.g. 'llama3' or 'qwen2.5'
      # @param host [String, nil] base URL of the Ollama server
      # @param logger [Logger, nil]
      # @param read_timeout [Integer] seconds to wait for a completion (default 120)
      def initialize(model:, host: nil, logger: nil, read_timeout: 120, **_ignored)
        super()
        @model = model
        @host = (host || ENV['OLLAMA_HOST'] || DEFAULT_HOST).to_s.chomp('/')
        @logger = logger || Legate.logger
        @read_timeout = read_timeout
      end

      # Ollama is a local server; assume it's reachable rather than pinging it on
      # every planner init. A real failure surfaces from #generate with a clear
      # message.
      def available?
        true
      end

      def model_name
        @model
      end

      # @see Legate::LLM::Adapter#generate
      # `schema:` is accepted for interface parity but ignored (Ollama's
      # `format: json` is the only structured constraint used here).
      def generate(prompt, json: false, schema: nil) # rubocop:disable Lint/UnusedMethodArgument
        body = { model: @model, prompt: prompt, stream: false }
        # Ollama supports constrained JSON output via the "format" field.
        body[:format] = 'json' if json

        post_json('/api/generate', body)['response']
      rescue StandardError => e
        @logger.error("Ollama generate failed (#{@host}, model '#{@model}'): #{e.class}: #{e.message}")
        raise
      end

      private

      def post_json(path, body)
        uri = URI.join("#{@host}/", path.sub(%r{\A/}, ''))
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 5
        http.read_timeout = @read_timeout

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate(body)

        response = http.request(request)
        raise "Ollama HTTP #{response.code}: #{response.body.to_s[0, 300]}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end
    end
  end
end
