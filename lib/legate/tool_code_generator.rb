# File: lib/legate/tool_code_generator.rb
# frozen_string_literal: true

module Legate
  # Generates Ruby source code from tool metadata.
  # Used to create downloadable .rb files for native tools from the web UI.
  module ToolCodeGenerator
    # Generate Ruby code from a tool's metadata.
    # @param tool_name [Symbol, String] The tool name registered with GlobalToolManager.
    # @return [String, nil] Valid Ruby source code or nil if tool not found.
    def self.generate(tool_name)
      tool_name_sym = tool_name.to_sym
      tool_class = Legate::GlobalToolManager.find_class(tool_name_sym)
      return nil unless tool_class

      metadata = tool_class.tool_metadata
      return nil unless metadata

      name = metadata[:name] || tool_name_sym
      description = metadata[:description] || 'No description provided'
      parameters = metadata[:parameters] || {}

      # Generate class name from tool name (snake_case to PascalCase)
      class_name = name.to_s.split('_').map(&:capitalize).join

      code = <<~RUBY
        # frozen_string_literal: true

        # Tool: #{name}
        # Generated from Legate Web UI on #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}

        require 'legate/tool'

        module Legate
          module Tools
            class #{class_name} < Tool
              tool_description #{ruby_string(description)}

      RUBY

      # Add parameter declarations
      parameters.each do |param_name, param_opts|
        code += generate_parameter(param_name, param_opts)
      end

      code += <<~RUBY

        private

        # @param params [Hash] The validated input parameters.
        # @param context [Legate::ToolContext] The execution context.
        # @return [Hash] Result with :status and :result or :error_message.
        def perform_execution(params, context)
          # TODO: Implement your tool logic here
          #
          # Available context methods:
          #   context.state_get(:key)  - Read from session state
          #   context.state_set(:key, value) - Write to session state
          #   context.session_id - Current session ID
          #
      RUBY

      # Add parameter access examples
      parameters.each do |param_name, _param_opts|
        code += "            # #{param_name} = params[:#{param_name}]\n"
      end

      code += <<~RUBY

                # Return success result
                { status: :success, result: 'Tool executed successfully' }

              rescue StandardError => e
                { status: :error, error_message: e.message }
              end
            end
          end
        end

        # Register the tool so agents can use it
        Legate::GlobalToolManager.register_tool(Legate::Tools::#{class_name})
      RUBY

      code
    end

    private_class_method def self.generate_parameter(param_name, param_opts)
      type = param_opts[:type] || :string
      description = param_opts[:description] || ''
      required = param_opts[:required] || false

      code = "          parameter :#{param_name},\n"
      code += "                    type: :#{type},\n"
      code += "                    description: #{ruby_string(description)},\n"
      code += "                    required: #{required}\n\n"
      code
    end

    private_class_method def self.ruby_string(value)
      value.to_s.inspect
    end
  end
end
