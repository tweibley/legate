# frozen_string_literal: true

module ADK
  module CLI
    # CLI commands for tool management
    class ToolCommands < Thor
      desc 'list', 'List available tools'
      def list
        # In a real implementation, this would discover tools dynamically
        puts "Available tools:"
        puts "  - echo: Echoes back a message"
      end

      desc 'info NAME', 'Show information about a tool'
      def info(name)
        case name
        when 'echo'
          tool = ADK::Tools::Echo.new
          puts "Tool: #{tool.name}"
          puts "Description: #{tool.description}"
          puts "\nParameters:"
          tool.parameters.each do |param_name, param_info|
            required = param_info[:required] ? 'required' : 'optional'
            puts "  - #{param_name} (#{param_info[:type]}, #{required})"
            puts "    #{param_info[:description]}"
          end
        else
          puts "Tool not found: #{name}"
        end
      end

      desc 'execute NAME ...ARGS', 'Execute a tool directly'
      def execute(name, *args)
        case name
        when 'echo'
          tool = ADK::Tools::Echo.new
          result = tool.execute(message: args.join(' '))
          puts "Result: #{result}"
        else
          puts "Tool not found: #{name}"
        end
      end
    end
  end
end 