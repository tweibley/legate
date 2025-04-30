# File: spec/adk/fixtures/tools/dir_a/tool_c.rb
require 'adk/tool'

class ToolC < ADK::Tool
  # Name :tool_c inferred
  tool_description 'Tool C from fixture'
  parameter :c_param, type: :string

  def perform_execution(params, context)
    { status: :success, result: 'C' }
  end
end
