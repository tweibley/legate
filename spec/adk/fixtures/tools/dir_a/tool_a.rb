# frozen_string_literal: true

# spec/adk/fixtures/tools/dir_a/tool_a.rb
require 'adk/tool'

class FixtureToolA < ADK::Tool
  # Use the new DSL for defining metadata
  self.explicit_tool_name = :fixture_tool_a
  tool_description 'Fixture Tool A from Dir A'
  parameter :param_a, type: :string, required: true

  def perform_execution(params, context)
    # Simple execution logic for testing
    { status: :success, result: "Fixture A processed: #{params[:param_a]}" }
  end
end
