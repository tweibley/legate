# File: spec/legate/agent_code_generator_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'legate/agent_code_generator'

RSpec.describe Legate::AgentCodeGenerator do
  describe '.generate' do
    context 'with a basic LLM agent' do
      let(:definition) do
        {
          name: :my_test_agent,
          description: 'A test agent',
          instruction: 'Be helpful and friendly.',
          model: 'gemini-2.0-flash',
          tools: %w[echo calculator],
          fallback_mode: :error,
          agent_type: :llm
        }
      end

      it 'generates valid Ruby code' do
        code = described_class.generate(definition)

        expect(code).to include("require 'legate'")
        expect(code).to include('Legate::AgentDefinition.new.define')
        expect(code).to include('a.name :my_test_agent')
        expect(code).to include('a.description "A test agent"')
        expect(code).to include('a.instruction "Be helpful and friendly."')
        expect(code).to include('a.model_name "gemini-2.0-flash"')
        expect(code).to include('a.use_tool :echo')
        expect(code).to include('a.use_tool :calculator')
        expect(code).to include('Legate::GlobalDefinitionRegistry.register(definition)')
      end

      it 'generates syntactically valid Ruby' do
        code = described_class.generate(definition)
        expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
      end

      it 'omits fallback_mode when set to :error (default)' do
        code = described_class.generate(definition)
        expect(code).not_to include('a.fallback_mode')
      end
    end

    context 'with echo fallback mode' do
      let(:definition) do
        {
          name: :echo_fallback_agent,
          description: 'An agent with echo fallback',
          fallback_mode: :echo
        }
      end

      it 'includes fallback_mode when not default' do
        code = described_class.generate(definition)
        expect(code).to include('a.fallback_mode :echo')
      end
    end

    context 'with multi-line instruction' do
      let(:definition) do
        {
          name: :multiline_agent,
          description: 'Agent with long instruction',
          instruction: "You are a helpful assistant.\n\nGuidelines:\n- Be polite\n- Be accurate"
        }
      end

      it 'uses heredoc for multi-line instructions' do
        code = described_class.generate(definition)
        expect(code).to include('<<~INSTRUCTION')
        expect(code).to include('You are a helpful assistant.')
        expect(code).to include('- Be polite')
      end

      it 'generates syntactically valid Ruby' do
        code = described_class.generate(definition)
        expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
      end
    end

    context 'with output_key' do
      let(:definition) do
        {
          name: :output_agent,
          description: 'Agent with output key',
          output_key: :result
        }
      end

      it 'includes output_key' do
        code = described_class.generate(definition)
        expect(code).to include('a.output_key :result')
      end
    end

    context 'with sequential agent type' do
      let(:definition) do
        {
          name: :seq_agent,
          description: 'Sequential workflow agent',
          agent_type: :sequential,
          sub_agent_names: %w[step_one step_two step_three]
        }
      end

      it 'includes agent_type and sub_agent_names' do
        code = described_class.generate(definition)
        expect(code).to include('a.agent_type :sequential')
        expect(code).to include('a.sequential_sub_agent_names [:step_one, :step_two, :step_three]')
      end

      it 'generates syntactically valid Ruby' do
        code = described_class.generate(definition)
        expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
      end
    end

    context 'with parallel agent type' do
      let(:definition) do
        {
          name: :par_agent,
          description: 'Parallel workflow agent',
          agent_type: :parallel,
          sub_agent_names: %w[worker_a worker_b]
        }
      end

      it 'includes agent_type and parallel sub_agent_names' do
        code = described_class.generate(definition)
        expect(code).to include('a.agent_type :parallel')
        expect(code).to include('a.parallel_sub_agent_names [:worker_a, :worker_b]')
      end
    end

    context 'with loop agent type' do
      let(:definition) do
        {
          name: :loop_agent,
          description: 'Loop workflow agent',
          agent_type: :loop,
          sub_agent_names: %w[process_step check_step],
          loop_max_iterations: 10,
          loop_condition_state_key: :is_complete,
          loop_condition_expected_value: 'true'
        }
      end

      it 'includes all loop configuration' do
        code = described_class.generate(definition)
        expect(code).to include('a.agent_type :loop')
        expect(code).to include('a.loop_sub_agent_names [:process_step, :check_step]')
        expect(code).to include('a.loop_max_iterations 10')
        expect(code).to include('a.loop_condition_state_key :is_complete')
        expect(code).to include('a.loop_condition_expected_value "true"')
      end

      it 'generates syntactically valid Ruby' do
        code = described_class.generate(definition)
        expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
      end
    end

    context 'with delegation targets (LLM agent)' do
      let(:definition) do
        {
          name: :delegating_agent,
          description: 'Agent that delegates',
          agent_type: :llm,
          delegation_targets: %w[helper_agent specialist_agent]
        }
      end

      it 'includes delegation_targets' do
        code = described_class.generate(definition)
        expect(code).to include('a.delegation_targets [:helper_agent, :specialist_agent]')
      end
    end

    context 'with MCP servers configured' do
      let(:definition) do
        {
          name: :mcp_agent,
          description: 'Agent with MCP servers',
          mcp_servers_json: '[{"name": "local-server", "transport": "stdio", "command": "python", "args": ["-m", "mcp_server"]}]'
        }
      end

      it 'includes MCP server configuration' do
        code = described_class.generate(definition)
        expect(code).to include('a.mcp_servers(')
        expect(code).to include('"name"')
        expect(code).to include('"local-server"')
      end

      it 'generates syntactically valid Ruby' do
        code = described_class.generate(definition)
        expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
      end
    end

    context 'with empty MCP servers' do
      let(:definition) do
        {
          name: :no_mcp_agent,
          description: 'Agent without MCP',
          mcp_servers_json: '[]'
        }
      end

      it 'does not include MCP configuration' do
        code = described_class.generate(definition)
        expect(code).not_to include('a.mcp_servers')
      end
    end

    context 'with no tools' do
      let(:definition) do
        {
          name: :toolless_agent,
          description: 'Agent with no tools',
          tools: []
        }
      end

      it 'generates valid code without tool declarations' do
        code = described_class.generate(definition)
        expect(code).not_to include('a.use_tool')
        expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
      end
    end

    context 'with special characters in name' do
      let(:definition) do
        {
          name: 'My Agent (v2)',
          description: 'Agent with special chars'
        }
      end

      it 'sanitizes the agent name for Ruby symbol' do
        code = described_class.generate(definition)
        expect(code).to include('a.name :My_Agent__v2_')
      end
    end

    context 'with escaped characters in strings' do
      let(:definition) do
        {
          name: :escape_test,
          description: 'Test with "quotes" and newline\ncharacters'
        }
      end

      it 'properly escapes string content' do
        code = described_class.generate(definition)
        expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
      end
    end

    context 'when model/instruction come through as Symbols (regression)' do
      let(:definition) do
        {
          name: :sym_agent, description: 'desc', model: :'gemini-3.5-flash',
          instruction: :'be brief', tools: [], agent_type: :llm
        }
      end

      it 'does not raise on a Symbol model/instruction and still emits the model' do
        code = nil
        expect { code = described_class.generate(definition) }.not_to raise_error
        expect(code).to include('a.model_name "gemini-3.5-flash"')
        expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
      end
    end
  end
end
