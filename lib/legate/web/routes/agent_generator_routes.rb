# File: lib/legate/web/routes/agent_generator_routes.rb
# frozen_string_literal: true

require_relative '../../generators/agent_generator'
require_relative '../../agent_code_generator'

module Legate
  module Web
    # Routes for AI-powered agent code generation. Delegates to
    # Legate::Generators::AgentGenerator so the web path shares the exact
    # generation logic AND the CodeValidator safety check used by the CLI
    # (the route must not reimplement either).
    module AgentGeneratorRoutes
      def self.registered(app)
        # POST /agents/generate - Generate agent definition code from natural language
        app.post '/agents/generate' do
          content_type :json

          begin
            request.body.rewind
            body = JSON.parse(request.body.read)
          rescue JSON::ParserError => e
            halt 400, json(error: "Invalid JSON: #{e.message}")
          end

          begin
            result = Legate::Generators::AgentGenerator.generate(description: body['description'].to_s.strip)
            logger.info("Successfully generated agent code (suggested name: #{result[:suggested_name]})")
            json(result)
          rescue Legate::Generators::AgentGenerator::ApiKeyMissingError => e
            halt 503, json(error: e.message)
          rescue Legate::Generators::AgentGenerator::ApiError => e
            logger.error("Gemini API error during agent generation: #{e.message}")
            halt 503, json(error: 'AI service communication error. Please try again.')
          rescue Legate::Generators::AgentGenerator::GenerationError => e
            # Validation failures, empty responses, and unsafe generated code
            # rejected by CodeValidator.
            halt 400, json(error: e.message)
          rescue StandardError => e
            logger.error("Unexpected error during agent generation: #{e.class} - #{e.message}")
            halt 500, json(error: 'Generation failed. Please try again.')
          end
        end

        # POST /agents/generate/definition - Generate a STRUCTURED agent definition
        # (the same fields the create form accepts) from natural language. The agent
        # can then be registered live via POST /agents — no file download/restart.
        # Also returns derived .rb (via AgentCodeGenerator, no extra LLM call) so the
        # power-user "Export .rb" still works.
        app.post '/agents/generate/definition' do
          content_type :json

          begin
            request.body.rewind
            body = JSON.parse(request.body.read)
          rescue JSON::ParserError => e
            halt 400, json(error: "Invalid JSON: #{e.message}")
          end

          begin
            result = Legate::Generators::AgentGenerator.generate_definition(description: body['description'].to_s.strip)
            code = Legate::AgentCodeGenerator.generate(result)
            logger.info("Successfully generated agent definition (name: #{result[:name]})")
            json(result.merge(code: code))
          rescue Legate::Generators::AgentGenerator::ApiKeyMissingError => e
            halt 503, json(error: e.message)
          rescue Legate::Generators::AgentGenerator::ApiError => e
            logger.error("Gemini API error during agent definition generation: #{e.message}")
            halt 503, json(error: 'AI service communication error. Please try again.')
          rescue Legate::Generators::AgentGenerator::GenerationError => e
            halt 400, json(error: e.message)
          rescue StandardError => e
            logger.error("Unexpected error during agent definition generation: #{e.class} - #{e.message}")
            halt 500, json(error: 'Generation failed. Please try again.')
          end
        end
      end
    end
  end
end
