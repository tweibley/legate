# File: lib/adk/cli/tool_commands.rb
# frozen_string_literal: true

require 'thor'
require_relative '../global_tool_manager' # Require the global manager
require_relative '../tool_context' # <--- ADDED require
require 'securerandom' # <-- ADDED require for dummy context

module ADK
  module CLI
    # CLI commands for tool management using ToolRegistry
    class ToolCommands < Thor
      include OutputHelper

      desc 'list', 'List available tools from the registry'
      def list
        tools = ADK::GlobalToolManager.list_all_tools
        if tools.empty?
          say 'No tools registered.'
        else
          say 'Available tools:', :bold
          tools.each do |tool_info|
            say "- #{tool_info[:name]}: #{tool_info[:description]}"
          end
        end
      end

      desc 'info NAME', 'Show information about a tool from the registry'
      def info(name)
        tool_name_sym = name.to_sym
        tool = ADK::GlobalToolManager.create_instance(tool_name_sym) # Create instance to get params

        if tool
          say "Tool: #{tool.name}"
          say "Description: #{tool.description}"
          if tool.parameters.empty?
            say "\nParameters: None"
          else
            say "\nParameters:"
            tool.parameters.each do |param_name, param_info|
              required = param_info[:required] ? 'required' : 'optional'
              type = param_info[:type] || 'any'
              say "  - #{param_name} (#{type}, #{required})"
              say "    #{param_info[:description]}"
            end
          end
        else
          say "Tool '#{name}' not found in registry.", :red
        end
      end

      desc 'execute NAME [param1=value1 param2=value2 ...]', 'Execute a tool directly using key=value arguments'
      long_desc <<-LONGDESC
      Executes a specified tool directly with key=value pair arguments.

      Example:
        adk tool execute calculator operand1=10 operand2=5 operation=add

      Arguments should be provided as `key=value`. If a value contains spaces,
      it might need quoting depending on your shell.

      If the tool execution results in a :pending status (e.g., for an async job),
      the job_id will be printed. Use the check_job_status tool
      in a subsequent call to get the final result.
      LONGDESC
      method_option :quiet, type: :boolean, default: false, aliases: '-q',
                            desc: 'Suppress status messages, only output result'
      method_option :json, type: :boolean, default: false,
                           desc: 'Output result in JSON format (implies --quiet)'
      def execute(name, *args)
        tool_name_sym = name.to_sym
        tool = ADK::GlobalToolManager.create_instance(tool_name_sym)

        unless tool
          output_error("Tool '#{name}' not found in registry.", metadata: { tool: name })
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
              status("Warning: Provided parameter '#{key}' is not defined for tool '#{name}'. Ignoring.", :yellow)
              next
            end

            params_to_execute[key.to_sym] = value # Store as symbol key
            status("  Parsed: #{key} = '#{value}'")
          elsif args.length == 1 && tool.parameters.length == 1 && tool.parameters.values.first[:required]
            # Simplified single arg handling
            single_key = tool.parameters.keys.first
            status("Info: Assuming single argument '#{arg}' maps to required parameter '#{single_key}'.", :cyan)
            params_to_execute[single_key] = arg
          elsif !args.empty?
            status("Warning: Argument '#{arg}' ignored. Please use 'key=value' format for parameters.", :yellow)
          end
        end

        begin
          status("Executing tool '#{name}' with parsed params: #{params_to_execute.inspect}")
          # --- Create a dummy context for direct tool execution ---
          dummy_context = ADK::ToolContext.new(session_id: "cli_direct_#{SecureRandom.hex(4)}", user_id: 'cli_user',
                                               app_name: 'cli_tool_exec')

          # --- Call execute with context ---
          result_hash = tool.execute(params_to_execute, dummy_context)

          status("\nResult:", :bold)
          output_result(result_hash, metadata: { tool: name }, format_method: :format_tool_result)
        rescue ADK::Error, ArgumentError => e
          output_error(e, metadata: { tool: name })
          exit(1)
        rescue StandardError => e
          output_error(e, metadata: { tool: name })
          puts e.backtrace.first(5).join("\n") unless json_mode?
          exit(1)
        end
      end # end execute

      no_commands do
        # Format tool result in human-readable format
        def format_tool_result(result_hash)
          if result_hash.is_a?(Hash) && result_hash.key?(:status)
            case result_hash[:status]
            when :success
              say 'Success:', :green
              say "  Output: #{result_hash[:result]}"
            when :pending
              say 'Pending:', :yellow
              say "  Job ID: #{result_hash[:job_id]}"
              say "  Message: #{result_hash[:message]}" if result_hash[:message]
            when :error
              say 'Error:', :red
              say "  Message: #{result_hash[:error_message]}"
            else
              say 'Unknown Status:', :yellow
              say "  Data: #{result_hash.inspect}"
            end
          else
            say 'Unknown Result Format:', :yellow
            say "  Data: #{result_hash.inspect}"
          end
        end
      end

      desc 'ai_generate', 'Generate tool class code using AI from a natural language description'
      long_desc <<-LONGDESC
        Uses AI (Gemini LLM) to generate a production-ready tool class based on
        your natural language description. The AI automatically determines if the
        tool should be a simple tool, HTTP API tool, or async tool.

        Input sources (in priority order):
          1. --description / -d : Inline description
          2. --prompt-file / -f : Read description from a file
          3. stdin : Pipe description via stdin (auto-enables stdout output)

        Output destinations:
          - Default: Writes to ./<suggested_name>.rb
          - --output / -o : Custom output file path
          - --stdout : Output to stdout instead of file
          - When reading from stdin: Auto-outputs to stdout

        Examples:
          adk tool ai_generate -d "A tool that converts temperatures between Celsius and Fahrenheit"
          adk tool ai_generate -d "A tool that checks if a URL is reachable" -o ./tools/url_checker.rb
          echo "A calculator that adds two numbers" | adk tool ai_generate
          echo "A weather API tool" | adk tool ai_generate > weather_tool.rb

        Requires GOOGLE_API_KEY environment variable to be set.
      LONGDESC
      method_option :description, aliases: '-d', type: :string, desc: 'Description of the tool to generate'
      method_option :prompt_file, aliases: '-f', type: :string, desc: 'Read description from a file'
      method_option :output, aliases: '-o', type: :string, desc: 'Output file path (default: ./<suggested_name>.rb)'
      method_option :stdout, type: :boolean, default: false, desc: 'Output to stdout instead of file'
      method_option :force, type: :boolean, default: false, desc: 'Overwrite existing file without prompting'
      def ai_generate
        require_relative '../generators'

        description = nil
        from_stdin = false

        # Priority: --description > --prompt-file > stdin
        if options[:description] && !options[:description].strip.empty?
          description = options[:description].strip
        elsif options[:prompt_file]
          unless File.exist?(options[:prompt_file])
            say "Error: Prompt file '#{options[:prompt_file]}' not found.", :red
            exit(1)
          end
          description = File.read(options[:prompt_file]).strip
        elsif !$stdin.tty?
          # Reading from stdin (piped input)
          description = $stdin.read.strip
          from_stdin = true
        end

        if description.nil? || description.empty?
          say 'Error: No description provided. Use --description, --prompt-file, or pipe via stdin.', :red
          exit(1)
        end

        # Determine output mode
        output_to_stdout = options[:stdout] || from_stdin

        say 'Generating tool code via AI...', :cyan unless output_to_stdout

        begin
          result = ADK::Generators::ToolGenerator.generate(description: description)
          code = result[:code]
          suggested_name = result[:suggested_name]
          tool_type = result[:tool_type]

          if output_to_stdout
            puts code
          else
            # Write to file
            file_path = options[:output] || "./#{suggested_name}.rb"

            if File.exist?(file_path) && !options[:force] && !yes?("File '#{file_path}' already exists. Overwrite? [y/N]", :yellow)
              say 'Generation cancelled.', :yellow
              exit(0)
            end

            File.write(file_path, code)
            say "Tool code generated and saved to '#{file_path}'", :green
            say "  Suggested name: #{suggested_name}", :cyan
            say "  Tool type: #{tool_type}", :cyan
          end
        rescue ADK::Generators::ToolGenerator::ApiKeyMissingError => e
          say "Error: #{e.message}", :red
          exit(1)
        rescue ADK::Generators::ToolGenerator::ApiError => e
          say "Error: #{e.message}", :red
          exit(1)
        rescue ADK::Generators::ToolGenerator::GenerationError => e
          say "Error: #{e.message}", :red
          exit(1)
        rescue StandardError => e
          say "Unexpected error: #{e.class} - #{e.message}", :red
          exit(1)
        end
      end
    end
  end
end
