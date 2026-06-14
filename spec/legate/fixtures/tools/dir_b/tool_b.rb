# frozen_string_literal: true

# spec/legate/fixtures/tools/dir_b/tool_b.rb
require 'legate/tool'

class FixtureToolB < Legate::Tool
  self.explicit_tool_name = :fixture_tool_b
  tool_description 'Fixture Tool B from Dir B'
  parameter :param_b, type: :integer

  def perform_execution(params, _context)
    { status: :success, result: "Fixture B processed: #{params[:param_b]}" }
  end
end
