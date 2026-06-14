# File: lib/legate/agent_code_generator.rb
# frozen_string_literal: true

module Legate
  # Generates Ruby source code from agent definition hashes.
  # Used to create downloadable .rb files from agents configured in the web UI.
  module AgentCodeGenerator
    # Generate Ruby code from an agent definition hash.
    # @param definition [Hash] Agent definition with keys like :name, :description, :instruction, etc.
    # @return [String] Valid Ruby source code for the agent definition.
    def self.generate(definition)
      name = definition[:name]
      description = definition[:description]
      instruction = definition[:instruction]
      model = definition[:model]
      tools = Array(definition[:tools])
      fallback_mode = definition[:fallback_mode]
      agent_type = definition[:agent_type]&.to_sym || :llm
      output_key = definition[:output_key]
      mcp_servers_json = definition[:mcp_servers_json]

      # Workflow-specific settings
      sub_agent_names = definition[:sub_agent_names] || []
      delegation_targets = definition[:delegation_targets] || []

      # Loop-specific settings
      loop_max_iterations = definition[:loop_max_iterations]
      loop_condition_state_key = definition[:loop_condition_state_key]
      loop_condition_expected_value = definition[:loop_condition_expected_value]

      code = <<~RUBY
        # frozen_string_literal: true

        # Agent: #{name}
        # Generated from Legate Web UI on #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}

        require 'legate'

        definition = Legate::AgentDefinition.new.define do |a|
          a.name #{ruby_symbol(name)}
          a.description #{ruby_string(description)}
      RUBY

      # Add instruction if present
      code += generate_instruction(instruction.to_s) if instruction && !instruction.to_s.strip.empty?

      # Add agent type if not default LLM
      code += "  a.agent_type #{ruby_symbol(agent_type)}\n" if agent_type && agent_type != :llm

      # Add model if specified (model may be a String or Symbol depending on source)
      code += "  a.model_name #{ruby_string(model)}\n" if model && !model.to_s.strip.empty?

      # Add temperature (use default if not specified)
      # code += "  a.temperature 0.7\n" # Uncomment if temperature should be included

      # Add fallback mode if specified and not default
      code += "  a.fallback_mode #{ruby_symbol(fallback_mode)}\n" if fallback_mode && fallback_mode.to_sym != :error

      # Add output_key if specified
      code += "  a.output_key #{ruby_symbol(output_key)}\n" if output_key && !output_key.to_s.strip.empty?

      # Add tools
      tools.each do |tool_name|
        code += "  a.use_tool #{ruby_symbol(tool_name)}\n"
      end

      # Add workflow-specific settings based on agent type
      case agent_type
      when :sequential
        code += "  a.sequential_sub_agent_names [#{sub_agent_names.map { |n| ruby_symbol(n) }.join(', ')}]\n" if sub_agent_names.any?
      when :parallel
        code += "  a.parallel_sub_agent_names [#{sub_agent_names.map { |n| ruby_symbol(n) }.join(', ')}]\n" if sub_agent_names.any?
      when :loop
        code += "  a.loop_sub_agent_names [#{sub_agent_names.map { |n| ruby_symbol(n) }.join(', ')}]\n" if sub_agent_names.any?
        code += "  a.loop_max_iterations #{loop_max_iterations.to_i}\n" if loop_max_iterations
        code += "  a.loop_condition_state_key #{ruby_symbol(loop_condition_state_key)}\n" if loop_condition_state_key && !loop_condition_state_key.to_s.strip.empty?
        code += "  a.loop_condition_expected_value #{ruby_string(loop_condition_expected_value)}\n" if loop_condition_expected_value && !loop_condition_expected_value.to_s.strip.empty?
      when :llm
        # For LLM agents, use delegation_targets if present
        code += "  a.delegation_targets [#{delegation_targets.map { |n| ruby_symbol(n) }.join(', ')}]\n" if delegation_targets.any?
      end

      # Add MCP servers if configured
      if mcp_servers_json && mcp_servers_json != '[]' && !mcp_servers_json.strip.empty?
        begin
          mcp_configs = JSON.parse(mcp_servers_json)
          code += generate_mcp_servers(mcp_configs) if mcp_configs.is_a?(Array) && mcp_configs.any?
        rescue JSON::ParserError
          # Skip if invalid JSON
        end
      end

      code += <<~RUBY
        end

        # Register the agent globally
        Legate::GlobalDefinitionRegistry.register(definition)

        # To use this agent programmatically:
        #
        # agent = Legate::Agent.new(definition: definition)
        # agent.start
        #
        # session_service = Legate::SessionService::InMemory.new
        # session = session_service.create_session(app_name: agent.name, user_id: 'user')
        #
        # result = agent.run_task(
        #   session_id: session.id,
        #   user_input: 'Your task here',
        #   session_service: session_service
        # )
        #
        # agent.stop
      RUBY

      code
    end

    private_class_method def self.generate_instruction(instruction)
      # Use heredoc for multi-line instructions
      if instruction.include?("\n") || instruction.length > 80
        # Escape any heredoc terminators in the instruction
        escaped_instruction = instruction.gsub('INSTRUCTION', 'INSTR_ESCAPED')
        <<~RUBY

            a.instruction <<~INSTRUCTION
          #{indent_text(escaped_instruction, '    ')}
            INSTRUCTION

        RUBY
      else
        "  a.instruction #{ruby_string(instruction)}\n"
      end
    end

    private_class_method def self.generate_mcp_servers(mcp_configs)
      code = "\n  # MCP Server Configuration\n"
      code += "  a.mcp_servers(\n"

      mcp_configs.each_with_index do |config, index|
        code += "    {\n"
        config.each do |key, value|
          code += "      #{ruby_string(key)} => #{ruby_value(value)}"
          code += ",\n"
        end
        code.chomp!(",\n")
        code += "\n    }"
        code += ',' if index < mcp_configs.size - 1
        code += "\n"
      end

      code += "  )\n"
      code
    end

    private_class_method def self.ruby_symbol(value)
      ":#{value.to_s.gsub(/[^a-zA-Z0-9_]/, '_')}"
    end

    private_class_method def self.ruby_string(value)
      value.to_s.inspect
    end

    private_class_method def self.ruby_value(value)
      case value
      when String
        value.inspect
      when Symbol
        ":#{value}"
      when Numeric, TrueClass, FalseClass, NilClass
        value.inspect
      when Array
        "[#{value.map { |v| ruby_value(v) }.join(', ')}]"
      when Hash
        "{ #{value.map { |k, v| "#{ruby_value(k)} => #{ruby_value(v)}" }.join(', ')} }"
      else
        value.to_s.inspect
      end
    end

    private_class_method def self.indent_text(text, indent)
      text.lines.map { |line| "#{indent}#{line.rstrip}" }.join("\n")
    end
  end
end
