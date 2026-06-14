# frozen_string_literal: true

# File: spec/legate/fixtures/tools/dir_a/tool_c.rb
require 'legate/tool'

class ToolC < Legate::Tool
  # Name :tool_c inferred
  tool_description 'Tool C from fixture'
  parameter :c_param, type: :string

  def perform_execution(_params, _context)
    { status: :success, result: 'C' }
  end
end
