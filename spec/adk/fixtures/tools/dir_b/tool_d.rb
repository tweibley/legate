# frozen_string_literal: true
# File: spec/adk/fixtures/tools/dir_b/tool_d.rb
require 'adk/tool'

class ToolD < ADK::Tool
  # Name :tool_d inferred
  tool_description 'Tool D from fixture'

  def perform_execution(params, context)
    { status: :success, result: 'D' }
  end
end
