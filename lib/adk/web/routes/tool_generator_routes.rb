# File: lib/adk/web/routes/tool_generator_routes.rb
# frozen_string_literal: true

require 'gemini-ai'

module ADK
  module Web
    # Routes for AI-powered tool code generation
    module ToolGeneratorRoutes
      def self.registered(app)
        # POST /tools/generate - Generate tool class code from natural language
        app.post '/tools/generate' do
          content_type :json

          # Parse request body
          begin
            request.body.rewind
            body = JSON.parse(request.body.read)
          rescue JSON::ParserError => e
            halt 400, json(error: "Invalid JSON: #{e.message}")
          end

          description = body['description']&.strip
          if description.nil? || description.empty?
            halt 400, json(error: 'Description is required.')
          end

          if description.length > 5000
            halt 400, json(error: 'Description too long. Maximum 5000 characters.')
          end

          # Check for API key
          google_api_key = ENV['GOOGLE_API_KEY']
          unless google_api_key && !google_api_key.empty?
            halt 503, json(error: 'GOOGLE_API_KEY not configured. AI generation requires a Gemini API key.')
          end

          # Build the system prompt
          system_prompt = ToolGeneratorRoutes.build_tool_generator_prompt

          # Build user prompt
          user_prompt = <<~PROMPT
            Generate a Ruby tool class based on this description:

            #{description}

            Remember to output ONLY the Ruby code, no explanations or markdown formatting.
            Determine the appropriate tool type (simple, HTTP API, or async) based on the description.
          PROMPT

          begin
            logger.info('Generating tool code via Gemini AI')
            logger.debug("Tool generation description: #{description[0..100]}...")

            gemini_client = Gemini.new(
              credentials: { service: 'generative-language-api', api_key: google_api_key },
              options: { model: 'gemini-2.5-pro', server_sent_events: false }
            )

            response = gemini_client.generate_content({
              contents: [
                { role: 'user', parts: { text: "#{system_prompt}\n\n#{user_prompt}" } }
              ]
            })

            generated_code = response.dig('candidates', 0, 'content', 'parts', 0, 'text')

            unless generated_code && !generated_code.strip.empty?
              logger.error('Gemini returned empty response for tool generation')
              halt 500, json(error: 'AI service returned empty response. Please try again.')
            end

            # Clean up the generated code (remove markdown fences if present)
            clean_code = generated_code.strip
            clean_code = clean_code.gsub(/\A```ruby\n?/, '').gsub(/\A```\n?/, '')
            clean_code = clean_code.gsub(/\n?```\z/, '')
            clean_code = clean_code.strip

            # Extract tool info from the code
            suggested_name = ToolGeneratorRoutes.extract_tool_name(clean_code)
            tool_type = ToolGeneratorRoutes.detect_tool_type(clean_code)

            logger.info("Successfully generated tool code (name: #{suggested_name}, type: #{tool_type})")

            json({
              code: clean_code,
              suggested_name: suggested_name,
              tool_type: tool_type
            })
          rescue Faraday::Error, Gemini::Errors::RequestError => e
            logger.error("Gemini API error during tool generation: #{e.class} - #{e.message}")
            halt 503, json(error: 'AI service communication error. Please try again.')
          rescue StandardError => e
            logger.error("Unexpected error during tool generation: #{e.class} - #{e.message}")
            logger.error(e.backtrace.first(5).join("\n"))
            halt 500, json(error: "Generation failed: #{e.message}")
          end
        end
      end

      # Build the comprehensive system prompt for tool generation
      def self.build_tool_generator_prompt
        <<~PROMPT
          You are an expert Ruby developer specializing in the ADK (Agent Development Kit) framework.
          Your task is to generate complete, production-ready Ruby tool class code based on user descriptions.

          ## Tool Types

          Based on the user's description, determine which type of tool to generate:

          1. **Simple Tool** - For local computation, data transformation, no external calls
          2. **HTTP API Tool** - For calling external REST APIs, checking URLs/websites, or any HTTP requests
          3. **Async Tool** - For long-running background jobs (using Sidekiq)

          ## Simple Tool Template

          ```ruby
          # frozen_string_literal: true

          require 'adk/tool'

          class MyTool < ADK::Tool
            tool_description 'Brief description of what this tool does'

            parameter :param_name,
              type: :string,        # :string, :integer, :number, :boolean, :array, :object
              description: 'What this parameter is for',
              required: true        # or false for optional

            parameter :optional_param,
              type: :integer,
              description: 'An optional parameter',
              required: false

            private

            def perform_execution(params, context)
              # params is a Hash with symbol keys
              # context is ADK::ToolContext with session access

              input = params[:param_name]

              # Your logic here
              result = process(input)

              # Return success
              { status: :success, result: result }

            rescue StandardError => e
              { status: :error, error_message: e.message }
            end
          end

          # Register the tool so agents can use it
          ADK::GlobalToolManager.register_tool(MyTool)
          ```

          ## HTTP API Tool Template

          For tools that call external APIs, check URLs/websites, or make any HTTP requests.
          ALWAYS use HttpClient for ANY HTTP operations - never use Net::HTTP directly.

          Available HTTP methods:
          - `http_get(path, query: {}, headers: {})` - GET request
          - `http_head(path, query: {}, headers: {})` - HEAD request (headers only, no body - efficient for status checks)
          - `http_post(path, body: {}, query: {}, headers: {})` - POST request
          - `http_put(path, body: {}, query: {}, headers: {})` - PUT request
          - `http_delete(path, query: {}, headers: {})` - DELETE request

          ### Fixed Base URL Pattern (for single API)

          ```ruby
          # frozen_string_literal: true

          require 'adk/tool'
          require 'adk/tools/base/http_client'

          class MyApiTool < ADK::Tool
            include ADK::Tools::Base::HttpClient

            tool_description 'Fetches data from External API'

            parameter :query,
              type: :string,
              description: 'Search query',
              required: true

            def initialize(**options)
              super
              setup_http_client(
                base_url: 'https://api.example.com/v1/',
                headers: {
                  'Accept' => 'application/json',
                  'Authorization' => "Bearer \#{ENV['API_KEY']}"
                }
              )
            end

            private

            def perform_execution(params, context)
              query = params[:query]

              # GET request (path is relative to base_url)
              response = http_get('search', query: { q: query })

              # POST request example:
              # response = http_post('endpoint', body: { data: params[:data] })

              data = JSON.parse(response.body)
              { status: :success, result: data }

            rescue ADK::ToolHttpError => e
              { status: :error, error_message: "API error: \#{e.message}" }
            rescue JSON::ParserError => e
              { status: :error, error_message: "Invalid response: \#{e.message}" }
            end
          end

          ADK::GlobalToolManager.register_tool(MyApiTool)
          ```

          ### Dynamic/Arbitrary URL Pattern (for URL checkers, webhooks, etc.)

          For tools that need to call user-provided URLs (not a fixed API), use a placeholder
          base_url and pass absolute URLs to the http_* methods:

          ```ruby
          # frozen_string_literal: true

          require 'adk/tool'
          require 'adk/tools/base/http_client'
          require 'uri'

          class UrlStatusChecker < ADK::Tool
            include ADK::Tools::Base::HttpClient

            tool_description 'Checks if a URL is reachable and returns its HTTP status code'

            parameter :url,
              type: :string,
              description: 'The full URL to check (e.g., https://example.com)',
              required: true

            parameter :expected_status,
              type: :integer,
              description: 'Optional expected status code to validate against',
              required: false

            def initialize(**options)
              super
              # Use placeholder base_url - actual URLs will be absolute
              setup_http_client(base_url: 'https://placeholder.invalid')
            end

            private

            def perform_execution(params, context)
              url = params[:url]
              expected = params[:expected_status]

              # Validate URL format
              validate_url!(url)

              # HEAD request is efficient - fetches headers only, no body
              response = http_head(url)

              result = {
                url: url,
                status_code: response.status,
                reachable: (200..399).cover?(response.status)
              }

              if expected
                result[:expected_status] = expected
                result[:matches] = (response.status == expected)
              end

              { status: :success, result: result }

            rescue URI::InvalidURIError => e
              { status: :error, error_message: "Invalid URL: \#{e.message}" }
            rescue ADK::ToolHttpError => e
              # Non-2xx responses are caught here
              { status: :error, error_message: "HTTP error: \#{e.message}" }
            rescue ADK::ToolNetworkError => e
              { status: :error, error_message: "Network error: \#{e.message}" }
            rescue ADK::ToolTimeoutError => e
              { status: :error, error_message: "Request timed out: \#{e.message}" }
            end

            def validate_url!(url)
              uri = URI.parse(url)
              unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
                raise URI::InvalidURIError, 'URL must use http:// or https://'
              end
              raise URI::InvalidURIError, 'URL must have a host' if uri.host.nil? || uri.host.empty?
            end
          end

          ADK::GlobalToolManager.register_tool(UrlStatusChecker)
          ```

          ## Async Tool Template

          For long-running operations that should run in background:

          ```ruby
          # frozen_string_literal: true

          require 'adk/tools/base_async_job_tool'
          require 'sidekiq'

          # The Sidekiq worker that does the actual work
          class MyWorker
            include Sidekiq::Worker
            sidekiq_options queue: 'default'

            def perform(session_id, input_data)
              jid = self.jid

              # Mark job as started
              ADK::Tools::BaseAsyncJobTool.store_job_pending(jid)

              # Do the long-running work
              result = process_data(input_data)

              # Store the result
              ADK::Tools::BaseAsyncJobTool.store_job_result(jid, result)

            rescue StandardError => e
              ADK::Tools::BaseAsyncJobTool.store_job_error(jid, e.message, e.class.name)
              raise
            end

            private

            def process_data(data)
              # Your long-running logic here
              sleep(5) # Simulating work
              { processed: true, data: data }
            end
          end

          # The ADK tool that enqueues the job
          class MyAsyncTool < ADK::Tools::BaseAsyncJobTool
            tool_description 'Starts a background job to process data'

            parameter :data,
              type: :string,
              description: 'Data to process',
              required: true

            def sidekiq_worker_class
              MyWorker
            end

            def prepare_job_arguments(params, context)
              [context.session_id, params[:data]]
            end
          end

          ADK::GlobalToolManager.register_tool(MyAsyncTool)
          ```

          ## ToolContext Methods

          The `context` parameter provides access to:
          - `context.state_get(:key)` - Read from session state
          - `context.state_set(:key, value)` - Write to session state (applied after execution)
          - `context.session_id` - Current session ID
          - `context.user_id` - Current user ID
          - `context.app_name` - Agent name
          - `context.invocation_id` - Unique invocation ID

          ## Parameter Types

          - `:string` - Text values
          - `:integer` - Whole numbers
          - `:number` - Decimal numbers (float)
          - `:boolean` - true/false
          - `:array` - List of values
          - `:object` - Nested hash/object

          ## Output Requirements

          1. Output ONLY valid Ruby code - no markdown fences, no explanations
          2. Include appropriate requires at the top
          3. Include helpful comments explaining the code
          4. Use ENV variables for API keys and secrets (never hardcode)
          5. End with `ADK::GlobalToolManager.register_tool(ToolClass)`
          6. Use descriptive class names in PascalCase
          7. Include proper error handling

          ## Determining Tool Type

          - If description mentions: API, HTTP, fetch, external service, REST, URL, website, 
            check site, status code, HEAD request, ping, request, web, endpoint, webhook,
            download, upload, GET, POST, online, reachable → Use HTTP API Tool
          - If description mentions: background, async, queue, long-running, process files → Use Async Tool
          - Otherwise → Use Simple Tool

          IMPORTANT: Any tool that makes network requests to URLs or APIs MUST use the HTTP API Tool pattern.
          Never use Net::HTTP, Faraday, or other HTTP libraries directly - always use HttpClient.
        PROMPT
      end

      # Extract tool class name from generated code
      def self.extract_tool_name(code)
        # Try to find class definition
        if code =~ /class\s+(\w+)\s*<\s*(?:ADK::Tool|ADK::Tools::BaseAsyncJobTool)/
          class_name = Regexp.last_match(1)
          # Convert PascalCase to snake_case for filename
          return class_name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                           .downcase
        end
        'generated_tool'
      end

      # Detect what type of tool was generated
      def self.detect_tool_type(code)
        if code.include?('BaseAsyncJobTool') || code.include?('Sidekiq::Worker')
          'async'
        elsif code.include?('HttpClient') || code.include?('http_get') || code.include?('http_post') ||
              code.include?('http_head') || code.include?('http_put') || code.include?('http_delete')
          'http'
        else
          'simple'
        end
      end
    end
  end
end

