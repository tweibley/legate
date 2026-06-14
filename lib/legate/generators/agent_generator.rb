# frozen_string_literal: true

require_relative 'code_validator'
require_relative '../llm'

module Legate
  module Generators
    # AI-powered agent code generator. Uses the configured LLM adapter (Gemini by
    # default) via Legate::LLM.
    class AgentGenerator
      class GenerationError < StandardError; end
      class ApiKeyMissingError < GenerationError; end
      class ApiError < GenerationError; end

      # Model used for code generation; passed to Legate::LLM.build_adapter.
      GENERATION_MODEL = 'gemini-2.5-pro'

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
        adapter = Legate::LLM.build_adapter(model: GENERATION_MODEL)
        raise ApiKeyMissingError, 'GOOGLE_API_KEY not configured. AI generation requires a Gemini API key.' unless adapter.available?

        available_tools = format_available_tools
        system_prompt = build_prompt(available_tools)
        user_prompt = build_user_prompt(description)

        generated_code = call_llm(adapter, system_prompt, user_prompt)
        clean_code = clean_generated_code(generated_code)
        CodeValidator.validate!(clean_code)
        suggested_name = extract_agent_name(clean_code)

        { code: clean_code, suggested_name: suggested_name }
      rescue CodeValidator::UnsafeCodeError => e
        raise GenerationError, e.message
      end

      # Generate a STRUCTURED agent definition (the same fields the "Create Agent"
      # form accepts) from a description. No Ruby is generated or executed — the
      # result is plain data that can be registered live via POST /agents. Tools
      # are filtered to those actually installed (hallucinated ones are dropped).
      # @return [Hash] { name:, description:, instruction:, model:, agent_type:,
      #                  tools: [String], output_key:, dropped_tools: [String] }
      def self.generate_definition(description:)
        new.generate_definition(description: description)
      end

      def generate_definition(description:)
        validate_description!(description)
        adapter = Legate::LLM.build_adapter(model: GENERATION_MODEL)
        raise ApiKeyMissingError, 'GOOGLE_API_KEY not configured. AI generation requires a Gemini API key.' unless adapter.available?

        system_prompt = build_definition_prompt(format_available_tools)
        user_prompt = build_definition_user_prompt(description)
        raw = call_llm(adapter, system_prompt, user_prompt)
        normalize_definition_fields(parse_definition_json(raw), fallback_description: description)
      end

      private

      def parse_definition_json(raw)
        cleaned = raw.strip
                     .gsub(/\A```json\n?/, '').gsub(/\A```\n?/, '').gsub(/\n?```\z/, '').strip
        # Be forgiving if the model wraps the object in stray prose.
        cleaned = Regexp.last_match(0) if cleaned !~ /\A\{/ && cleaned.match(/\{.*\}/m)
        JSON.parse(cleaned)
      rescue JSON::ParserError => e
        raise GenerationError, "The AI response wasn't valid JSON. Please try regenerating. (#{e.message})"
      end

      def normalize_definition_fields(fields, fallback_description:)
        raise GenerationError, 'The AI response was not a JSON object. Please try regenerating.' unless fields.is_a?(Hash)

        valid_tool_names = Legate::GlobalToolManager.list_all_tools.map { |t| t[:name].to_s }

        name = sanitize_agent_name(fields['name'])
        raise GenerationError, 'The AI did not produce a valid agent name. Please try regenerating.' if name.empty?

        agent_type = fields['agent_type'].to_s.strip.downcase
        agent_type = 'llm' unless %w[llm sequential parallel loop].include?(agent_type)

        requested = Array(fields['tools']).map { |t| t.to_s.sub(/\A:/, '').strip }.reject(&:empty?).uniq
        tools = requested & valid_tool_names
        dropped = requested - valid_tool_names

        description = fields['description'].to_s.strip
        description = fallback_description.to_s.strip if description.empty?

        model = fields['model'].to_s.strip
        model = Legate::Agent::DEFAULT_MODEL if model.empty?

        {
          name: name,
          description: description,
          instruction: fields['instruction'].to_s.strip,
          model: model,
          agent_type: agent_type,
          tools: tools,
          output_key: fields['output_key'].to_s.strip,
          dropped_tools: dropped,
          suggested_tools: build_suggested_tools(fields['suggested_tools'], dropped, valid_tool_names)
        }
      end

      # Tools the agent wants that aren't installed — the model's explicit
      # `suggested_tools` proposals plus any names it wrongly put in `tools`.
      # Filtered to genuinely-missing tools and de-duped by sanitized name.
      # @return [Array<Hash>] [{ name: String, description: String }]
      def build_suggested_tools(explicit, dropped_from_tools, valid_tool_names)
        candidates = Array(explicit).map do |st|
          st.is_a?(Hash) ? { name: st['name'].to_s, description: st['description'].to_s } : { name: st.to_s, description: '' }
        end
        candidates += dropped_from_tools.map { |n| { name: n.to_s, description: '' } }

        seen = {}
        candidates.each do |st|
          nm = sanitize_agent_name(st[:name])
          next if nm.empty? || valid_tool_names.include?(nm)

          seen[nm] ||= { name: nm, description: '' }
          desc = st[:description].to_s.strip
          seen[nm][:description] = desc if seen[nm][:description].empty? && !desc.empty?
        end
        seen.values
      end

      def sanitize_agent_name(raw)
        raw.to_s.strip.sub(/\A:/, '').downcase.gsub(/[^a-z0-9_]+/, '_').gsub(/\A_+|_+\z/, '')
      end

      def build_definition_user_prompt(description)
        <<~PROMPT
          Create a Legate agent configuration (JSON only) for this description:

          #{description}
        PROMPT
      end

      def build_definition_prompt(available_tools)
        <<~PROMPT
          You configure agents for Legate — an AI Agent Framework for Ruby. Given a
          description, output a single JSON object describing the agent. Output ONLY
          the JSON — no markdown fences, no prose.

          ## JSON schema (all keys required)
          {
            "name": "snake_case_unique_name",
            "description": "one-line summary of what the agent does",
            "instruction": "the system prompt guiding the agent's behavior (may be multi-line)",
            "model": "gemini-3.5-flash",
            "agent_type": "llm",
            "tools": ["echo"],
            "output_key": "",
            "suggested_tools": [
              { "name": "snake_case_tool_name", "description": "what this missing tool would do" }
            ]
          }

          ## Rules
          - "name": lowercase letters, digits and underscores only; descriptive.
          - "agent_type": one of llm, sequential, parallel, loop. Prefer "llm" unless the description clearly describes a multi-agent workflow.
          - "tools": ONLY names from the Available Tools list below. Never invent tools. Use [] if none fit.
          - "suggested_tools": if the agent would clearly benefit from a capability that NONE of the available tools provide, propose it here with a snake_case name and a one-line description of what it should do. Do NOT put these in "tools". Use [] if every needed capability is already covered.
          - "instruction": clear and detailed; explain when to use each chosen tool.
          - "output_key": optional; use "" when not needed.

          ## Available Tools
          #{available_tools}
        PROMPT
      end

      def validate_description!(description)
        raise GenerationError, 'Description is required' if description.nil? || description.strip.empty?
        raise GenerationError, 'Description too long. Maximum 5000 characters.' if description.length > 5000
      end

      def call_llm(adapter, system_prompt, user_prompt)
        text = begin
          adapter.generate("#{system_prompt}\n\n#{user_prompt}")
        rescue StandardError => e
          raise ApiError, "AI service communication error: #{e.message}"
        end
        raise GenerationError, 'AI service returned empty response. Please try again.' unless text && !text.strip.empty?

        text
      end

      def format_available_tools
        Legate::GlobalToolManager.list_all_tools.map do |tool|
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
          You are an expert Ruby developer specializing in Legate — AI Agent Framework for Ruby.
          Your task is to generate complete, production-ready Ruby agent definition code based on user descriptions.

          ## Legate AgentDefinition DSL Reference

          An agent is defined using the AgentDefinition DSL:

          ```ruby
          require 'legate'

          definition = Legate::AgentDefinition.new.define do |a|
            # Required fields
            a.name :agent_name                    # Symbol, unique identifier
            a.description 'What this agent does' # String, brief description
            a.instruction 'System prompt...'     # String, guides agent behavior

            # Tools - add each tool the agent should use
            a.use_tool :tool_name

            # Optional: Model configuration
            a.model_name '#{Legate.config.default_model_name}'      # LLM model to use
            a.temperature 0.7                     # Creativity (0.0-1.0)
            a.fallback_mode :error                # :error or :echo

            # Optional: Output storage
            a.output_key :result_key              # Store final result in session state
          end

          # Register the agent globally
          Legate::GlobalDefinitionRegistry.register(definition)
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

          The following tools are available in this Legate installation:

          #{available_tools}

          ## Output Requirements

          1. Output ONLY valid Ruby code - no markdown fences, no explanations
          2. Always start with `require 'legate'`
          3. Include helpful comments explaining each section
          4. Use ENV variables for any secrets (never hardcode)
          5. End with `Legate::GlobalDefinitionRegistry.register(definition)`
          6. **CRITICAL: Only use tools from the "Available Tools" section above - never invent or assume tools exist**
          7. If no existing tool matches a requirement, either omit that capability or suggest in a comment that a custom tool would need to be created
          8. Write clear, detailed instructions that guide the agent's behavior
          9. In the agent instruction, explain what tools are available and when to use each one

          ## Example Output

          ```ruby
          # frozen_string_literal: true

          require 'legate'

          # Agent: Customer Support Assistant
          # Handles customer inquiries and provides helpful responses
          definition = Legate::AgentDefinition.new.define do |a|
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
            a.model_name '#{Legate.config.default_model_name}'
            a.temperature 0.7
          end

          Legate::GlobalDefinitionRegistry.register(definition)
          ```
        PROMPT
      end
    end
  end
end
