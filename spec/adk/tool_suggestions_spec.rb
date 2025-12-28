# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool'

RSpec.describe ADK::Tool do
  let(:tool_class) do
    Class.new(ADK::Tool) do
      self.explicit_tool_name = :suggestion_test_tool
      tool_description 'A tool for testing suggestions'

      parameter :username, type: :string, required: true, description: 'The username'
      parameter :count, type: :integer, required: false, description: 'The count'

      def perform_execution(_params, _context)
        { status: :success }
      end
    end
  end

  subject(:tool) { tool_class.new }

  describe '#execute' do
    context 'when a required parameter is missing due to a typo' do
      it 'raises ToolArgumentError with a suggestion' do
        expect {
          tool.execute({ 'user_name' => 'jules' })
        }.to raise_error(ADK::ToolArgumentError) do |e|
          expect(e.message).to include("Missing required parameters for tool 'suggestion_test_tool': username")
          expect(e.message).to include("Did you mean? 'user_name' -> username")
        end
      end
    end

    context 'when a required parameter is missing with no close match' do
      it 'raises ToolArgumentError without a suggestion' do
        expect {
          tool.execute({ 'completely_wrong' => 'jules' })
        }.to raise_error(ADK::ToolArgumentError) do |e|
          expect(e.message).to include("Missing required parameters for tool 'suggestion_test_tool': username")
          expect(e.message).not_to include("Did you mean?")
        end
      end
    end
  end
end
