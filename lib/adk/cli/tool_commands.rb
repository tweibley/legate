# File: lib/adk/cli/tool_commands.rb
# frozen_string_literal: true

require 'thor'
require_relative '../tool_registry' # Require the registry

module ADK
  module CLI
    # CLI commands for tool management using ToolRegistry
    class ToolCommands < Thor
      desc 'list', 'List available tools from the registry'
      def list
        tools = ADK::ToolRegistry.list_tools
        if tools.empty?
          say "No tools registered."
        else
          say "Available tools:", :bold
          tools.each do |tool_info|
            say "- #{tool_info[:name]}: #{tool_info[:description]}"
          end
        end
      end

      desc 'info NAME', 'Show information about a tool from the registry'
      def info(name)
        tool_name_sym = name.to_sym
        tool = ADK::ToolRegistry.create_instance(tool_name_sym) # Create instance to get params

        if tool
          puts "Tool: #{tool.name}"
          puts "Description: #{tool.description}"
          if tool.parameters.empty?
            puts "\nParameters: None"
          else
            puts "\nParameters:"
            tool.parameters.each do |param_name, param_info|
              required = param_info[:required] ? 'required' : 'optional'
              type = param_info[:type] || 'any'
              puts "  - #{param_name} (#{type}, #{required})"
              puts "    #{param_info[:description]}"
            end
          end
        else
          say "Tool '#{name}' not found in registry.", :red
        end
      end

      desc 'execute NAME [param1=value1 param2=value2 ...]', 'Execute a tool directly using key=value arguments'
      long_desc <<-LONGDESC
        # ... (long description) ...
      LONGDESC
      def execute(name, *args)
        tool_name_sym = name.to_sym
        tool = ADK::ToolRegistry.create_instance(tool_name_sym)

        unless tool
          say "Error: Tool '#{name}' not found in registry.", :red
          exit(1)
        end

        params_to_execute = {}
        valid_param_names = tool.parameters.keys.map(&:to_s)

        args.each do |arg|
          parts = arg.split('=', 2)
          if parts.length == 2
            key = parts[0].strip
            value = parts[1]

            unless valid_param_names.include?(key)
              say "Warning: Provided parameter '#{key}' is not defined for tool '#{name}'. Ignoring.", :yellow
              next
            end

            params_to_execute[key] = value
            # --- REMOVED :faint ---
            say "  Parsed: #{key} = '#{value}'" # No color specified, uses default
          else
            # ... (rest of the argument parsing logic) ...
            if args.length == 1 && tool.parameters.length == 1 && tool.parameters.values.first[:required]
              single_key = valid_param_names.first
              say "Info: Assuming single argument '#{arg}' maps to required parameter '#{single_key}'.", :cyan
              params_to_execute[single_key] = arg
            elsif !args.empty?
              say "Warning: Argument '#{arg}' ignored. Please use 'key=value' format for parameters.", :yellow
            end
          end
        end

        begin
          say "Executing tool '#{name}' with parsed params: #{params_to_execute.inspect}"
          result_hash = tool.execute(params_to_execute)

          # ... (result printing logic - remains the same) ...
          say "\nResult:", :bold
          if result_hash.is_a?(Hash) && result_hash.key?(:status)
            if result_hash[:status] == :success
              say "Success:", :green
              say "  Output: #{result_hash[:result]}"
            else
              say "Error:", :red
              say "  Message: #{result_hash[:error_message]}"
            end
          else
            say "Unknown Result Format:", :yellow
            say "  Data: #{result_hash.inspect}"
          end
        rescue ADK::Error, ArgumentError => e
          say "\nError executing tool:", :red
          say e.message, :red
        rescue StandardError => e
          say "\nAn unexpected error occurred:", :red
          say "#{e.class} - #{e.message}", :red
        end
      end # end execute
    end
  end
end
