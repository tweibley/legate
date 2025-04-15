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

      desc 'execute NAME ...ARGS', 'Execute a tool directly using arguments'
      def execute(name, *args)
        tool_name_sym = name.to_sym
        tool = ADK::ToolRegistry.create_instance(tool_name_sym)

        unless tool
          say "Tool '#{name}' not found in registry.", :red
          return
        end

        # Basic argument parsing (same as before, needs improvement for complex tools)
        params_to_execute = {}
        string_keys_params = tool.parameters.transform_keys(&:to_s) # Get string keys for lookup

        if string_keys_params.keys.length == 1 && string_keys_params.values.first[:required]
          param_key = string_keys_params.keys.first
          params_to_execute[param_key] = args.join(' ')
          say "Attempting execution with single required param '#{param_key}' = '#{params_to_execute[param_key]}'"
        elsif args.empty? && !tool.parameters.any? { |_, p| p[:required] }
          say "Executing tool '#{name}' with no arguments (assuming no required parameters)."
        else
          # Very basic fallback - might fail validation
          # TODO: Implement proper mapping of ARGS based on tool.parameters
          say "Warning: Basic argument parsing used. Mapping all args to 'message' or first param if possible.", :yellow
          fallback_key = string_keys_params.key?('message') ? 'message' : string_keys_params.keys.first
          if fallback_key
            params_to_execute[fallback_key] = args.join(' ')
          else
            say "Error: Cannot determine how to map arguments to parameters for tool '#{name}'.", :red
            return
          end

        end

        begin
          say "Executing tool '#{name}' with params: #{params_to_execute.inspect}"
          result = tool.execute(params_to_execute) # Pass string keys
          puts "Result: #{result}"
        rescue ADK::Error, ArgumentError => e
          say "Error: #{e.message}", :red
        rescue StandardError => e
          say "An unexpected error occurred: #{e.class} - #{e.message}", :red
          puts e.backtrace.first # Show where the error occurred
        end
      end
    end
  end
end
