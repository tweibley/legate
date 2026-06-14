# frozen_string_literal: true

# File: spec/legate/fixtures/tools/dir_b/tool_d.rb
require 'legate/tool'

class ToolD < Legate::Tool
  # Name :tool_d inferred
  tool_description 'Tool D from fixture'

  def perform_execution(_params, _context)
    { status: :success, result: 'D' }
  end
end
