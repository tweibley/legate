# File: lib/legate/mcp.rb
# frozen_string_literal: true

# MCP errors are defined in legate/errors.rb (loaded by lib/legate.rb)
require_relative 'mcp/util/schema_converter'
require_relative 'mcp/connection/stdio'
require_relative 'mcp/client'
require_relative 'mcp/tool_wrapper'
require_relative 'mcp/connection_manager'
require_relative 'mcp/server/legate_tool_adapter'
require_relative 'mcp/server/legate_agent_adapter'

module Legate
  # Module for Model Context Protocol (MCP) integration.
  module Mcp
    # Central point for MCP-related logging.
    def self.logger
      Legate.logger
    end

    logger.info('Legate::Mcp module loaded.')
  end
end
