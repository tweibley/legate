# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ADK::Tool do
  # Define a dummy tool class for testing validation
  class ToolValidationTestTool < ADK::Tool
    tool_description 'A tool for testing validation UX'
    parameter :location, type: :string, required: true, description: 'Target location'

    def perform_execution(params, context)
      { status: :success, result: params[:location] }
    end
  end

  let(:tool) { ToolValidationTestTool.new }

  describe '#validate_and_coerce_params' do
    context 'when a required parameter is missing but a similar key is provided' do
      it 'raises an error with a "Did you mean?" suggestion' do
        expect {
          tool.execute(locatoin: 'San Francisco')
        }.to raise_error(ADK::ToolArgumentError) do |error|
          expect(error.message).to include("Missing required parameters for tool 'tool_validation_test_tool': location")
          expect(error.message).to include("Did you mean 'location' instead of 'locatoin'?")
        end
      end
    end

    context 'when a required parameter is missing and no similar key is provided' do
      it 'raises an error without a "Did you mean?" suggestion' do
        expect {
          tool.execute(completely_wrong: 'San Francisco')
        }.to raise_error(ADK::ToolArgumentError) do |error|
          expect(error.message).to include("Missing required parameters for tool 'tool_validation_test_tool': location")
          expect(error.message).not_to include("Did you mean")
        end
      end
    end
  end
end
