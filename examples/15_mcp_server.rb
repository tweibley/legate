# File: examples/15_mcp_server.rb
# frozen_string_literal: true

# --- Example: Exposing an Legate::Tool via MCP using fast-mcp ---
#
# This script demonstrates how to wrap an existing Legate::Tool
# (in this case, the built-in Calculator tool) and expose it
# on an MCP server run over STDIO using the fast-mcp gem.
#
# Prerequisites:
#   - Run `bundle install` in the legate directory.
#   - Ensure the `fast-mcp` gem is available (e.g., via Gemfile path).
#
# Usage:
#   1. Run this script from the legate root directory:
#      `bundle exec ruby examples/15_mcp_server.rb`
#   2. The script will start and wait for MCP JSON-RPC messages on STDIN.
#   3. Use an MCP client (like `mcp-client`, `mcp-inspector`, or another script
#      using Legate::Mcp::Client) connected to this script's STDIO to interact.
#
# Example Interaction (using a generic client):
#   -> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
#   <- {"jsonrpc":"2.0","id":1,"result":{"capabilities":{},"serverInfo":{"name":"Legate Tool Server","version":"1.0"}}}
#   -> {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
#   <- {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"calculator","description":"Performs basic arithmetic operations.","inputSchema":{"type":"object","properties":{"a":{"type":"number","description":"First operand"},"b":{"type":"number","description":"Second operand"},"op":{"type":"string","description":"Operator (+, -, *, /)"}},"required":["a","b","op"]}}]}}
#   -> {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"calculator","arguments":{"a":10,"b":5,"op":"*"}}}
#   <- {"jsonrpc":"2.0","id":3,"result":50.0}
#
# -------------------------------------------------------------

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'legate'
Legate.load_environment # Handle Bundler, Dotenv, etc.

require 'legate/mcp' # Load Legate MCP modules
require 'legate/mcp/server/legate_tool_adapter' # Load the Tool adapter
require 'legate/tools/calculator' # Load the specific Legate tool we want to expose
require 'fast_mcp' # Load the fast-mcp library

Legate.configure do |config|
  # Configure Legate logger level if desired (e.g., :debug for more verbose MCP logs)
  # config.log_level = :debug
end

# --- 1. Wrap the Legate::Tool ---
# Use the LegateToolAdapter to create a fast-mcp compatible class
begin
  AdaptedCalculator = Legate::Mcp::Server::LegateToolAdapter.wrap(Legate::Tools::Calculator)
  Legate.logger.info('Successfully wrapped Legate::Tools::Calculator for MCP.')
rescue StandardError => e
  Legate.logger.fatal("Failed to wrap Legate Tool: #{e.message}")
  exit(1)
end

# --- 2. Create fast-mcp Server Instance ---
# FastMcp::Server uses STDIO transport by default when calling #start
mcp_server = FastMcp::Server.new(
  name: 'Legate Tool Server',
  version: Legate::VERSION # Use Legate version
)
Legate.logger.info('Initialized FastMcp::Server.')

# --- 3. Register the Wrapped Tool ---
mcp_server.register_tool(AdaptedCalculator)
Legate.logger.info("Registered adapted '#{AdaptedCalculator.tool_name}' tool with fast-mcp server.")

# --- 4. Start the Server ---
Legate.logger.info('Starting MCP server on STDIO. Waiting for requests...')
puts '--- Legate MCP Tool Server (STDIO) Ready --- ' # Signal readiness besides logs
begin
  mcp_server.start # This method typically blocks, listening on STDIN
rescue Interrupt
  Legate.logger.info('Received interrupt, shutting down server.')
rescue StandardError => e
  Legate.logger.fatal("MCP server crashed: #{e.class} - #{e.message}")
  Legate.logger.fatal(e.backtrace.join("\n"))
ensure
  Legate.logger.info('MCP server stopped.')
end
