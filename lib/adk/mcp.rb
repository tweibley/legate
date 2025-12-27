# File: lib/adk/mcp.rb
# frozen_string_literal: true

require_relative 'mcp/error'
# We will require other mcp components here as they are built.
require_relative 'mcp/util/schema_converter'
require_relative 'mcp/connection/stdio'
require_relative 'mcp/client'
require_relative 'mcp/tool_wrapper'
require_relative 'mcp/server/adk_tool_adapter'
require_relative 'mcp/server/adk_agent_adapter'
require_relative 'mcp/connection_manager'

module ADK
  # Module for Model Context Protocol (MCP) integration.
  module Mcp
    # Central point for MCP-related logging.
    def self.logger
      ADK.logger
    end

    logger.info('ADK::Mcp module loaded.')
  end
end
