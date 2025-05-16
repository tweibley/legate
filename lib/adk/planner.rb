# File: lib/adk/planner.rb
# frozen_string_literal: true

require 'gemini-ai'
require 'json'
require 'logger'

module ADK
  class Planner
    attr_reader :agent, :logger, :model_name # Add model_name reader

    # --- MODIFY initialize signature and logic ---
    def initialize(agent:, model_name: nil, **options) # Add model_name param
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

    # Plan a task using the gemini-ai gem
    # @param task [String] The task to plan
    # @return [Array] The plan (array of step hashes) or a fallback plan on error
    def plan(user_input)
      # Check if client is available, fallback if not
      unless @client
        logger.error("Gemini client not initialized. Falling back to default plan.")
        return fallback_plan(user_input, "No LLM client available")
      end

      # Format tools for the prompt
      tools_description = format_tools_for_prompt

      # Build and send the planning prompt to the LLM
      prompt = build_multi_step_gemini_prompt(user_input, tools_description)

      # Use the LLM client from the Gemini wrapper
      begin
        response = @client.generate_content(
          {
            contents: [{ role: 'user', parts: { text: prompt } }]
          }
        )

        raw_response_text = response.dig('candidates', 0, 'content', 'parts', 0, 'text')

        unless raw_response_text
          logger.warn("Gemini response was empty or couldn't find text.")
          logger.debug("Raw Gemini Response Object: #{response.inspect}")
          return { error: 'Gemini response was empty or unparseable.' }
        end

        # Extract and validate the plan
        validated_result = validate_and_format_multi_step_plan(raw_response_text)

        # Check for errors in validation
        if validated_result[:error]
          logger.error("Plan validation failed: #{validated_result[:error]}")
          return { error: validated_result[:error] }
        end

        # Return the formatted plan steps
        {
          thought_process: validated_result[:thought_process],
          steps: validated_result[:formatted_steps]
        }
      rescue StandardError => e
        logger.error("Error during planning with Gemini: #{e.class}: #{e.message}")
        fallback_plan(user_input, "Error during planning: #{e.message}")
      end
    end

    private

    # Format tools metadata for the prompt
    # Fetches metadata from the agent instance directly.
    def format_tools_for_prompt
      tools_metadata = agent.available_tools_metadata # Fetch metadata here
      delegation_targets_description = format_delegation_targets
      sequential_sub_agents_description = format_sequential_sub_agents

      if tools_metadata.empty? && delegation_targets_description.empty? && sequential_sub_agents_description.empty?
        return 'No tools or delegable agents available.'
      end

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

      targets_description = delegation_targets.map do |target_name|
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

      targets_description
    end

    # Format sequential sub-agents for the prompt
    # Each sequential sub-agent is presented as a "tool" with a task parameter
    def format_sequential_sub_agents
      return '' unless @agent.definition.respond_to?(:sequential_sub_agent_names) && @agent.definition.sequential_sub_agent_names&.any?

      sub_agent_names = @agent.definition.sequential_sub_agent_names
      logger.info("Planner including #{sub_agent_names.size} sequential sub-agents: #{sub_agent_names.to_a.join(', ')}")

      sub_agents_description = sub_agent_names.map do |agent_name|
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

      sub_agents_description
    end

    # --- NEW: Build the multi-step prompt ---
    def build_multi_step_gemini_prompt(user_input, tools_description)
      # Check if agent has delegation targets
      has_delegation_targets = @agent.definition.respond_to?(:delegation_targets) &&
                               @agent.definition.delegation_targets&.any?

      # Get agent instruction if available
      agent_instruction = @agent.respond_to?(:instruction) ? @agent.instruction : nil
      instruction_text = agent_instruction&.strip.to_s

      # Build the prompt with clearer delegation instructions if relevant
      prompt = <<~PROMPT
        # Instructions

        You are an AI assistant that helps people by breaking down tasks into simpler steps.
        #{!instruction_text.empty? ? "\n" + instruction_text + "\n" : ""}

        ## Response Format Requirements

        1. ALWAYS respond with valid JSON format following this structure:
        ```json
        {
          "thought_process": "Your reasoning about the user's request",
          "plan": [
            {
              "step": 1,
              "type": "tool_use",#{' '}
              "tool_name": "echo",
              "tool_input": {"message": "Your message content here"},
              "reason": "Why this step is necessary"
            }
          ]
        }
        ```

        2. Each step MUST have:
           - A sequential number ("step")
           - A "type" field which must be exactly "tool_use" (this is the only valid type)
           - A "tool_name" field with the exact name of a tool from the Available Tools list
           - A "tool_input" object with the correct parameters for that tool
           - A "reason" explaining the purpose of this step

        3. IMPORTANT: Your output MUST be parseable as a JSON object with the fields described above.
           - DO NOT add markdown code fences (```) outside the JSON
           - DO NOT add explanations outside the JSON structure
           - All JSON keys and string values MUST use double quotes

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

    # Parse the text response from Gemini, expecting a JSON array
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
        logger.debug("Found JSON array match via regex")
      else
        # Method 2: Clean up markdown code blocks
        clean_text = response_text.strip
        if clean_text.include?('```json')
          # Extract content from ```json ... ``` block
          match = clean_text.match(/```json\s*(.*?)\s*```/m)
          candidate_json = match ? match[1].strip : clean_text
          logger.debug("Extracted from ```json block")
        elsif clean_text.include?('```')
          # Extract content from ``` ... ``` block
          match = clean_text.match(/```\s*(.*?)\s*```/m)
          candidate_json = match ? match[1].strip : clean_text
          logger.debug("Extracted from ``` block")
        else
          candidate_json = clean_text
          logger.debug("Using cleaned text as-is")
        end
      end

      # Handle edge cases and empty array
      if candidate_json.nil? || candidate_json.empty?
        logger.error("Empty JSON candidate after extraction")
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
        return []
      end
    end

    # --- NEW: Validate the parsed multi-step response ---
    def validate_and_format_multi_step_plan(llm_response)
      # Extract JSON from response
      json_pattern = /\{.*\}/m
      json_match = llm_response.match(json_pattern)

      if json_match.nil?
        logger.warn("Failed to extract JSON from LLM response: #{llm_response}")
        return { error: "Failed to extract valid JSON from LLM response" }
      end

      # Parse the JSON
      begin
        parsed_json = JSON.parse(json_match[0])
      rescue JSON::ParserError => e
        logger.warn("Failed to parse JSON from LLM response: #{e.message}\nResponse: #{llm_response}")
        return { error: "Failed to parse JSON: #{e.message}" }
      end

      # Extract plan array from the JSON
      plan = parsed_json["plan"]
      thought_process = parsed_json["thought_process"]

      # Add enhanced error handling and plan validation
      if plan.nil? || !plan.is_a?(Array) || plan.empty?
        logger.warn("Invalid or empty plan structure: #{parsed_json.inspect}")
        return { error: "Invalid or empty plan structure returned by the model" }
      end

      # Ensure each step has the required fields
      formatted_steps = []

      plan.each_with_index do |step, index|
        step_number = index + 1

        # Common validation for all step types
        unless step.key?("step") && step.key?("type") && step.key?("reason")
          logger.warn("Step #{step_number} is missing required fields: #{step.inspect}")
          return { error: "Step #{step_number} is missing required fields" }
        end

        # Type-specific validation - only accept tool_use
        if step["type"] != "tool_use"
          logger.warn("Step #{step_number} has invalid type: #{step['type']}")
          return { error: "Step #{step_number} has invalid type: #{step['type']}" }
        end

        # Validate tool use fields
        unless step.key?("tool_name") && step.key?("tool_input")
          logger.warn("Step #{step_number} is missing required tool fields: #{step.inspect}")
          return { error: "Step #{step_number} is missing required tool fields" }
        end

        # Check if tool_input is a hash
        unless step["tool_input"].is_a?(Hash)
          logger.warn("Step #{step_number} has invalid tool_input (not a hash): #{step["tool_input"].inspect}")
          return { error: "Step #{step_number} has invalid tool_input: must be a hash/object" }
        end

        # Format as proper tool step
        formatted_steps << {
          tool: step["tool_name"].to_sym,
          params: step["tool_input"].transform_keys { |k| k.to_sym rescue k },
          reason: step["reason"]
        }
      end

      # Return the formatted plan
      if formatted_steps.empty?
        { error: "No valid steps could be extracted from the plan" }
      else
        {
          thought_process: thought_process,
          formatted_steps: formatted_steps
        }
      end
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
