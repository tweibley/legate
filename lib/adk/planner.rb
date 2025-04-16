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
        @logger.error("GOOGLE_API_KEY not found. GeminiPlanner requires an API key.")
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
    def plan(task)
      unless @client
        logger.error("Gemini client not initialized. Falling back to default plan.")
        return fallback_plan(task, "Gemini client not available.")
      end

      available_tools = format_tools_for_prompt(agent.tools)
      # --- Use the NEW multi-step prompt ---
      prompt = build_multi_step_gemini_prompt(task, available_tools)

      logger.info("Sending multi-step planning request to Gemini (#{@model_name}) for task: #{task}")
      # logger.debug("Gemini Prompt:\n#{prompt}") # Uncomment for deep debugging

      begin
        response = @client.generate_content(
          {
            contents: [{ role: 'user', parts: { text: prompt } }]
            # --- Add safety setting to encourage JSON output ---
            # Check Gemini API docs for exact names if needed
            # safety_settings: [
            #   { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_NONE' },
            #   # Add others if needed
            # ],
            # generation_config: {
            #    response_mime_type: "application/json" # Request JSON directly if model supports it
            # }
            # Note: Check if gemini-ai gem exposes these generation_config options.
            # If not, we rely on prompt instructions and parsing.
          }
        )

        raw_response_text = response.dig('candidates', 0, 'content', 'parts', 0, 'text')

        unless raw_response_text
          logger.warn("Gemini response was empty or couldn't find text.")
          logger.debug("Raw Gemini Response Object: #{response.inspect}")
          return fallback_plan(task, "Gemini response was empty or unparseable.")
        end

        # logger.debug("Gemini Raw Response Text:\n#{raw_response_text}")

        parsed_plan = parse_gemini_response(raw_response_text) # Expects JSON array now
        validated_plan = validate_and_format_multi_step_plan(parsed_plan) # New validation method

        if validated_plan.empty?
          logger.warn("Failed to get a valid multi-step plan from Gemini response. Falling back.")
          # logger.debug("Parsed plan before validation: #{parsed_plan.inspect}") # Debugging line
          return fallback_plan(task, "Could not parse or validate Gemini's multi-step plan.")
        else
          logger.info("Multi-step plan received from Gemini: #{validated_plan}")
          return validated_plan
        end
      rescue JSON::ParserError => e
        logger.error("Failed to parse Gemini response as JSON: #{e.message}")
        logger.error("Raw response text was: #{raw_response_text}")
        return fallback_plan(task, "Invalid JSON response from Gemini.")
      rescue StandardError => e
        logger.error("Error during planning with gemini-ai: #{e.class}: #{e.message}")
        logger.error(e.backtrace.join("\n"))
        return fallback_plan(task, "Gemini planning error: #{e.message}")
      end
    end

    private

    # Format tools (remains the same)
    def format_tools_for_prompt(tools)
      # ... (implementation from previous response - no change needed) ...
      return "No tools available." if tools.empty?

      tools.map do |tool|
        params_desc = tool.parameters.map do |name, info|
          req = info[:required] ? "required" : "optional"
          # Ensure type is displayed, default to 'any' if missing
          type = info[:type] || 'any'
          "- #{name} (#{type}, #{req}): #{info[:description]}"
        end.join("\n    ")
        <<~TOOL_DESC
          Tool Name: #{tool.name}
          Description: #{tool.description}
          Parameters:
            #{params_desc.empty? ? 'None' : params_desc}
        TOOL_DESC
      end.join("\n\n")
    end

    # --- NEW: Build the multi-step prompt ---
    def build_multi_step_gemini_prompt(task, tools_description)
      <<~PROMPT
        You are an AI planner for an agent. Your goal is to break down the user's request into a sequence of steps. Each step must use exactly one of the available tools. You need to determine the necessary parameters for each tool call based on the user request AND the potential output of previous steps.

        Available Tools:
        ---
        #{tools_description}
        ---

        User Request: "#{task}"

        Instructions:
        1. Analyze the user request and the available tools.
        2. Determine the sequence of tool calls needed to fulfill the request.
        3. For each step, identify the exact tool name (must match a "Tool Name" from the list).
        4. For each step, determine the values for its parameters. Parameter values can come from the original request OR **implicitly from the result of the previous step** if applicable (e.g., if step 1 gets a number, step 2 might use that number).
        5. Respond ONLY with a single JSON array where each element represents one step in the sequence. Each step object must have the following format:
           {
             "tool_name": "exact_tool_name_here",
             "parameters": {
               "param1_name": "value1", // Values derived from request or previous step output
               "param2_name": "value2"
               // ... include all necessary parameters for this step
             }
           }
        6. If the request can be fulfilled by a single tool call, the array will contain only one step object.
        7. If the request cannot be fulfilled by any sequence of the available tools, respond ONLY with an empty JSON array: `[]`.
        8. Do not include any explanation, commentary, or text outside the JSON array in your response. Ensure the output is valid JSON.

        Example Request: "Generate a random number and then tell me that number."
        Example Tools: random_number (no params), echo (param: message)
        Example Response:
        [
          {
            "tool_name": "random_number",
            "parameters": {}
          },
          {
            "tool_name": "echo",
            "parameters": {
              "message": "[Result from step 1]" // You should infer how to represent the dependency
            }
          }
        ]
        // (Note: The actual parameter value for 'echo' in the real response should be derived by the agent during execution based on step 1's output, but the LLM needs to structure the plan correctly).

        Now, plan the User Request: "#{task}"
      PROMPT
    end

    # Parse the text response from Gemini, expecting a JSON array (minor change)
    def parse_gemini_response(response_text)
      logger.debug("Attempting to parse Gemini response text: #{response_text}")
      # Sometimes the model might still wrap the JSON in backticks or "json" language identifier
      clean_text = response_text.strip
      if clean_text.start_with?('```json') && clean_text.end_with?('```')
        clean_text = clean_text.delete_prefix('```json').delete_suffix('```').strip
      elsif clean_text.start_with?('```') && clean_text.end_with?('```')
        clean_text = clean_text.delete_prefix('```').delete_suffix('```').strip
      end
      # Ensure it looks like an array before parsing
      unless clean_text.start_with?('[') && clean_text.end_with?(']')
        # Maybe it's the failure case? Check for empty array explicitly
        return [] if clean_text == '[]'

        # Otherwise, it's likely invalid format
        logger.error("Gemini response does not appear to be a JSON array: #{clean_text}")
        raise JSON::ParserError, "Response is not a JSON array."
      end

      JSON.parse(clean_text)
    end

    # --- NEW: Validate the parsed multi-step response ---
    def validate_and_format_multi_step_plan(parsed_response)
      unless parsed_response.is_a?(Array)
        logger.warn("Parsed Gemini response was not an Array: #{parsed_response.inspect}")
        return [] # Return empty plan if it's not even an array
      end

      plan_steps = []
      available_tool_syms = agent.tools.map(&:name)

      parsed_response.each_with_index do |step_data, index|
        unless step_data.is_a?(Hash)
          logger.warn("Step #{index + 1} in Gemini plan is not a Hash: #{step_data.inspect}")
          return [] # Invalid plan if any step is malformed
        end

        tool_name_str = step_data['tool_name']
        parameters = step_data['parameters']

        # Handle potential null tool_name (shouldn't happen with array format, but check)
        if tool_name_str.nil? || tool_name_str.empty?
          logger.warn("Step #{index + 1} has missing 'tool_name'.")
          return [] # Invalid step
        end

        tool_name_sym = tool_name_str.to_sym

        # Check if tool exists
        unless available_tool_syms.include?(tool_name_sym)
          logger.warn("Step #{index + 1} suggested tool '#{tool_name_sym}' which is not available to the agent. Available: #{available_tool_syms.join(', ')}")
          return [] # Invalid plan if tool doesn't exist
        end

        # Check parameters format
        unless parameters.is_a?(Hash)
          logger.warn("Step #{index + 1} 'parameters' field was not a JSON object: #{parameters.inspect}")
          # Allow empty parameters if the tool definition has none or only optional ones.
          # Let tool validation handle required params later. Assume {} if not a hash for now? Or fail? Let's fail for stricter planning.
          return [] # Fail if params isn't a Hash
        end

        # Convert parameter keys to symbols for Tool#execute
        symbolized_params = parameters.transform_keys do |k|
          k.to_sym rescue k # Keep original if conversion fails
        end

        # Add the validated step to the plan
        plan_steps << { tool: tool_name_sym, params: symbolized_params }
      end

      # Return the fully validated sequence of steps
      plan_steps
    end

    # Fallback plan remains the same (single echo step)
    def fallback_plan(task, reason)
      # ... (implementation from previous response - no change needed) ...
      logger.warn("Falling back to echo plan. Reason: #{reason}")
      # Find if echo tool exists to use it
      echo_tool_exists = agent.tools.any? { |t| t.name == :echo }
      if echo_tool_exists
        [
          {
            tool: :echo,
            params: { message: "Planning failed: #{reason}. Original task: #{task}" }
          }
        ]
      else
        logger.error("Fallback failed: Echo tool not available to the agent.")
        [] # Return empty plan if echo isn't available
      end
    end
  end
end
