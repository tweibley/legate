# frozen_string_literal: true

require 'spec_helper'
require 'adk/agent'

RSpec.describe ADK::AgentDefinition do
  subject(:definition) { described_class.new }

  # Define the proc outside let for access within instance_eval
  minimal_valid_block_proc = proc do |a|
    a.name :test_agent
    a.instruction 'Do something.'
  end

  # Define test procs here as well
  transformer_proc_test = ->(body) { body }
  extractor_proc_test = ->(body) { body['id'] }

  describe '#initialize' do
    it 'defaults webhook_enabled to false' do
      expect(definition.webhook_enabled).to be false
    end

    it 'defaults webhook_validator to nil' do
      expect(definition.webhook_validator).to be_nil
    end

    it 'defaults webhook_secret to nil' do
      expect(definition.webhook_secret).to be_nil
    end

    it 'defaults webhook_transformer to nil' do
      expect(definition.webhook_transformer).to be_nil
    end

    it 'defaults webhook_session_extractor to nil' do
      expect(definition.webhook_session_extractor).to be_nil
    end
  end

  describe 'DSL methods (via #define)' do
    it 'allows setting webhook_enabled' do
      # Access the proc directly
      definition.define do |a|
        minimal_valid_block_proc.call(a)
        a.webhook_enabled true
      end
      expect(definition.webhook_enabled).to be true
    end

    it 'allows setting webhook_validator to a Symbol' do
      definition.define do |a|
        minimal_valid_block_proc.call(a)
        a.webhook_validator :hmac_sha256
      end
      expect(definition.webhook_validator).to eq(:hmac_sha256)
    end

    it 'allows setting webhook_validator to a Proc' do
      validator_proc = -> { true }
      definition.define do |a|
        minimal_valid_block_proc.call(a)
        a.webhook_validator validator_proc
      end
      expect(definition.webhook_validator).to eq(validator_proc)
    end

    it 'raises ArgumentError if webhook_validator is not Symbol, a Proc, or nil' do
      expect do
        definition.define do |a|
          minimal_valid_block_proc.call(a) # Call the proc correctly
          a.webhook_validator 'invalid'
        end
      end.to raise_error(ArgumentError, 'webhook_validator must be a Symbol, a Proc, or nil.')
    end

    it 'allows setting webhook_secret' do
      definition.define do |a|
        minimal_valid_block_proc.call(a)
        a.webhook_secret 'my-super-secret'
      end
      expect(definition.webhook_secret).to eq('my-super-secret')
    end

    it 'allows setting webhook_transformer' do
      transformer_proc = -> { Hash.new }
      definition.define do |a|
        minimal_valid_block_proc.call(a)
        a.webhook_transformer transformer_proc
      end
      expect(definition.webhook_transformer).to eq(transformer_proc)
    end

    it 'raises ArgumentError if webhook_transformer is not a Proc or nil' do
      expect do
        definition.define do |a|
          minimal_valid_block_proc.call(a) # Call the proc correctly
          a.webhook_transformer :not_a_proc
        end
      end.to raise_error(ArgumentError, 'webhook_transformer must be a Proc or nil.')
    end

    it 'allows setting webhook_session_extractor' do
      extractor_proc = -> { 'session_123' }
      definition.define do |a|
        minimal_valid_block_proc.call(a)
        a.webhook_session_extractor extractor_proc
      end
      expect(definition.webhook_session_extractor).to eq(extractor_proc)
    end

    it 'raises ArgumentError if webhook_session_extractor is not a Proc or nil' do
      expect do
        definition.define do |a|
          minimal_valid_block_proc.call(a) # Call the proc correctly
          a.webhook_session_extractor 'not_a_proc_either'
        end
      end.to raise_error(ArgumentError, 'webhook_session_extractor must be a Proc or nil.')
    end
  end

  describe '#validate!' do
    it 'passes for a minimal valid definition' do
      expect { definition.define(&minimal_valid_block_proc) }.not_to raise_error
    end

    context 'when webhook_enabled is true' do
      # Use the procs defined outside let

      it 'passes if transformer and extractor are Procs' do
        expect do
          definition.define do |a|
            minimal_valid_block_proc.call(a)
            a.webhook_enabled true
            a.webhook_transformer transformer_proc_test
            a.webhook_session_extractor extractor_proc_test
          end
        end.not_to raise_error
      end

      it 'logs a warning if webhook_transformer is not a Proc' do
        expect(ADK.logger).to receive(:warn) { |&block|
          expect(block.call).to match(/lacks a valid :webhook_transformer Proc/)
        }
        definition.define do |a|
          minimal_valid_block_proc.call(a)
          a.webhook_enabled true
          # a.webhook_transformer transformer_proc_test # Missing
          a.webhook_session_extractor extractor_proc_test
        end
      end

      it 'logs a warning if webhook_session_extractor is not a Proc' do
        expect(ADK.logger).to receive(:warn) { |&block|
          expect(block.call).to match(/lacks a valid :webhook_session_extractor Proc/)
        }
        definition.define do |a|
          minimal_valid_block_proc.call(a)
          a.webhook_enabled true
          a.webhook_transformer transformer_proc_test
          # a.webhook_session_extractor extractor_proc_test # Missing
        end
      end

      it 'logs two warnings if both transformer and extractor are missing' do
        # Expect warn to be called with a block, matching the implementation
        expect(ADK.logger).to receive(:warn) { |&block|
          expect(block.call).to match(/lacks a valid :webhook_transformer Proc/)
        }.ordered
        expect(ADK.logger).to receive(:warn) { |&block|
          expect(block.call).to match(/lacks a valid :webhook_session_extractor Proc/)
        }.ordered
        definition.define do |a|
          minimal_valid_block_proc.call(a)
          a.webhook_enabled true
        end
      end
    end
  end

  describe '#to_h' do
    # Use the procs defined outside let

    before do
      definition.define do |a|
        minimal_valid_block_proc.call(a)
        a.description 'Test Desc'
        a.use_tool :calculator
        a.model_name 'gpt-test'
        a.temperature 0.5
        a.webhook_enabled true
        a.webhook_validator :hmac
        a.webhook_secret 'secret'
        a.webhook_transformer transformer_proc_test
        a.webhook_session_extractor extractor_proc_test
      end
    end

    it 'includes basic fields' do
      expect(definition.to_h).to include(
        name: :test_agent,
        description: 'Test Desc',
        instruction: 'Do something.',
        tool_names: [:calculator],
        model_name: :'gpt-test',
        temperature: 0.5
      )
    end

    it 'includes webhook_enabled field' do
      expect(definition.to_h[:webhook_enabled]).to be true
    end

    it 'includes webhook_validator field' do
      expect(definition.to_h[:webhook_validator]).to eq(:hmac)
    end

    it 'represents webhook_secret as <present>' do
      expect(definition.to_h[:webhook_secret]).to eq('<present>')
    end

    it 'represents webhook_transformer as <Proc>' do
      expect(definition.to_h[:webhook_transformer]).to eq('<Proc>')
    end

    it 'represents webhook_session_extractor as <Proc>' do
      expect(definition.to_h[:webhook_session_extractor]).to eq('<Proc>')
    end

    it 'shows nil for webhook_secret if not set' do
      local_definition = ADK::AgentDefinition.new
      local_definition.define do |a|
        minimal_valid_block_proc.call(a)
        # No webhook_secret defined here
      end
      expect(local_definition.to_h[:webhook_secret]).to be_nil
    end
  end

  describe '.from_hash and #to_h serialization/deserialization' do
    let(:original_definition) { described_class.new }
    let(:transformer_proc) { ->(data) { data } } # Dummy proc for testing assignment
    let(:extractor_proc) { ->(req) { req[:id] } }   # Dummy proc for testing assignment
    let(:validator_proc) { ->(req) { true } }    # Dummy proc for testing assignment

    # Use a shared context for defining a complex agent to reduce duplication
    shared_context 'with a complex original definition' do
      before do
        original_definition.define do |a|
          a.name :complex_agent
          a.description 'A complex agent with all bells and whistles'
          a.instruction 'Perform complex tasks meticulously.'
          a.use_tool :tool_one
          a.use_tool :tool_two
          a.model_name 'gemini-pro-max'
          a.temperature 0.88
          a.webhook_enabled true
          a.webhook_validator :my_custom_validator # Symbol validator
          a.webhook_secret 'super-secret-key-123'
          a.webhook_transformer transformer_proc
          a.webhook_session_extractor extractor_proc
          a.fallback_mode :echo
          a.mcp_servers({ type: 'stdio', command: 'mcp_server_exec' }, { type: 'sse', url: 'http://localhost:8080/sse' })
          a.sub_agents_define :sub_agent_alpha, :sub_agent_beta
        end
      end
    end

    let(:definition_hash) { original_definition.to_h }
    # Reconstruct immediately after to_h for round trip testing
    let(:reconstructed_definition) { described_class.from_hash(definition_hash) }

    context 'when all attributes are set' do
      include_context 'with a complex original definition'

      it 'reconstructs the name correctly' do
        expect(reconstructed_definition.name).to eq(:complex_agent)
      end

      it 'reconstructs the description correctly' do
        expect(reconstructed_definition.description).to eq('A complex agent with all bells and whistles')
      end

      it 'reconstructs the instruction correctly' do
        expect(reconstructed_definition.instruction).to eq('Perform complex tasks meticulously.')
      end

      it 'reconstructs the tool_names correctly' do
        expect(reconstructed_definition.tool_names).to match_array([:tool_one, :tool_two])
      end

      it 'reconstructs the model_name correctly' do
        expect(reconstructed_definition.model_name).to eq(:'gemini-pro-max')
      end

      it 'reconstructs the temperature correctly' do
        expect(reconstructed_definition.temperature).to eq(0.88)
      end

      it 'reconstructs webhook_enabled correctly' do
        expect(reconstructed_definition.webhook_enabled).to be true
      end

      it 'reconstructs webhook_validator (Symbol) correctly' do
        expect(reconstructed_definition.webhook_validator).to eq(:my_custom_validator)
      end

      it 'reconstructs webhook_secret as the string <present> (due to to_h behavior)' do
        # original_definition.webhook_secret is 'super-secret-key-123'
        # original_definition.to_h makes :webhook_secret '<present>'
        # ADK::AgentDefinition.from_hash receives '<present>' and sets it.
        expect(reconstructed_definition.webhook_secret).to eq('<present>')
      end

      it 'reconstructs webhook_transformer as nil (Procs are not serialized by to_h)' do
        # original_definition.webhook_transformer is a Proc
        # original_definition.to_h makes :webhook_transformer '<Proc>'
        # ADK::AgentDefinition.from_hash cannot reconstruct the Proc from this string.
        expect(reconstructed_definition.webhook_transformer).to be_nil
      end

      it 'reconstructs webhook_session_extractor as nil (Procs are not serialized by to_h)' do
        expect(reconstructed_definition.webhook_session_extractor).to be_nil
      end

      it 'reconstructs fallback_mode correctly' do
        expect(reconstructed_definition.fallback_mode).to eq(:echo)
      end

      it 'reconstructs mcp_servers correctly' do
        expected_mcp_servers = [
          { type: 'stdio', command: 'mcp_server_exec' },
          { type: 'sse', url: 'http://localhost:8080/sse' }
        ]
        # from_hash should convert symbol keys if they were strings in the hash
        # For mcp_servers, to_h provides them as an array of hashes with symbol keys already.
        # from_hash directly uses this array if it's an array.
        reconstructed_servers = reconstructed_definition.mcp_servers.map { |s| s.transform_keys(&:to_sym) }
        expect(reconstructed_servers).to eq(expected_mcp_servers)
      end

      it 'reconstructs sub_agent_names correctly' do
        expect(reconstructed_definition.sub_agent_names).to match_array([:sub_agent_alpha, :sub_agent_beta])
      end
    end

    context 'when webhook_validator is a Proc in original definition' do
      before do
        original_definition.define do |a|
          a.name :proc_validator_agent
          a.instruction 'Validates with a proc'
          a.webhook_validator validator_proc # Assign the actual Proc object
        end
      end

      # This re-uses the `definition_hash` and `reconstructed_definition` which are based on the new `original_definition`
      let(:definition_hash_for_proc_validator) { original_definition.to_h } # Recalculate based on this context's original_definition
      let(:reconstructed_definition_for_proc_validator) { described_class.from_hash(definition_hash_for_proc_validator) }

      it 'reconstructs webhook_validator as nil (Procs are not serialized by to_h)' do
        # original_definition.webhook_validator is a Proc
        # original_definition.to_h makes :webhook_validator '<Proc>'
        # ADK::AgentDefinition.from_hash cannot reconstruct the Proc from this string.
        expect(reconstructed_definition_for_proc_validator.webhook_validator).to be_nil
      end
    end

    context 'when mcp_servers is a JSON string in the input hash to from_hash' do
      include_context 'with a complex original definition' # To have an original_definition with mcp_servers

      let(:hash_with_json_mcp) do
        # Get the hash from the original definition
        temp_hash = original_definition.to_h.dup
        # Convert its mcp_servers (which is an array of hashes) to a JSON string
        temp_hash[:mcp_servers] = original_definition.mcp_servers.to_json
        temp_hash
      end
      let(:reconstructed_from_json_mcp) { described_class.from_hash(hash_with_json_mcp) }

      it 'reconstructs mcp_servers correctly from JSON string' do
        expected_mcp_servers = [
          { type: 'stdio', command: 'mcp_server_exec' },
          { type: 'sse', url: 'http://localhost:8080/sse' }
        ]
        # from_hash parses the JSON string and should produce symbol-keyed hashes
        reconstructed_servers = reconstructed_from_json_mcp.mcp_servers.map { |s| s.transform_keys(&:to_sym) }
        expect(reconstructed_servers).to eq(expected_mcp_servers)
      end
    end

    context 'when optional fields are not set in the original definition' do
      before do
        original_definition.define do |a|
          a.name :minimal_agent
          a.instruction 'Minimal instruction'
          # No other fields set
        end
      end

      # This re-uses the `definition_hash` and `reconstructed_definition`
      let(:minimal_definition_hash) { original_definition.to_h }
      let(:reconstructed_minimal_definition) { described_class.from_hash(minimal_definition_hash) }

      it 'reconstructs with defaults or nil for optional fields' do
        expect(reconstructed_minimal_definition.description).to eq('') # Default from DefinitionProxy
        expect(reconstructed_minimal_definition.tool_names).to be_empty
        expect(reconstructed_minimal_definition.model_name).to be_nil
        expect(reconstructed_minimal_definition.temperature).to be_nil
        expect(reconstructed_minimal_definition.webhook_enabled).to be false
        expect(reconstructed_minimal_definition.webhook_validator).to be_nil
        expect(reconstructed_minimal_definition.webhook_secret).to be_nil
        expect(reconstructed_minimal_definition.webhook_transformer).to be_nil
        expect(reconstructed_minimal_definition.webhook_session_extractor).to be_nil
        expect(reconstructed_minimal_definition.fallback_mode).to eq(:error) # Default
        expect(reconstructed_minimal_definition.mcp_servers).to eq([]) # Default
        expect(reconstructed_minimal_definition.sub_agent_names).to be_empty
      end
    end
  end
end
