# File: spec/adk/tools/echo_spec.rb
require 'spec_helper' # Loads 'adk'

RSpec.describe ADK::Tools::Echo do
  let(:tool_class) { described_class }
  let(:metadata) { tool_class.tool_metadata }

  # Test Class Metadata directly
  describe 'Class Metadata' do
    it 'has the correct inferred name' do
      expect(metadata[:name]).to eq(:echo)
    end

    it 'has the correct description' do
      expect(metadata[:description]).to eq('Echoes back the provided message.')
    end

    it 'defines the message parameter correctly' do
      expect(metadata[:parameters].keys).to eq([:message])
      param = metadata[:parameters][:message]
      expect(param[:type]).to eq(:string)
      expect(param[:required]).to eq(true)
      expect(param[:description]).to eq('The message to echo')
    end
  end

  describe '#execute' do
    subject(:tool) { tool_class.new } # Create instance for execution tests

    context 'with valid parameters' do
      let(:params) { { message: 'Hello test' } } # Use symbol keys as Agent uses them

      it 'returns a success hash with the original message' do
        result = tool.execute(params)
        expect(result).to eq({ status: :success, result: 'Hello test' })
      end
    end

    # Parameter validation happens in the base Tool class execute/validate_params
    # We test that the base class validation is triggered correctly.
    context 'with missing required parameters' do
      let(:params) { {} }

      # Updated to expect ADK::ToolArgumentError
      it 'raises an ADK::ToolArgumentError' do
        expect { tool.execute(params) }.to raise_error(ADK::ToolArgumentError, /Missing required parameters: message/)
      end
    end

    context 'with parameters as strings (less common case)' do
      let(:params) { { 'message' => 'Hello string key' } }

      it 'returns a success hash' do
        # This depends on perform_execution using fetch correctly
        result = tool.execute(params)
        expect(result).to eq({ status: :success, result: 'Hello string key' })
      end
    end

    # --- Test perform_execution specific error handling ---
    context 'when message is unexpectedly nil in perform_execution (post-validation)' do
      let(:params) { { message: 'Exists' } } # Start with valid params

      it 'logs an error and raises a ToolError' do
        # Stub fetch to simulate the parameter disappearing after validation
        allow(params).to receive(:fetch).with('message').and_return(nil)
        allow(params).to receive(:fetch).with(:message, nil).and_return(nil)

        allow(ADK.logger).to receive(:error) # Prevent logging noise

        expect { tool.execute(params) }
          .to raise_error(ADK::ToolError, /Internal Error: Message parameter missing/)

        expect(ADK.logger).to have_received(:error).with(/Internal Error: Message parameter missing/).at_least(:once)
      end
    end

    context 'when an unexpected error occurs during fetch' do
      let(:params) { { message: 'Exists' } } # Start with valid params
      let(:fetch_error) { StandardError.new('Something broke!') }

      it 'logs the error and raises a ToolError' do
        # Stub fetch to raise an unexpected error
        allow(params).to receive(:fetch).with('message').and_raise(fetch_error)
        allow(params).to receive(:fetch).with(:message, nil).and_raise(fetch_error)

        allow(ADK.logger).to receive(:error) # Prevent logging noise

        expect { tool.execute(params) }
          .to raise_error(ADK::ToolError, /Unexpected error in Echo tool: Something broke!/)

        expect(ADK.logger).to have_received(:error).with("Echo Tool: Unexpected error: StandardError - Something broke!")
      end
    end
    # --- End perform_execution specific error handling ---
  end
end
