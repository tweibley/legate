# File: spec/legate/tools/cat_facts_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'legate/tools/cat_facts'
require 'legate/errors'
require 'excon' # Required for Excon::Response mock

RSpec.describe Legate::Tools::CatFacts do
  let(:tool_class) { described_class }
  let(:metadata) { tool_class.tool_metadata }
  let(:base_api_url) { Legate::Tools::CatFacts::CAT_FACT_BASE_URL }
  let(:api_path) { '/fact' }

  # --- Metadata Tests ---
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

  # --- Execution Tests ---
  describe '#execute' do
    subject(:tool) { tool_class.new }
    let(:params) { {} }
    # Mock Excon::Response for use in stubs
    let(:mock_response) {
      Excon::Response.new(body: '', status: 200, headers: { 'Content-Type' => 'application/json' })
    }

    # Stub setup_http_client for all execution tests to prevent real initialization
    before do
      allow(tool).to receive(:setup_http_client)
    end

    context 'when API call is successful' do
      let(:fact_text) { 'Cats use their whiskers to determine if a space is too small to fit through.' }
      let(:json_body) { JSON.generate({ 'fact' => fact_text, 'length' => fact_text.length }) }

      before do
        # Stub http_get to return a new Excon::Response with the desired body
        allow(tool).to receive(:http_get).with(api_path).and_return(Excon::Response.new(body: json_body, status: 200,
                                                                                        headers: { 'Content-Type' => 'application/json' }))
      end

      it 'returns a success hash with the cat fact' do
        result = tool.execute(params)
        expect(result[:status]).to eq(:success)
        expect(result[:result]).to eq(fact_text)
      end
    end

    context 'when API response body is missing the fact field' do
      let(:json_body) { JSON.generate({ 'length' => 27 }) } # Missing 'fact'

      before do
        allow(tool).to receive(:http_get).with(api_path).and_return(Excon::Response.new(body: json_body, status: 200,
                                                                                        headers: { 'Content-Type' => 'application/json' }))
      end

      it 'raises ToolError' do
        expect {
          tool.execute(params)
        }.to raise_error(Legate::ToolError, /did not contain a valid 'fact' field/i)
      end
    end

    context 'when API call returns an error status (e.g., 500)' do
      # Simulate the error HttpClient would raise
      # Create a more realistic response object for ToolHttpError
      let(:error_response) { Excon::Response.new(status: 500, body: 'Server Error') }
      let(:http_error) { Legate::ToolHttpError.new('HTTP Error 500', response: error_response) }

      before do
        allow(tool).to receive(:http_get).with(api_path).and_raise(http_error)
      end

      it 'raises ToolError (propagated from HttpClient)' do
        expect {
          tool.execute(params)
        }.to raise_error(Legate::ToolHttpError) # Expect the specific error type
      end
    end

    context 'when API call times out' do
      # Simulate the error HttpClient would raise
      let(:timeout_error) { Legate::ToolTimeoutError.new('Timeout') }
      before do
        allow(tool).to receive(:http_get).with(api_path).and_raise(timeout_error)
      end

      it 'raises ToolError (propagated from HttpClient)' do
        expect {
          tool.execute(params)
        }.to raise_error(Legate::ToolTimeoutError)
      end
    end

    context 'when API connection fails' do
      # Simulate the error HttpClient would raise
      let(:network_error) { Legate::ToolNetworkError.new('Connection failed') }
      before do
        allow(tool).to receive(:http_get).with(api_path).and_raise(network_error)
      end

      it 'raises ToolError (propagated from HttpClient)' do
        expect {
          tool.execute(params)
        }.to raise_error(Legate::ToolNetworkError)
      end
    end

    context 'when API response is invalid JSON' do
      let(:invalid_json_body) { 'this is not json' }
      before do
        # Stub http_get to return response with invalid body
        allow(tool).to receive(:http_get).with(api_path).and_return(Excon::Response.new(body: invalid_json_body, status: 200, headers: { 'Content-Type' => 'text/plain' })) # Adjust content type if relevant
      end

      it 'raises ToolError (from JSON.parse)' do
        # Tool's internal JSON.parse rescue block should raise this
        expect {
          tool.execute(params)
        }.to raise_error(Legate::ToolError, /Failed to parse JSON response/i)
      end
    end
  end
end
