# File: lib/adk/planner.rb
# frozen_string_literal: true

require 'gemini-ai'
require_relative 'gemini_ai_beta_patch' # Apply monkey patch for v1beta API
require 'json'
require 'logger'

module ADK
  # Orchestrates the planning process using Gemini LLM.
  #
  # The Planner takes a user request and available tools, constructs a prompt,
  # sends it to the LLM, and parses the response into a structured plan of execution.
  # It handles multi-step planning, tool selection, and fallback strategies.
  class Planner
    # @return [ADK::Agent] The agent instance this planner belongs to.
    attr_reader :agent
    # @return [Logger] The logger instance.
    attr_reader :logger
    # @return [String, nil] The model name being used.
    attr_reader :model_name

    # Initializes a new Planner instance.
    #
    # @param agent [ADK::Agent] The agent that owns this planner.
    # @param model_name [String, nil] The specific Gemini model to use (overrides agent default).
    # @param options [Hash] Additional options.
    # @option options [Logger] :logger Logger instance to use (defaults to ADK.logger).
    # @option options [String] :api_key Google API key (defaults to ENV['GOOGLE_API_KEY']).
    def initialize(agent:, model_name: nil, **options)
      @agent = agent
      @logger = options[:logger] || ADK.logger
      @api_key = options[:api_key] || ENV['GOOGLE_API_KEY']
      @client = nil
      # Determine model to use: passed param > agent default > hardcoded default (fallback)
      @configured_model_name = model_name && !model_name.empty? ? model_name : ADK::Agent::DEFAULT_MODEL

      if @api_key.nil? || @api_key.empty?
        @logger.error('GOOGLE_API_KEY not found. GeminiPlanner requires an API key.')
      else
        begin
          @client = Gemini.new(
            credentials: {
              service: 'generative-language-api',
              api_key: @api_key
            },
            # --- Use the configured model name ---
            options: { model: @configured_model_name, server_sent_events: false }
          )
          # Store the actually used model name
          @model_name = @configured_model_name
          logger.info("Gemini AI client initialized for Planner with model: #{@model_name}")
        rescue StandardError => e
          logger.error("Failed to initialize Gemini AI client with model '#{@configured_model_name}': #{e.class}: #{e.message}")
          logger.error(e.backtrace.join("\n"))
          @client = nil
          @model_name = nil # Ensure model_name is nil if client fails
        end
      end
    end

    # Generates a multi-step execution plan for the given user input.
    #
    # @param user_input [String] The user's request or task description.
    # @param invocation_id [String, nil] The unique ID for this invocation (used for callbacks).
    # @return [Hash] A hash containing the thought process and the list of steps.
    #   * :thought_process [String] The LLM's reasoning.
    #   * :steps [Array<Hash>] The sequence of tool execution steps.
    #     Each step hash contains:
    #     * :tool [Symbol] The name of the tool to execute.
    #     * :params [Hash] The parameters for the tool.
    #     * :reason [String] The reason for this step.
    #   Returns a fallback plan structure on error.
    def plan(user_input, invocation_id = nil)
      # Check if client is available, fallback if not
      unless @client
        logger.error('Gemini client not initialized. Falling back to default plan.')
        return fallback_plan(user_input, 'No LLM client available')
      end

      # Format tools for the prompt
      tools_description = format_tools_for_prompt

      # Build and send the planning prompt to the LLM
      prompt = build_multi_step_gemini_prompt(user_input, tools_description)

      # Execute before_model_callback if defined
      modified_prompt = prompt
      if @agent.before_model_callback && invocation_id
        # Create callback context
        callback_context = ADK::Callbacks::CallbackContext.new(
          agent_name: @agent.name,
          invocation_id: invocation_id,
          session_id: nil, # Will be set by the agent in run_task
          user_id: nil,
          app_name: nil,
          session_service: nil
        )

        # Call the callback and get modified prompt if returned
        logger.debug { "Agent '#{@agent.name}': Executing before_model_callback for model input." }
        callback_result = begin
          @agent.before_model_callback.call(modified_prompt, callback_context)
        rescue StandardError => e
          logger.error("Error in before_model_callback: #{e.class}: #{e.message}")
          logger.debug(e.backtrace.join("\n"))
          nil # Continue execution on error
        end

        # If the callback returned a string, use it as the modified prompt
        if callback_result.is_a?(String)
          modified_prompt = callback_result
          logger.debug { "Agent '#{@agent.name}': Prompt modified by before_model_callback." }
        end
      end

      # Use the LLM client from the Gemini wrapper
      begin
        # NOTE: Structured output (responseSchema) would be ideal here but requires
        # investigation into gemini-ai gem support. For now, rely on prompt engineering
        # and robust JSON extraction with fallback to echo tool.
        # See: https://ai.google.dev/gemini-api/docs/structured-output
        response = @client.generate_content(
          {
            contents: [{ role: 'user', parts: { text: modified_prompt } }]
          }
        )

        raw_response_text = response.dig('candidates', 0, 'content', 'parts', 0, 'text')

        unless raw_response_text
          logger.warn("Gemini response was empty or couldn't find text.")
          logger.debug("Raw Gemini Response Object: #{response.inspect}")
          return { error: 'Gemini response was empty or unparseable.' }
        end

        # Execute after_model_callback if defined
        modified_response = raw_response_text
        if @agent.after_model_callback && invocation_id
          # Create callback context if not already created
          callback_context ||= ADK::Callbacks::CallbackContext.new(
            agent_name: @agent.name,
            invocation_id: invocation_id,
            session_id: nil,
            user_id: nil,
            app_name: nil,
            session_service: nil
          )

          # Call the callback and get modified response if returned
          logger.debug { "Agent '#{@agent.name}': Executing after_model_callback for model output." }
          callback_result = begin
            @agent.after_model_callback.call(modified_response, callback_context)
          rescue StandardError => e
            logger.error("Error in after_model_callback: #{e.class}: #{e.message}")
            logger.debug(e.backtrace.join("\n"))
            nil # Continue execution on error
          end

          # If the callback returned a string, use it as the modified response
          if callback_result.is_a?(String)
            modified_response = callback_result
            logger.debug { "Agent '#{@agent.name}': Response modified by after_model_callback." }
          end
        end

        # Extract and validate the plan
        validated_result = validate_and_format_multi_step_plan(modified_response)

        # Check for errors in validation - use fallback plan instead of returning error
        if validated_result[:error]
          logger.warn("Plan validation failed: #{validated_result[:error]}. Using fallback plan.")
          # Try to extract any useful text from the LLM response for the fallback message
          fallback_message = extract_fallback_message(modified_response, user_input)
          return {
            thought_process: 'Fallback: Could not parse structured plan from model response',
            steps: fallback_plan_steps(fallback_message)
          }
        end

        # Return the formatted plan steps
        {
          thought_process: validated_result[:thought_process],
          steps: validated_result[:formatted_steps]
        }
      rescue StandardError => e
        logger.error("Error during planning with Gemini: #{e.class}: #{e.message}")
        {
          thought_process: 'Error occurred during planning',
          steps: fallback_plan_steps("I encountered an error while processing your request: #{e.message}")
        }
      end
    end

    private

    # JSON Schema for structured plan output
    # This schema ensures Gemini returns properly formatted JSON plans
    # See: https://ai.google.dev/gemini-api/docs/structured-output
    def plan_json_schema
      {
        type: 'object',
        properties: {
          thought_process: {
            type: 'string',
            description: 'Your reasoning about how to approach the user request'
          },
          plan: {
            type: 'array',
            description: 'Array of steps to execute',
            items: {
              type: 'object',
              properties: {
                step: {
                  type: 'integer',
                  description: 'Sequential step number starting from 1'
                },
                type: {
                  type: 'string',
                  enum: ['tool_use'],
                  description: 'Type of action - must be tool_use'
                },
                tool_name: {
                  type: 'string',
                  description: 'Name of the tool to use from the available tools list'
                },
                tool_input: {
                  type: 'object',
                  description: 'Parameters to pass to the tool'
                },
                reason: {
                  type: 'string',
                  description: 'Brief explanation of why this step is needed'
                }
              },
              required: %w[step type tool_name tool_input reason]
            }
          }
        },
        required: %w[thought_process plan]
      }
    end

    # Format tools metadata for the prompt
    # Fetches metadata from the agent instance directly.
    def format_tools_for_prompt
      tools_metadata = agent.available_tools_metadata # Fetch metadata here
      delegation_targets_description = format_delegation_targets
      sequential_sub_agents_description = format_sequential_sub_agents

      return 'No tools or delegable agents available.' if tools_metadata.empty? && delegation_targets_description.empty? && sequential_sub_agents_description.empty?

      tools_description = tools_metadata.map do |metadata|
        # Use metadata hash directly
        tool_name = metadata[:name]
        tool_description = metadata[:description]
        parameters = metadata[:parameters] || {}

        params_desc = parameters.map do |name, info|
          req = info[:required] ? 'required' : 'optional'
          # Ensure type is displayed, default to 'any' if missing
          type = info[:type] || 'any'
          "- #{name} (#{type}, #{req}): #{info[:description]}"
        end.join("\n    ")
        <<~TOOL_DESC
          Tool Name: #{tool_name}
          Description: #{tool_description}
          Parameters:
            #{params_desc.empty? ? 'None' : params_desc}
        TOOL_DESC
      end.join("\n\n")

      # Combine tools, delegation targets, and sequential sub-agents
      combined_description = tools_description
      combined_description += "\n\n" + delegation_targets_description unless delegation_targets_description.empty?
      combined_description += "\n\n" + sequential_sub_agents_description unless sequential_sub_agents_description.empty?
      combined_description
    end

    # Format delegation targets for the prompt
    # Each delegable agent is presented as a "tool" with a target_agent parameter
    def format_delegation_targets
      return '' unless @agent.definition.respond_to?(:delegation_targets) && @agent.definition.delegation_targets&.any?

      delegation_targets = @agent.definition.delegation_targets
      logger.info("Planner including #{delegation_targets.size} delegation targets: #{delegation_targets.to_a.join(', ')}")

      delegation_targets.map do |target_name|
        # Try to find the target agent definition for its description
        target_def = nil
        begin
          target_def = ADK::GlobalDefinitionRegistry.find(target_name)
        rescue StandardError => e
          logger.warn("Error getting definition for delegation target '#{target_name}': #{e.message}")
        end

        description = target_def&.description || "Delegate tasks to the #{target_name} agent"

        # Format as a special tool with agent_transfer type
        <<~DELEGATE_DESC
          Tool Name: agent_transfer_to_#{target_name}
          Description: #{description}
          Parameters:
            - task (string, required): The task to delegate to the #{target_name} agent
        DELEGATE_DESC
      end.join("\n\n")
    end

    # Format sequential sub-agents for the prompt
    # Each sequential sub-agent is presented as a "tool" with a task parameter
    def format_sequential_sub_agents
      return '' unless @agent.definition.respond_to?(:sequential_sub_agent_names) && @agent.definition.sequential_sub_agent_names&.any?

      sub_agent_names = @agent.definition.sequential_sub_agent_names
      logger.info("Planner including #{sub_agent_names.size} sequential sub-agents: #{sub_agent_names.to_a.join(', ')}")

      sub_agent_names.map do |agent_name|
        # Try to find the sub-agent definition for its description
        agent_def = nil
        begin
          agent_def = ADK::GlobalDefinitionRegistry.find(agent_name)
        rescue StandardError => e
          logger.warn("Error getting definition for sequential sub-agent '#{agent_name}': #{e.message}")
        end

        description = agent_def&.description || "Execute the #{agent_name} agent"

        # Format as a special tool for sequential execution
        <<~SEQ_AGENT_DESC
          Tool Name: execute_sub_agent_#{agent_name}
          Description: #{description}
          Parameters:
            - task (string, required): The task to execute using the #{agent_name} agent
        SEQ_AGENT_DESC
      end.join("\n\n")
    end

    # Builds the prompt string to send to Gemini.
    #
    # @param user_input [String] The user's original request.
    # @param tools_description [String] Formatted description of available tools.
    # @return [String] The complete prompt including instructions, tool info, and user input.
    def build_multi_step_gemini_prompt(user_input, tools_description)
      # Check if agent has delegation targets
      has_delegation_targets = @agent.definition.respond_to?(:delegation_targets) &&
                               @agent.definition.delegation_targets&.any?

      # Get agent instruction if available
      agent_instruction = @agent.respond_to?(:instruction) ? @agent.instruction : nil
      instruction_text = agent_instruction&.strip.to_s

      # Build the prompt with clear JSON format requirements
      prompt = <<~PROMPT
        # Instructions

        You are an AI assistant that helps people by breaking down tasks into actionable steps using available tools.
        #{!instruction_text.empty? ? "\n" + instruction_text + "\n" : ''}

        ## Response Format - CRITICAL

        You MUST respond with ONLY a valid JSON object (no markdown, no explanation outside JSON):

        ```json
        {
          "thought_process": "Your reasoning about how to approach the request",
          "plan": [
            {
              "step": 1,
              "type": "tool_use",
              "tool_name": "exact_tool_name_from_list",
              "tool_input": {"param1": "value1"},
              "reason": "Why this step is needed"
            }
          ]
        }
        ```

        ## Planning Guidelines

        1. Analyze the user's request and determine which tools are needed
        2. Create a plan with one or more steps, each using exactly ONE tool
        3. Each step MUST have: step (number), type ("tool_use"), tool_name, tool_input (object), reason
        4. If you cannot fulfill the request with available tools, use the "echo" tool to provide a helpful response

      PROMPT

      # Add delegation instructions if targets exist
      if has_delegation_targets
        prompt += <<~DELEGATION_INSTRUCTIONS

          ## Agent Delegation Capabilities

          You can delegate tasks to specialized agents when appropriate. Look for tools with names#{' '}
          starting with "agent_transfer_to_" in the Available Tools list. These special tools allow
          you to transfer control to another agent that specializes in specific tasks.

          When deciding whether to delegate:
          1. Consider if the task requires specialized knowledge or capabilities
          2. Choose the most appropriate specialized agent from the available delegation options
          3. Clearly specify the task for the specialized agent in the "task" parameter

          For example, if you see "agent_transfer_to_calculator_agent" and the user asks a math question,
          you can delegate by including this in your plan:
          ```json
          {
            "step": 1,
            "type": "tool_use",
            "tool_name": "agent_transfer_to_calculator_agent",
            "tool_input": {"task": "Calculate 125 * 45"},
            "reason": "This requires mathematical calculation"
          }
          ```
        DELEGATION_INSTRUCTIONS
      end

      # Continue with the standard prompt
      prompt += <<~PROMPT

        ## CRITICAL INSTRUCTION:

        To answer the user's request, you MUST use the available tools to generate responses, especially the "echo" tool.#{' '}
        Even if you think you can't fulfill the request perfectly, use the "echo" tool to provide the best possible response.

        DO NOT say that you can't help or that your capabilities are limited. Instead, use your knowledge and the available tools to provide a helpful response.

        ## Available Tools

        #{tools_description}

        ## User Request

        #{user_input}
      PROMPT

      prompt
    end

    # Parses the text response from Gemini, expecting a JSON array.
    #
    # @deprecated Use {#validate_and_format_multi_step_plan} instead.
    # @param response_text [String] The raw response text from the LLM.
    # @return [Array] The parsed JSON array, or empty array on failure.
    def parse_gemini_response(response_text)
      logger.debug("Attempting to parse Gemini response text: #{response_text}")

      # First attempt: try direct JSON parsing
      begin
        parsed = JSON.parse(response_text)
        return parsed if parsed.is_a?(Array)

        logger.warn("JSON parsed successfully but not an array: #{parsed.class}")
      rescue JSON::ParserError => e
        logger.debug("Direct JSON parsing failed: #{e.message}, trying extraction methods")
      end

      # Try different extraction methods
      candidate_json = nil

      # Method 1: Extract JSON array using regex - find anything between square brackets
      json_array_match = response_text.match(/(\[.*\])/m)
      if json_array_match
        # Use the matched array part
        candidate_json = json_array_match[1].strip
        logger.debug('Found JSON array match via regex')
      else
        # Method 2: Clean up markdown code blocks
        clean_text = response_text.strip
        if clean_text.include?('```json')
          # Extract content from ```json ... ``` block
          match = clean_text.match(/```json\s*(.*?)\s*```/m)
          candidate_json = match ? match[1].strip : clean_text
          logger.debug('Extracted from ```json block')
        elsif clean_text.include?('```')
          # Extract content from ``` ... ``` block
          match = clean_text.match(/```\s*(.*?)\s*```/m)
          candidate_json = match ? match[1].strip : clean_text
          logger.debug('Extracted from ``` block')
        else
          candidate_json = clean_text
          logger.debug('Using cleaned text as-is')
        end
      end

      # Handle edge cases and empty array
      if candidate_json.nil? || candidate_json.empty?
        logger.error('Empty JSON candidate after extraction')
        return []
      end

      # Return empty array explicitly if that's what we got
      return [] if candidate_json.strip == '[]'

      # Ensure it looks like an array before parsing
      unless candidate_json.strip.start_with?('[') && candidate_json.strip.end_with?(']')
        logger.error("Gemini response does not appear to be a JSON array: #{response_text}")
        logger.error("After cleanup attempt, still not a JSON array: #{candidate_json}")
        return [] # Return empty array instead of raising to be more resilient
      end

      # Final parsing attempt
      begin
        JSON.parse(candidate_json)
      rescue JSON::ParserError => e
        logger.error("Failed to parse Gemini response as JSON: #{e.message}")
        logger.error("Raw response text was: #{response_text}")
        logger.error("Extracted candidate was: #{candidate_json}")
        # Return empty array instead of raising, for resilience
        []
      end
    end

    # Validates and formats the multi-step plan response from the LLM.
    #
    # @api private
    # @param llm_response [String] The raw response string from the LLM.
    # @return [Hash] A hash containing :thought_process and :formatted_steps, or :error.
    def validate_and_format_multi_step_plan(llm_response)
      # Try multiple methods to extract JSON from the response
      parsed_json = extract_json_from_response(llm_response)

      # If we still don't have valid JSON, log and return error
      if parsed_json.nil?
        logger.warn("Failed to extract valid JSON from LLM response. Full response:\n#{llm_response}")
        return { error: 'Failed to extract valid JSON from LLM response' }
      end

      # Extract plan array from the JSON
      plan = parsed_json['plan']
      thought_process = parsed_json['thought_process']

      # Add enhanced error handling and plan validation
      if plan.nil? || !plan.is_a?(Array) || plan.empty?
        logger.warn("Invalid or empty plan structure: #{parsed_json.inspect}")
        return { error: 'Invalid or empty plan structure returned by the model' }
      end

      # Ensure each step has the required fields
      formatted_steps = []

      plan.each_with_index do |step, index|
        step_number = index + 1

        # Common validation for all step types
        unless step.key?('step') && step.key?('type') && step.key?('reason')
          logger.warn("Step #{step_number} is missing required fields: #{step.inspect}")
          return { error: "Step #{step_number} is missing required fields" }
        end

        # Type-specific validation - only accept tool_use
        if step['type'] != 'tool_use'
          logger.warn("Step #{step_number} has invalid type: #{step['type']}")
          return { error: "Step #{step_number} has invalid type: #{step['type']}" }
        end

        # Validate tool use fields
        unless step.key?('tool_name') && step.key?('tool_input')
          logger.warn("Step #{step_number} is missing required tool fields: #{step.inspect}")
          return { error: "Step #{step_number} is missing required tool fields" }
        end

        # Check if tool_input is a hash
        unless step['tool_input'].is_a?(Hash)
          logger.warn("Step #{step_number} has invalid tool_input (not a hash): #{step['tool_input'].inspect}")
          return { error: "Step #{step_number} has invalid tool_input: must be a hash/object" }
        end

        # Format as proper tool step
        formatted_steps << {
          tool: step['tool_name'].to_sym,
          params: step['tool_input'].transform_keys { |k|
            begin
              k.to_sym
            rescue StandardError
              k
            end
          },
          reason: step['reason']
        }
      end

      # Return the formatted plan
      if formatted_steps.empty?
        { error: 'No valid steps could be extracted from the plan' }
      else
        {
          thought_process: thought_process,
          formatted_steps: formatted_steps
        }
      end
    end

    # Extract a useful message from the LLM response for fallback
    # @param llm_response [String] The raw LLM response
    # @param user_input [String] The original user input
    # @return [String] A message to use in the fallback response
    def extract_fallback_message(llm_response, user_input)
      # Try to find any meaningful content from the response
      # Remove markdown code blocks and JSON-like structures
      clean_response = llm_response
                       .gsub(/```[\s\S]*?```/, '') # Remove code blocks
                       .gsub(/\{[\s\S]*\}/, '')    # Remove JSON objects
                       .strip

      # If we have some clean text, use it (truncated if too long)
      if clean_response.length > 20
        truncated = clean_response.length > 500 ? "#{clean_response[0..500]}..." : clean_response
        "Based on your request '#{user_input}': #{truncated}"
      else
        # Generic fallback message
        "I received your request '#{user_input}' but encountered an issue processing it. Please try rephrasing your request."
      end
    end

    # Create fallback plan steps using echo tool
    # @param message [String] The message to echo
    # @return [Array<Hash>] Plan steps array
    def fallback_plan_steps(message)
      echo_tool_exists = agent.available_tools_metadata.any? { |m| m[:name] == :echo }
      if echo_tool_exists
        [{ tool: :echo, params: { message: message }, reason: 'Fallback response' }]
      else
        logger.error('Fallback failed: Echo tool not available to the agent.')
        []
      end
    end

    # Attempts to extract JSON from the LLM response using multiple methods.
    #
    # @param response_text [String] The raw response text from the LLM.
    # @return [Hash, nil] The parsed JSON object or nil if extraction failed.
    def extract_json_from_response(response_text)
      # Method 1: Try to extract from markdown code block (```json ... ```)
      json_code_block_match = response_text.match(/```(?:json)?\s*(\{.*?\})\s*```/m)
      if json_code_block_match
        begin
          json = JSON.parse(json_code_block_match[1])
          logger.debug('Successfully extracted JSON from markdown code block')
          return json
        rescue JSON::ParserError => e
          logger.debug("Failed to parse JSON from code block: #{e.message}")
        end
      end

      # Method 2: Try direct JSON object extraction (greedy match from first { to last })
      # Use a non-greedy inner match but capture the full object structure
      json_pattern = /(\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\})/m
      json_match = response_text.match(json_pattern)
      if json_match
        begin
          json = JSON.parse(json_match[1])
          logger.debug('Successfully extracted JSON via regex pattern')
          return json
        rescue JSON::ParserError => e
          logger.debug("Failed to parse extracted JSON: #{e.message}")
        end
      end

      # Method 3: Try the simple greedy pattern as fallback
      simple_pattern = /\{.*\}/m
      simple_match = response_text.match(simple_pattern)
      if simple_match
        begin
          json = JSON.parse(simple_match[0])
          logger.debug('Successfully extracted JSON via simple pattern')
          return json
        rescue JSON::ParserError => e
          logger.debug("Failed to parse JSON from simple pattern: #{e.message}")
        end
      end

      nil
    end

    # Fallback plan remains the same (single echo step)
    def fallback_plan(task, reason)
      # ... (implementation from previous response - no change needed) ...
      logger.warn("Falling back to echo plan. Reason: #{reason}")
      # Find if echo tool exists using metadata
      echo_tool_exists = agent.available_tools_metadata.any? { |m| m[:name] == :echo }
      if echo_tool_exists
        [
          {
            tool: :echo,
            params: { message: "Planning failed: #{reason}. Original task: #{task}" }
          }
        ]
      else
        logger.error('Fallback failed: Echo tool not available to the agent.')
        [] # Return empty plan if echo isn't available
      end
    end
  end
end
