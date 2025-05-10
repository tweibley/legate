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
end
