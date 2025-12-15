# frozen_string_literal: true

require 'gemini-ai'

module ADK
  module Generators
    # AI-powered agent code generator using Gemini LLM
    class AgentGenerator
      class GenerationError < StandardError; end
      class ApiKeyMissingError < GenerationError; end
      class ApiError < GenerationError; end

      # Generate agent definition code from a natural language description
      # @param description [String] Natural language description of the agent to generate
      # @return [Hash] { code: String, suggested_name: String }
      # @raise [ApiKeyMissingError] if GOOGLE_API_KEY is not set
      # @raise [ApiError] if Gemini API fails
      # @raise [GenerationError] for other generation failures
      def self.generate(description:)
        new.generate(description: description)
      end

      def generate(description:)
        validate_description!(description)
        validate_api_key!

        available_tools = format_available_tools
        system_prompt = build_prompt(available_tools)
        user_prompt = build_user_prompt(description)

        generated_code = call_gemini(system_prompt, user_prompt)
        clean_code = clean_generated_code(generated_code)
        suggested_name = extract_agent_name(clean_code)

        { code: clean_code, suggested_name: suggested_name }
      end

      private

      def validate_description!(description)
        raise GenerationError, 'Description is required' if description.nil? || description.strip.empty?
        raise GenerationError, 'Description too long. Maximum 5000 characters.' if description.length > 5000
      end

      def validate_api_key!
        api_key = ENV['GOOGLE_API_KEY']
        raise ApiKeyMissingError, 'GOOGLE_API_KEY not configured. AI generation requires a Gemini API key.' unless api_key && !api_key.empty?
      end

      def format_available_tools
        ADK::GlobalToolManager.list_all_tools.map do |tool|
          tool_info = "### :#{tool[:name]}\n"
          tool_info += "**Description:** #{tool[:description]}\n"

          params = tool[:parameters] || {}
          if params.empty?
            tool_info += "**Parameters:** None\n"
          else
            tool_info += "**Parameters:**\n"
            params.each do |param_name, param_options|
              required_str = param_options[:required] ? '(required)' : '(optional)'
              tool_info += "  - `#{param_name}` (#{param_options[:type]}) #{required_str}: #{param_options[:description]}\n"
            end
          end

          tool_info
        end.join("\n")
      end

      def build_user_prompt(description)
        <<~PROMPT
          Generate a Ruby agent definition based on this description:

          #{description}

          Remember to output ONLY the Ruby code, no explanations or markdown formatting.
        PROMPT
      end

      def call_gemini(system_prompt, user_prompt)
        gemini_client = Gemini.new(
          credentials: { service: 'generative-language-api', api_key: ENV['GOOGLE_API_KEY'] },
          options: { model: 'gemini-2.5-pro', server_sent_events: false }
        )

        response = gemini_client.generate_content({
                                                    contents: [
                                                      { role: 'user', parts: { text: "#{system_prompt}\n\n#{user_prompt}" } }
                                                    ]
                                                  })

        generated_code = response.dig('candidates', 0, 'content', 'parts', 0, 'text')

        raise GenerationError, 'AI service returned empty response. Please try again.' unless generated_code && !generated_code.strip.empty?

        generated_code
      rescue Faraday::Error, Gemini::Errors::RequestError => e
        raise ApiError, "AI service communication error: #{e.message}"
      end

      def clean_generated_code(code)
        clean = code.strip
        clean = clean.gsub(/\A```ruby\n?/, '').gsub(/\A```\n?/, '')
        clean = clean.gsub(/\n?```\z/, '')
        clean.strip
      end

      def extract_agent_name(code)
        # Try to find a.name :something pattern
        return Regexp.last_match(1) if code =~ /a\.name[(\s]+:(\w+)/

        'generated_agent'
      end

      def build_prompt(available_tools)
        <<~PROMPT
          You are an expert Ruby developer specializing in the ADK (Agent Development Kit) framework.
          Your task is to generate complete, production-ready Ruby agent definition code based on user descriptions.

          ## ADK AgentDefinition DSL Reference

          An agent is defined using the AgentDefinition DSL:

          ```ruby
          require 'adk'

          definition = ADK::AgentDefinition.new.define do |a|
            # Required fields
            a.name :agent_name                    # Symbol, unique identifier
            a.description 'What this agent does' # String, brief description
            a.instruction 'System prompt...'     # String, guides agent behavior

            # Tools - add each tool the agent should use
            a.use_tool :tool_name

            # Optional: Model configuration
            a.model_name 'gemini-2.0-flash'      # LLM model to use
            a.temperature 0.7                     # Creativity (0.0-1.0)
            a.fallback_mode :error                # :error or :echo

            # Optional: Output storage
            a.output_key :result_key              # Store final result in session state
          end

          # Register the agent globally
          ADK::GlobalDefinitionRegistry.register(definition)
          ```

          ## Agent Types

          ### LLM Agent (default)
          Uses an LLM for planning and tool selection:
          ```ruby
          a.agent_type :llm  # This is the default, can be omitted
          a.delegation_targets [:other_agent]  # Optional: agents this one can delegate to
          ```

          ### Sequential Workflow Agent
          Runs sub-agents in order:
          ```ruby
          a.agent_type :sequential
          a.sequential_sub_agent_names [:first_agent, :second_agent, :third_agent]
          ```

          ### Parallel Workflow Agent
          Runs sub-agents concurrently:
          ```ruby
          a.agent_type :parallel
          a.parallel_sub_agent_names [:agent_a, :agent_b, :agent_c]
          ```

          ### Loop Workflow Agent
          Runs sub-agents repeatedly until condition is met:
          ```ruby
          a.agent_type :loop
          a.loop_sub_agent_names [:process_agent, :check_agent]
          a.loop_max_iterations 10
          a.loop_condition_state_key :is_complete
          a.loop_condition_expected_value 'true'
          ```

          ## Webhook Configuration

          For agents triggered by external HTTP webhooks:
          ```ruby
          a.webhook_enabled true
          a.webhook_validator :hmac_sha256                    # Or custom Proc
          a.webhook_secret ENV['WEBHOOK_SECRET']              # Always use ENV vars!

          # Transform incoming payload to agent input
          a.webhook_transformer ->(payload) do
            data = payload['data'] || payload
            "Process this: \#{data.to_json}"
          end

          # Extract session ID from payload
          a.webhook_session_extractor ->(payload) do
            id = payload['id'] || payload.dig('resource', 'id') || 'default'
            "webhook_session_\#{id}"
          end
          ```

          ## Callbacks

          For custom logic before/after agent and tool execution:
          ```ruby
          a.before_agent_callback do |context|
            context.state_set(:start_time, Time.now.to_f)
            nil  # Return nil to continue, or a value to short-circuit
          end

          a.after_agent_callback do |context, response|
            duration = Time.now.to_f - context.state_get(:start_time)
            puts "Agent completed in \#{duration}s"
            nil  # Return nil to use response as-is, or modified response
          end

          a.before_tool_callback do |tool, args, context|
            puts "Calling \#{tool.name} with \#{args}"
            nil
          end

          a.after_tool_callback do |tool, args, context, result|
            puts "Tool \#{tool.name} returned: \#{result}"
            nil
          end
          ```

          ## Available Tools

          **IMPORTANT: You may ONLY use tools from the list below. Do NOT hallucinate or invent tools that are not listed here.**

          The following tools are available in this ADK installation:

          #{available_tools}

          ## Output Requirements

          1. Output ONLY valid Ruby code - no markdown fences, no explanations
          2. Always start with `require 'adk'`
          3. Include helpful comments explaining each section
          4. Use ENV variables for any secrets (never hardcode)
          5. End with `ADK::GlobalDefinitionRegistry.register(definition)`
          6. **CRITICAL: Only use tools from the "Available Tools" section above - never invent or assume tools exist**
          7. If no existing tool matches a requirement, either omit that capability or suggest in a comment that a custom tool would need to be created
          8. Write clear, detailed instructions that guide the agent's behavior
          9. In the agent instruction, explain what tools are available and when to use each one

          ## Example Output

          ```ruby
          # frozen_string_literal: true

          require 'adk'

          # Agent: Customer Support Assistant
          # Handles customer inquiries and provides helpful responses
          definition = ADK::AgentDefinition.new.define do |a|
            a.name :customer_support
            a.description 'Assists customers with questions and issues'

            a.instruction <<~INSTRUCTION
              You are a friendly and helpful customer support assistant.
          #{'    '}
              Guidelines:
              - Be polite and professional at all times
              - Ask clarifying questions when needed
              - Provide accurate information based on available tools
              - Escalate complex issues appropriately
            INSTRUCTION

            # Tools for customer support
            a.use_tool :echo

            # Model configuration
            a.model_name 'gemini-2.0-flash'
            a.temperature 0.7
          end

          ADK::GlobalDefinitionRegistry.register(definition)
          ```
        PROMPT
      end
    end
  end
end
