# File: spec/adk/tools/cat_facts_spec.rb
require 'spec_helper'
# Webmock is no longer strictly needed here as we stub the HttpClient methods,
# but keep it for now in case of future changes or direct Faraday usage elsewhere.
require 'webmock/rspec'

RSpec.describe ADK::Tools::CatFacts do
  let(:tool_class) { described_class }
  let(:metadata) { tool_class.tool_metadata }
  # Base URL is now used
  let(:base_api_url) { ADK::Tools::CatFacts::CAT_FACT_BASE_URL }
  let(:api_path) { '/fact' }

  # Test Class Metadata directly
  describe 'Class Metadata' do
    it 'has the correct inferred name' do
      expect(metadata[:name]).to eq(:cat_facts)
    end

    it 'has the correct description' do
      expect(metadata[:description]).to eq('Fetches a random cat fact from an online API.')
    end

    it 'has no parameters defined' do
      expect(metadata[:parameters]).to be_empty
    end
  end

  describe '#execute' do
    subject(:tool) { tool_class.new } # Create instance for execution tests
    let(:params) { {} } # No params needed
    let(:mock_response) { instance_double(Faraday::Response, body: '', status: 200) } # Mock response for stubs

    # Prevent actual HTTP client setup during tests
    before do
      allow(tool).to receive(:setup_http_client) # Stub the setup method
    end

    context 'when API call is successful' do
      let(:parsed_body) { { "fact" => "Cats sleep 16 hours a day.", "length" => 27 } }

      before do
        # Stub the HttpClient methods used by the tool
        allow(tool).to receive(:http_get).with(api_path).and_return(mock_response)
        allow(tool).to receive(:parse_json_response).with(mock_response).and_return(parsed_body)
      end

      it 'returns a success hash with the cat fact' do
        result = tool.execute(params)
        expect(result[:status]).to eq(:success)
        expect(result[:result]).to eq("Cats sleep 16 hours a day.")
      end
    end

    context 'when API response body is missing the fact field' do
      let(:parsed_body) { { "length" => 27 } } # Missing 'fact'

      before do
        allow(tool).to receive(:http_get).with(api_path).and_return(mock_response)
        allow(tool).to receive(:parse_json_response).with(mock_response).and_return(parsed_body)
      end

      it 'raises ToolError' do
        expect {
          tool.execute(params)
        }.to raise_error(ADK::ToolError, /did not contain a valid 'fact' field/i)
      end
    end

    context 'when API call returns an error status (e.g., 500)' do
      let(:error_message) { "HTTP error during GET request to #{api_path} (Status: 500): Some Server Error" }
      before do
        # Stub http_get to raise the error directly, simulating HttpClient behavior
        allow(tool).to receive(:http_get).with(api_path).and_raise(ADK::ToolError.new(error_message))
      end

      it 'raises ToolError (propagated from HttpClient)' do
        expect {
          tool.execute(params)
        }.to raise_error(ADK::ToolError, /HTTP error during GET request.*Status: 500/i)
      end
    end

    context 'when API call times out' do
      let(:error_message) { "Connection failed during GET request to #{api_path}: execution expired" }
      before do
        # Stub http_get to raise the error directly, simulating HttpClient behavior
        allow(tool).to receive(:http_get).with(api_path).and_raise(ADK::ToolError.new(error_message))
      end

      it 'raises ToolError (propagated from HttpClient)' do
        expect {
          tool.execute(params)
        }.to raise_error(ADK::ToolError, /Connection failed during GET request.*execution expired/i)
      end
    end

    context 'when API connection fails' do
      let(:error_message) { "Connection failed during GET request to #{api_path}: Connection refused" }
      before do
        # Stub http_get to raise the error directly, simulating HttpClient behavior
        allow(tool).to receive(:http_get).with(api_path).and_raise(ADK::ToolError.new(error_message))
      end

      it 'raises ToolError (propagated from HttpClient)' do
        expect {
          tool.execute(params)
        }.to raise_error(ADK::ToolError, /Connection failed during GET request.*Connection refused/i)
      end
    end

    context 'when API response is invalid JSON' do
      let(:error_message) { "Error parsing JSON response: invalid token" }
      before do
        # Stub http_get to return a response, but parse_json_response to fail
        allow(tool).to receive(:http_get).with(api_path).and_return(mock_response)
        allow(tool).to receive(:parse_json_response).with(mock_response).and_raise(ADK::ToolError.new(error_message))
      end

      it 'raises ToolError (propagated from HttpClient)' do
        expect {
          tool.execute(params)
        }.to raise_error(ADK::ToolError, /Error parsing JSON response/i)
      end
    end
  end
end
