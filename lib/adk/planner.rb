# File: lib/adk/planner.rb
# frozen_string_literal: true

# require 'google/generative_ai' # Remove this
require 'gemini-ai' # Add this
require 'json'
require 'logger'

module ADK
  class Planner
    attr_reader :agent, :logger

    # Initialize the planner using the gemini-ai gem
    # @param agent [Agent] The agent this planner belongs to
    # @param options [Hash] Additional options
    # @option options [Logger] :logger Optional logger instance
    # @option options [String] :api_key Google AI API Key (defaults to ENV['GOOGLE_API_KEY'])
    def initialize(agent:, **options)
      @agent = agent
      @logger = options[:logger] || ADK.logger
      @api_key = options[:api_key] || ENV['GOOGLE_API_KEY']
      @client = nil # Initialize client as nil

      if @api_key.nil? || @api_key.empty?
        @logger.error("GOOGLE_API_KEY not found. GeminiPlanner requires an API key.")
        @client = nil
      else
        begin
          @client = Gemini.new(
            credentials: {
              service: 'generative-language-api',
              api_key: @api_key
            },
            options: { model: 'gemini-2.0-flash', server_sent_events: false }
          )
          # @model_name = @client.options[:model] # <--- REMOVE THIS LINE
          @model_name = 'gemini-2.0-flash' # <-- Store the model name directly
          logger.info("Gemini AI client initialized with model: #{@model_name}")
        rescue StandardError => e
          logger.error("Failed to initialize Gemini AI client: #{e.class}: #{e.message}")
          logger.error(e.backtrace.join("\n"))
          @client = nil
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
      prompt = build_gemini_prompt(task, available_tools)

      logger.info("Sending planning request to Gemini (via gemini-ai) for task: #{task}")
      # logger.debug("Gemini Prompt:\n#{prompt}") # Uncomment for debugging

      begin
        # API call using the gemini-ai gem's structure
        # Pass ONE hash argument, not keyword arguments
        response = @client.generate_content(
          { # <--- Start of the single Hash argument
            # The model should be set during client initialization,
            # so we likely only need to pass contents here.
            # Check gem docs if model override is needed/possible here.
            contents: [{ role: 'user', parts: { text: prompt } }]
          } # <--- End of the single Hash argument
        )

        # Accessing the response text - Check the gem's response structure
        # This dig might still be correct if it wraps the Google API response
        raw_response_text = response.dig('candidates', 0, 'content', 'parts', 0, 'text')

        unless raw_response_text
          logger.warn("Gemini response (via gemini-ai) was empty or couldn't find text.")
          # Try inspecting the response object if dig fails
          logger.debug("Raw Gemini Response Object: #{response.inspect}")
          return fallback_plan(task, "Gemini response was empty or unparseable.")
        end

        # logger.debug("Gemini Raw Response Text:\n#{raw_response_text}")

        parsed_plan = parse_gemini_response(raw_response_text)
        validated_plan = validate_and_format_plan(parsed_plan)

        if validated_plan.empty?
          logger.warn("Failed to get a valid plan from Gemini response. Falling back.")
          return fallback_plan(task, "Could not parse or validate Gemini's plan.")
        else
          logger.info("Plan received from Gemini: #{validated_plan}")
          return validated_plan
        end

      # Error handling might need adjustment based on errors raised by gemini-ai
      rescue JSON::ParserError => e
        logger.error("Failed to parse Gemini response as JSON: #{e.message}")
        logger.error("Raw response text was: #{raw_response_text}")
        return fallback_plan(task, "Invalid JSON response from Gemini.")
      rescue StandardError => e # Catch broader errors as specific API errors might differ
        logger.error("Error during planning with gemini-ai: #{e.class}: #{e.message}")
        logger.error(e.backtrace.join("\n"))
        return fallback_plan(task, "Gemini planning error: #{e.message}")
      end
    end

    # --- Helper methods (format_tools_for_prompt, build_gemini_prompt, parse_gemini_response, validate_and_format_plan, fallback_plan) ---
    # --- These methods should remain largely the same as they handle the content ---
    # --- Ensure they are present and correct as in the previous implementation ---

    private

    # Format available tools into a string for the prompt (Identical to previous version)
    def format_tools_for_prompt(tools)
      # ... (implementation from previous response) ...
      return "No tools available." if tools.empty?

      tools.map do |tool|
        params_desc = tool.parameters.map do |name, info|
          req = info[:required] ? "required" : "optional"
          "- #{name} (#{info[:type]}, #{req}): #{info[:description]}"
        end.join("\n    ")
        <<~TOOL_DESC
          Tool Name: #{tool.name}
          Description: #{tool.description}
          Parameters:
            #{params_desc.empty? ? 'None' : params_desc}
        TOOL_DESC
      end.join("\n\n")
    end

    # Build the prompt for the Gemini API call (Identical to previous version)
    def build_gemini_prompt(task, tools_description)
      # puts tools_description
      # ... (implementation from previous response) ...
      <<~PROMPT
        You are an AI planner for an agent. Your goal is to choose the single best tool to fulfill the user's request and determine the necessary parameters for that tool based ONLY on the request and the tool descriptions provided.

        Available Tools:
        ---
        #{tools_description}
        ---

        User Request: "#{task}"

        Instructions:
        1. Analyze the user request and the available tools.
        2. Select the single most appropriate tool from the list provided. The tool name must match EXACTLY one of the "Tool Name" values above.
        3. Determine the values for the tool's required parameters based on the user request. If optional parameters can be inferred, include them.
        4. Respond ONLY with a single JSON object in the following format:
           {
             "tool_name": "exact_tool_name_here",
             "parameters": {
               "param1_name": "value1",
               "param2_name": "value2"
               // ... include all necessary parameters derived from the request
             }
           }
        5. If no suitable tool is found among the available tools to fulfill the request, respond ONLY with the following JSON object:
           {
             "tool_name": null,
             "parameters": null
           }
        6. Do not include any explanation, commentary, or text outside the JSON object in your response.
      PROMPT
    end

    # Parse the text response from Gemini, expecting JSON (Identical to previous version)
    def parse_gemini_response(response_text)
      # ... (implementation from previous response) ...
      # Sometimes the model might still wrap the JSON in backticks or "json" language identifier
      clean_text = response_text.strip.delete_prefix("```json").delete_prefix("```").delete_suffix("```").strip
      JSON.parse(clean_text)
    end

    # Validate the parsed response and format it into the ADK plan structure (Identical to previous version)
    def validate_and_format_plan(parsed_response)
      # ... (implementation from previous response) ...
      tool_name_str = parsed_response['tool_name']
      parameters = parsed_response['parameters']

      # Handle the "no suitable tool" case
      return [] if tool_name_str.nil?

      tool_name_sym = tool_name_str.to_sym

      # Find the actual tool to ensure it exists
      tool = agent.tools.find { |t| t.name == tool_name_sym }

      unless tool
        logger.warn("Gemini suggested tool '#{tool_name_sym}' which is not available to the agent.")
        return [] # Return empty plan if tool doesn't exist
      end

      unless parameters.is_a?(Hash)
        logger.warn("Gemini response 'parameters' field was not a JSON object.")
        return []
      end

      # Basic validation (could add more checks for required params if needed)
      # Convert parameter keys to symbols for the Tool#execute method
      symbolized_params = parameters.transform_keys(&:to_sym)

      # Return the plan in the expected format
      [{ tool: tool_name_sym, params: symbolized_params }]
    end

    # Default plan to use if Gemini fails (Identical to previous version)
    def fallback_plan(task, reason)
      # ... (implementation from previous response) ...
      logger.warn("Falling back to echo plan. Reason: #{reason}")
      [
        {
          tool: :echo,
          params: { message: "Planning failed: #{reason}. Original task: #{task}" }
        }
      ]
    end
  end
end
