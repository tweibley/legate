# File: examples/mcp_server_adk_tool.rb
# frozen_string_literal: true

# --- Example: Exposing an ADK::Tool via MCP using fast-mcp ---
#
# This script demonstrates how to wrap an existing ADK::Tool
# (in this case, the built-in Calculator tool) and expose it
# on an MCP server run over STDIO using the fast-mcp gem.
#
# Prerequisites:
#   - Run `bundle install` in the adk-ruby directory.
#   - Ensure the `fast-mcp` gem is available (e.g., via Gemfile path).
#
# Usage:
#   1. Run this script from the adk-ruby root directory:
#      `bundle exec ruby examples/mcp_server_adk_tool.rb`
#   2. The script will start and wait for MCP JSON-RPC messages on STDIN.
#   3. Use an MCP client (like `mcp-client`, `mcp-inspector`, or another script
#      using ADK::Mcp::Client) connected to this script's STDIO to interact.
#
# Example Interaction (using a generic client):
#   -> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
#   <- {"jsonrpc":"2.0","id":1,"result":{"capabilities":{},"serverInfo":{"name":"ADK Tool Server","version":"1.0"}}}
#   -> {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
#   <- {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"calculator","description":"Performs basic arithmetic operations.","inputSchema":{"type":"object","properties":{"a":{"type":"number","description":"First operand"},"b":{"type":"number","description":"Second operand"},"op":{"type":"string","description":"Operator (+, -, *, /)"}},"required":["a","b","op"]}}]}}
#   -> {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"calculator","arguments":{"a":10,"b":5,"op":"*"}}}
#   <- {"jsonrpc":"2.0","id":3,"result":50.0}
#
# -------------------------------------------------------------

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'adk'
ADK.load_environment # Handle Bundler, Dotenv, etc.

require 'adk/mcp' # Load ADK MCP modules
require 'adk/mcp/server/adk_tool_adapter' # Load the Tool adapter
require 'adk/tools/calculator' # Load the specific ADK tool we want to expose
require 'fast_mcp' # Load the fast-mcp library

ADK.configure do |config|
  # Configure ADK logger level if desired (e.g., :debug for more verbose MCP logs)
  # config.log_level = :debug
end

# --- 1. Wrap the ADK::Tool ---
# Use the AdkToolAdapter to create a fast-mcp compatible class
begin
  AdaptedCalculator = ADK::Mcp::Server::AdkToolAdapter.wrap(ADK::Tools::Calculator)
  ADK.logger.info('Successfully wrapped ADK::Tools::Calculator for MCP.')
rescue StandardError => e
  ADK.logger.fatal("Failed to wrap ADK Tool: #{e.message}")
  exit(1)
end

# --- 2. Create fast-mcp Server Instance ---
# We'll use the STDIO server for this example
mcp_server = FastMcp::Server::Stdio.new(
  server_info: {
    name: 'ADK Tool Server',
    version: ADK::VERSION # Use ADK version
  },
  logger: ADK.logger # Integrate with ADK's logger
)
ADK.logger.info('Initialized FastMcp::Server::Stdio.')

# --- 3. Register the Wrapped Tool ---
mcp_server.register_tool(AdaptedCalculator)
ADK.logger.info("Registered adapted '#{AdaptedCalculator.tool_name}' tool with fast-mcp server.")

# --- 4. Start the Server ---
ADK.logger.info('Starting MCP server on STDIO. Waiting for requests...')
puts '--- ADK MCP Tool Server (STDIO) Ready --- ' # Signal readiness besides logs
begin
  mcp_server.start # This method typically blocks, listening on STDIN
rescue Interrupt
  ADK.logger.info('Received interrupt, shutting down server.')
rescue StandardError => e
  ADK.logger.fatal("MCP server crashed: #{e.class} - #{e.message}")
  ADK.logger.fatal(e.backtrace.join("\n"))
ensure
  ADK.logger.info('MCP server stopped.')
end
