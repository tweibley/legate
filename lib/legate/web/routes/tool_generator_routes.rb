# File: lib/legate/web/routes/tool_generator_routes.rb
# frozen_string_literal: true

require_relative '../../generators/tool_generator'
require_relative '../../generators/runtime_tool_loader'

module Legate
  module Web
    # Routes for AI-powered tool code generation. Delegates to
    # Legate::Generators::ToolGenerator so the web path shares the exact
    # generation logic AND the CodeValidator safety check used by the CLI
    # (the route must not reimplement either).
    module ToolGeneratorRoutes
      def self.registered(app)
        # POST /tools/generate - Generate tool class code from natural language
        app.post '/tools/generate' do
          content_type :json

          begin
            request.body.rewind
            body = JSON.parse(request.body.read)
          rescue JSON::ParserError => e
            halt 400, json(error: "Invalid JSON: #{e.message}")
          end

          begin
            result = Legate::Generators::ToolGenerator.generate(description: body['description'].to_s.strip)
            logger.info("Successfully generated tool code (name: #{result[:suggested_name]}, type: #{result[:tool_type]})")
            json(result)
          rescue Legate::Generators::ToolGenerator::ApiKeyMissingError => e
            halt 503, json(error: e.message)
          rescue Legate::Generators::ToolGenerator::ApiError => e
            logger.error("Gemini API error during tool generation: #{e.message}")
            halt 503, json(error: 'AI service communication error. Please try again.')
          rescue Legate::Generators::ToolGenerator::GenerationError => e
            # Covers validation failures, empty responses, and unsafe generated
            # code rejected by CodeValidator.
            halt 400, json(error: e.message)
          rescue StandardError => e
            logger.error("Unexpected error during tool generation: #{e.class} - #{e.message}")
            halt 500, json(error: 'Generation failed. Please try again.')
          end
        end

        # POST /tools/install - Load a generated custom tool into the RUNNING process.
        # SECURITY: executes LLM-generated Ruby. Gated by config + explicit confirm +
        # server-side re-validation (see RuntimeToolLoader). Writes tools/<name>.rb.
        app.post '/tools/install' do
          content_type :json

          halt 403, json(error: 'Runtime tool loading is disabled in this environment. Use Download instead, place the file in tools/, and restart.') unless Legate::Generators::RuntimeToolLoader.enabled?

          begin
            request.body.rewind
            body = JSON.parse(request.body.read)
          rescue JSON::ParserError => e
            halt 400, json(error: "Invalid JSON: #{e.message}")
          end

          # Require an explicit confirmation that the user accepts running this code.
          halt 400, json(error: 'Confirmation required to install a tool.') unless body['confirm'] == true

          source = body['code'].to_s
          halt 400, json(error: 'No tool code provided.') if source.strip.empty?

          result = Legate::Generators::RuntimeToolLoader.load_source!(
            source, suggested_name: body['suggested_name'].to_s
          )

          if result[:ok]
            logger.info("Runtime-loaded custom tool '#{result[:tool_name]}' -> #{result[:path]}")
            json(ok: true, tool_name: result[:tool_name])
          else
            logger.warn("Runtime tool install rejected: #{result[:error]}")
            halt 422, json(error: result[:error])
          end
        end
      end
    end
  end
end
