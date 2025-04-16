# File: spec/adk/tools/echo_spec.rb
require 'spec_helper' # Loads 'adk'

RSpec.describe ADK::Tools::Echo do
  subject(:tool) { described_class.new }

  describe '#initialize' do
    it 'sets the name correctly' do
      expect(tool.name).to eq(:echo)
    end

    it 'sets the description correctly' do
      expect(tool.description).to eq('Echoes back the provided message.')
    end

    it 'defines the message parameter' do
      expect(tool.parameters).to have_key(:message)
      expect(tool.parameters[:message][:type]).to eq(:string)
      expect(tool.parameters[:message][:required]).to eq(true)
    end
  end

  describe '#execute' do
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

      it 'raises an ADK::Error' do
        # Check for the specific error message from validate_params
        expect { tool.execute(params) }.to raise_error(ADK::Error, /Missing required parameters: message/)
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
  end
end
