# File: lib/adk/cli/output_helper.rb
# frozen_string_literal: true

require 'json'
require 'did_you_mean'

module ADK
  module CLI
    # Helper module for CLI output control.
    # Provides methods to conditionally output status messages and format results
    # based on --quiet and --json flags.
    module OutputHelper
      # Write status/progress message (suppressed in quiet or json mode)
      # @param message [String] The status message to display
      # @param color [Symbol, nil] Optional color for Thor's say method
      def status_message(message, color = nil)
        return if quiet_mode?

        say message, color
      end

      # Output final result (JSON format in --json mode, otherwise uses format_method or default)
      # @param data [Object] The result data to output
      # @param metadata [Hash] Additional metadata to include (e.g., session_id)
      # @param format_method [Symbol] Method name to call for human-friendly formatting
      def output_result(data, metadata: {}, format_method: nil)
        if json_mode?
          output_json(data, metadata)
        elsif format_method && respond_to?(format_method, true)
          send(format_method, data)
        else
          say data.inspect
        end
      end

      # Output error (JSON format in --json mode, otherwise text to stderr)
      # @param error [Exception, String] The error to output
      # @param metadata [Hash] Additional metadata to include
      def output_error(error, metadata: {})
        suggestions = get_suggestions(metadata)

        if json_mode?
          output_json_error(error, metadata, suggestions)
        else
          output_text_error(error, suggestions)
        end
      end

      private

      def output_json_error(error, metadata, suggestions)
        error_data = {
          status: 'error',
          error_class: error.is_a?(Exception) ? error.class.name : 'Error',
          error_message: error.is_a?(Exception) ? error.message : error.to_s
        }
        error_data[:suggestion] = suggestions.first if suggestions&.any?
        error_data.merge!(metadata) unless metadata.empty?
        puts JSON.generate(error_data)
      end

      def output_text_error(error, suggestions)
        message = error.is_a?(Exception) ? "#{error.class} - #{error.message}" : error.to_s
        message += ". Did you mean? #{suggestions.join(', ')}" if suggestions&.any?
        say message, :red
      end

      # Get "Did you mean?" suggestions based on metadata
      def get_suggestions(metadata)
        return nil unless metadata

        candidates = nil
        typo = nil

        if metadata[:tool]
          typo = metadata[:tool].to_s
          candidates = ADK::GlobalToolManager.registered_tool_names
        elsif metadata[:agent]
          typo = metadata[:agent].to_s
          candidates = safe_get_agent_names
        end

        return nil unless candidates && typo

        checker = DidYouMean::SpellChecker.new(dictionary: candidates)
        checker.correct(typo)
      end

      def safe_get_agent_names
        # Safety check to avoid crashing if ADK not fully configured or Redis down
        return nil unless defined?(ADK) && ADK.respond_to?(:config)

        begin
          store = ADK.config.definition_store
          return nil unless store

          definitions = store.list_definitions
          definitions&.map { |d| d[:name] }
        rescue StandardError => _e
          # Silently ignore errors during suggestion generation (e.g. Redis down)
          nil
        end
      end

      # Check if quiet mode is enabled (--quiet or --json)
      # Thor options may use string or symbol keys depending on how they're accessed
      def quiet_mode?
        options['quiet'] || options[:quiet] || options['json'] || options[:json]
      end

      # Check if JSON output mode is enabled
      def json_mode?
        options['json'] || options[:json]
      end

      # Output data as JSON
      def output_json(data, metadata)
        result = normalize_for_json(data)
        output = metadata.empty? ? result : metadata.merge(result: result)
        puts JSON.generate(output)
      end

      # Normalize various data types to JSON-serializable format
      def normalize_for_json(data)
        case data
        when ADK::Event
          normalize_event(data)
        when Hash
          normalize_hash(data)
        when Array
          data.map { |item| normalize_for_json(item) }
        else
          data
        end
      end

      def normalize_event(event)
        {
          role: event.role.to_s,
          content: normalize_for_json(event.content),
          tool_name: event.tool_name&.to_s,
          timestamp: event.timestamp
        }.compact
      end

      def normalize_hash(hash)
        hash.transform_keys(&:to_s).transform_values do |v|
          case v
          when Symbol then v.to_s
          when Hash then normalize_hash(v)
          when Array then v.map { |item| normalize_for_json(item) }
          else v
          end
        end
      end
    end
  end
end
