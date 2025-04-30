# File: spec/adk/tools/cat_facts_spec.rb
require 'spec_helper'
require 'webmock/rspec' # Ensure webmock is required

RSpec.describe ADK::Tools::CatFacts do
  let(:tool_class) { described_class }
  let(:metadata) { tool_class.tool_metadata }
  let(:api_url) { ADK::Tools::CatFacts::CAT_FACT_URL }

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

    context 'when API call is successful' do
      let(:api_response_body) { { fact: "Cats sleep 16 hours a day.", length: 27 }.to_json }

      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: api_response_body, headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns a success hash with the cat fact' do
        result = tool.execute(params)
        expect(result[:status]).to eq(:success)
        expect(result[:result]).to eq("Cats sleep 16 hours a day.")
      end
    end

    context 'when API response body is missing the fact field' do
      let(:api_response_body) { { length: 27 }.to_json } # Missing 'fact'

      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: api_response_body, headers: { 'Content-Type' => 'application/json' })
      end

      it 'raises ToolError' do
        expect {
          tool.execute(params)
        }.to raise_error(ADK::ToolError, /did not contain a valid 'fact' field/i)
      end
    end

    context 'when API call returns an error status (e.g., 500)' do
      before do
        stub_request(:get, api_url)
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'raises ToolError' do
        expect {
          tool.execute(params)
        }.to raise_error(ADK::ToolError, /Error fetching cat fact \(HTTP Status: 500\)/i)
      end
    end

    context 'when API call times out' do
      before do
        stub_request(:get, api_url).to_raise(Faraday::TimeoutError.new("execution expired"))
      end

      it 'raises ToolError' do
        expect {
          tool.execute(params)
        }.to raise_error(ADK::ToolError, /Timeout connecting/i)
      end
    end

    context 'when API connection fails' do
      before do
        stub_request(:get, api_url).to_raise(Faraday::ConnectionFailed.new("Connection refused"))
      end

      it 'raises ToolError' do
        expect {
          tool.execute(params)
        }.to raise_error(ADK::ToolError, /Connection failed/i)
      end
    end

    context 'when API response is invalid JSON' do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: 'This is not JSON', headers: { 'Content-Type' => 'text/plain' })
      end

      it 'raises ToolError' do
        expect {
          tool.execute(params)
        }.to raise_error(ADK::ToolError, /JSON parse failed/i)
      end
    end
  end
end
