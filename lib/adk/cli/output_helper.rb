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
        if json_mode?
          error_data = {
            status: 'error',
            error_class: error.is_a?(Exception) ? error.class.name : 'Error',
            error_message: error.is_a?(Exception) ? error.message : error.to_s
          }
          error_data.merge!(metadata) unless metadata.empty?
          puts JSON.generate(error_data)
        else
          message = error.is_a?(Exception) ? "#{error.class} - #{error.message}" : error.to_s

          suggestion = nil
          if metadata[:agent]
            typo = metadata[:agent].to_s
            candidates = ADK::AgentDefinitionStore.all.keys.map(&:to_s) | ADK::AgentDefinitionStore.list_all_names
            suggestion = DidYouMean::SpellChecker.new(dictionary: candidates).correct(typo).first
          elsif metadata[:tool]
            typo = metadata[:tool].to_s
            candidates = ADK::GlobalToolManager.registered_tool_names.map(&:to_s)
            suggestion = DidYouMean::SpellChecker.new(dictionary: candidates).correct(typo).first
          end

          message += "\nDid you mean '#{suggestion}'?" if suggestion
          say message, :red
        end
      end

      private

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
