# File: lib/adk/cli/tool_commands.rb
# frozen_string_literal: true

require_relative '../tool_registry'

module ADK
  module CLI
    # CLI commands for tool management using ToolRegistry
    class ToolCommands < Thor
      desc 'list', 'List available tools'
      def list
        tools = ADK::ToolRegistry.list_tools
        if tools.empty?
          puts "No tools registered."
        else
          puts "Available tools:"
          tools.each do |tool_info|
            puts "  - #{tool_info[:name]}: #{tool_info[:description]}"
          end
        end
      end

      desc 'info NAME', 'Show information about a tool'
      def info(name)
        tool_name_sym = name.to_sym
        tool = ADK::ToolRegistry.create_instance(tool_name_sym)

        if tool
          puts "Tool: #{tool.name}"
          puts "Description: #{tool.description}"
          if tool.parameters.empty?
            puts "\nParameters: None"
          else
            puts "\nParameters:"
            tool.parameters.each do |param_name, param_info|
              required = param_info[:required] ? 'required' : 'optional'
              type = param_info[:type] || 'any' # Default type if not specified
              puts "  - #{param_name} (#{type}, #{required})"
              puts "    #{param_info[:description]}"
            end
          end
        else
          puts "Tool not found: #{name}"
        end
      end

      desc 'execute NAME ...ARGS', 'Execute a tool directly'
      def execute(name, *args)
        tool_name_sym = name.to_sym
        tool = ADK::ToolRegistry.create_instance(tool_name_sym)

        unless tool
          puts "Tool not found: #{name}"
          return
        end

        # Basic parsing: Assume single required param or simple string join
        # TODO: Improve argument parsing based on tool.parameters definition
        params_to_execute = {}
        if tool.parameters.keys.length == 1
          # Assuming the first (and only) parameter takes the joined args
          param_key = tool.parameters.keys.first.to_s # Use string key for validation
          params_to_execute[param_key] = args.join(' ')
        else
          # Default for tools with no params or multiple (unhandled by CLI yet)
          # This might fail validation if params are required.
          # A more robust CLI would parse args into a hash based on tool params.
          # For echo specifically:
          params_to_execute['message'] = args.join(' ') if tool.name == :echo
        end

        begin
          puts "Executing tool '#{name}' with params: #{params_to_execute.inspect}"
          result = tool.execute(params_to_execute) # Pass string keys
          puts "Result: #{result}"
        rescue ADK::Error, ArgumentError => e
          puts "Error: #{e.message}"
        rescue StandardError => e
          puts "An unexpected error occurred: #{e.class} - #{e.message}"
          puts e.backtrace.first # Show where the error occurred
        end
      end
    end
  end
end
