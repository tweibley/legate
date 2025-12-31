# File: lib/adk/tool.rb
# frozen_string_literal: true

require_relative 'tool_registry'
require 'logger'
require 'did_you_mean'
require_relative 'tool_context'
require_relative 'global_tool_manager'
require_relative 'tool/metadata_dsl'
require 'json'

module ADK
  # Base class for all tools that can be used by Agents.
  #
  # Tools are the way agents interact with the outside world. To create a new tool,
  # inherit from this class, use the DSL to define metadata, and implement
  # the {#perform_execution} method.
  #
  # @example Creating a custom weather tool
  #   class WeatherTool < ADK::Tool
  #     tool_description 'Fetches current weather for a location'
  #
  #     parameter :location, type: :string, required: true,
  #               description: 'City name (e.g. "San Francisco")'
  #
  #     parameter :unit, type: :string, required: false,
  #               description: 'Temperature unit (celsius/fahrenheit)'
  #
  #     private
  #
  #     def perform_execution(params, context)
  #       location = params[:location]
  #       # ... fetch weather logic ...
  #       weather_data = "Sunny, 25C"
  #
  #       {
  #         status: :success,
  #         result: weather_data
  #       }
  #     rescue => e
  #       {
  #         status: :error,
  #         error_message: "Failed to fetch weather: #{e.message}"
  #       }
  #     end
  #   end
  #
  class Tool
    # --- Include the DSL ---
    include MetadataDsl

    # --- Class-level attributes --- Accessors defined via DSL, but keep old readers/define_metadata for backward compat ---
    class << self
      # Keep old readers for define_metadata compatibility
      attr_reader :tool_name, :description, :parameters_definition

      # Define the tool's static metadata.
      # DEPRECATED: Use `tool_description`, `parameter`, and automatic name inference instead.
      def define_metadata(name:, description:, parameters: {})
        warn "[DEPRECATION] `define_metadata` is deprecated. Use `tool_description`, `parameter`, and rely on class name inference (or `self.explicit_tool_name = :my_name`) instead. Called from #{caller_locations(
          1, 1
        )[0].label}"

        @tool_name = name.to_sym
        @description = description
        @parameters_definition = parameters
        @_tool_metadata_cache = nil # Invalidate cache
      end

      # --- Fallback Metadata Method (Commented out as DSL version takes precedence) ---
      # def tool_metadata
      #   ...
      # end
      # --- End Fallback Metadata Method ---
    end
    # --- End Class-level ---

    # --- Self-Registration Hook ---
    # NOTE: We intentionally do NOT auto-register tools in the inherited hook.
    # The reason is that `inherited` is called BEFORE the class body executes,
    # so explicit_tool_name and other DSL methods haven't run yet. This would
    # cause tools to be registered under their inferred name (e.g., :random_number_tool)
    # instead of their explicit name (e.g., :random_number).
    #
    # Instead, built-in tools are explicitly registered in lib/adk.rb after their
    # class definitions are complete. Custom tools should either:
    # 1. Call `ADK::GlobalToolManager.register_tool(MyTool)` explicitly after definition
    # 2. Be discovered via tool_paths when creating agents
    def self.inherited(subclass)
      super # Call parent's inherited if necessary
      ADK.logger.debug("Tool subclass #{subclass} inherited. Tool will be registered when explicitly added to GlobalToolManager or an agent's tool registry.")
    end
    # --- End Hook ---

    # Instance readers
    attr_reader :name, :description, :parameters

    # Initialize - Sets instance vars from class metadata
    def initialize(**_options)
      # Fetch metadata using the primary tool_metadata method (defined by DSL)
      metadata = self.class.tool_metadata
      @name = metadata[:name]
      @description = metadata[:description]
      @parameters = metadata[:parameters] || {}

      # Lenient check for missing metadata
      return unless @name.nil? || @name == :'' || @description.nil? || @description.empty?

      is_anonymous = !self.class.name || self.class.name.empty? || self.class.name.start_with?('#<Class:')
      unless is_anonymous
        missing = []
        missing << ':name' if @name.nil? || @name == :''
        missing << ':description' if @description.nil? || @description.empty?
        ADK.logger.warn("Tool class #{self.class} initialized with missing metadata: [#{missing.join(', ')}] using #{self.class.tool_metadata}. Tool may not function correctly.")
      end
      @description ||= ''
    end

    # Execute the tool
    # @param params [Hash] Input parameters for the tool.
    # @param context [ADK::ToolContext, nil] Contextual information (session details).
    # @return [Hash] A hash with :status (:success, :error, :pending) and :result/:error_message/:workflow_id.
    def execute(params = {}, context = nil)
      coerced_params = validate_and_coerce_params(params)
      ADK.logger.debug("Executing tool '#{@name}' with validated params: #{coerced_params.inspect} and context: #{context&.to_h.inspect}")
      perform_execution(coerced_params, context)
    end

    # Validate the parameters (Deprecated: Use validate_and_coerce_params)
    # This method is kept for backward compatibility and wraps the new logic,
    # but ignores the coerced return value.
    def validate_params(params)
      validate_and_coerce_params(params)
      nil
    end

    # Validate and coerce parameters based on metadata types
    # @param params [Hash] Input parameters
    # @return [Hash] New hash with symbol keys and coerced values
    # @raise [ADK::ToolArgumentError] if validation fails
    def validate_and_coerce_params(params)
      # 1. Normalize keys to symbols
      normalized_params = params.transform_keys(&:to_sym)

      current_parameters = @parameters || {}

      # 2. Check for missing required parameters
      # Use symbol keys for check
      required_param_names = current_parameters.select { |_, p| p[:required] }.keys
      present_keys = normalized_params.keys
      missing_params = required_param_names - present_keys

      unless missing_params.empty?
        msg = "Missing required parameters for tool '#{@name}': #{missing_params.join(', ')}."
        msg += " Provided: [#{present_keys.empty? ? 'None' : present_keys.join(', ')}]."

        if defined?(::DidYouMean::SpellChecker)
          # Check for typos in provided keys against missing required params
          suggestions = []
          dictionary = missing_params.map(&:to_s)
          checker = ::DidYouMean::SpellChecker.new(dictionary: dictionary)

          # Normalize to strings for comparison to handle Symbol vs String keys
          known_keys_str = current_parameters.keys.map(&:to_s)
          unknown_keys = present_keys.select { |k| !known_keys_str.include?(k.to_s) }

          unknown_keys.each do |key|
            found = checker.correct(key.to_s)
            found.each do |suggestion|
              suggestions << "'#{suggestion}' for '#{key}'"
            end
          end

          msg += " Did you mean #{suggestions.join(', ')}?" unless suggestions.empty?
        end

        ADK.logger.error("Validation failed: #{msg} Params: #{params.inspect}")
        raise ADK::ToolArgumentError, msg
      end

      # 3. Type Validation & Coercion
      coerced_params = normalized_params.dup

      current_parameters.each do |param_name, param_def|
        # Only process if present
        next unless coerced_params.key?(param_name)

        value = coerced_params[param_name]
        expected_type = param_def[:type]
        next unless expected_type

        begin
          coerced_value = coerce_value(value, expected_type)
          coerced_params[param_name] = coerced_value
        rescue ArgumentError, TypeError => e
          raise ADK::ToolArgumentError, "Parameter '#{param_name}' for tool '#{@name}' error: #{e.message}"
        end
      end

      coerced_params
    end

    private

    # Coerce a value to the expected type
    def coerce_value(value, type)
      return value if value.nil?

      case type
      when :string
        value.to_s
      when :integer
        # Integer(val) handles strings like "123" and numbers like 123.0 (truncates)
        begin
          Integer(value)
        rescue ArgumentError, TypeError
          raise ADK::ToolArgumentError, "expected Integer, got #{value.class} (#{value.inspect})"
        end
      when :float, :numeric
        # :numeric treated as Float for broad compatibility
        begin
          Float(value)
        rescue ArgumentError, TypeError
          raise ADK::ToolArgumentError, "expected Numeric/Float, got #{value.class} (#{value.inspect})"
        end
      when :boolean
        if value.is_a?(TrueClass) || value.is_a?(FalseClass)
          value
        elsif value.is_a?(String)
          case value.downcase
          when 'true', 't', 'yes', '1' then true
          when 'false', 'f', 'no', '0' then false
          else
            raise ADK::ToolArgumentError, "expected Boolean, got String '#{value}'"
          end
        else
          raise ADK::ToolArgumentError, "expected Boolean, got #{value.class} (#{value.inspect})"
        end
      when :array
        if value.is_a?(Array)
          value
        elsif value.is_a?(String)
          begin
            parsed = JSON.parse(value)
            raise ArgumentError unless parsed.is_a?(Array)

            parsed
          rescue StandardError
            raise ADK::ToolArgumentError, "expected Array, got #{value.class} (#{value.inspect})"
          end
        else
          raise ADK::ToolArgumentError, "expected Array, got #{value.class} (#{value.inspect})"
        end
      when :hash
        if value.is_a?(Hash)
          value
        elsif value.is_a?(String)
          begin
            parsed = JSON.parse(value)
            raise ArgumentError unless parsed.is_a?(Hash)

            parsed
          rescue StandardError
            raise ADK::ToolArgumentError, "expected Hash, got #{value.class} (#{value.inspect})"
          end
        else
          raise ADK::ToolArgumentError, "expected Hash, got #{value.class} (#{value.inspect})"
        end
      else
        # Unknown type or 'any', return as is
        value
      end
    end

    # Perform the actual execution of the tool.
    #
    # This method must be implemented by subclasses to define the tool's behavior.
    #
    # @param params [Hash] The validated parameters to execute with. Keys are symbols.
    # @param context [ADK::ToolContext] Contextual information (session, user, state).
    #
    # @return [Hash] The result hash containing:
    #   * :status [Symbol] :success, :error, or :pending
    #   * :result [Object] The output data (if success)
    #   * :error_message [String] Error description (if error)
    #   * :job_id [String] Job ID (if pending/async)
    #
    # @raise [NotImplementedError] if the subclass does not implement this method.
    def perform_execution(params, context)
      raise NotImplementedError, 'Subclasses must implement #perform_execution(params, context)'
    end
  end
end
