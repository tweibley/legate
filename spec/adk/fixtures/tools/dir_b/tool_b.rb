# frozen_string_literal: true
# spec/adk/fixtures/tools/dir_b/tool_b.rb
require 'adk/tool'

class FixtureToolB < ADK::Tool
  self.explicit_tool_name = :fixture_tool_b
  tool_description 'Fixture Tool B from Dir B'
  parameter :param_b, type: :integer

  def perform_execution(params, context)
    { status: :success, result: "Fixture B processed: #{params[:param_b]}" }
  end
end
