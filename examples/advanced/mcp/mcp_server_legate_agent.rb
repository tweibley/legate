# File: examples/advanced/mcp/mcp_server_legate_agent.rb
# frozen_string_literal: true

# --- Example: Exposing an Legate::Agent via MCP using fast-mcp ---
#
# This script demonstrates how to wrap an existing Legate::Agent definition
# and expose it as a single tool on an MCP server
# run over STDIO using the fast-mcp gem and LegateAgentAdapter.
#
# Prerequisites:
#   - Run `bundle install` in the legate directory.
#   - Ensure the `fast-mcp` gem is available (e.g., via Gemfile path).
#   - An agent definition registered in GlobalDefinitionRegistry.
#     Replace `MY_AGENT_NAME` below with the actual name.
#
# Usage:
#   1. Replace `MY_AGENT_NAME` with your agent's name.
#   2. Run this script from the legate root directory:
#      `bundle exec ruby examples/advanced/mcp/mcp_server_legate_agent.rb`
#   3. The script will start and wait for MCP JSON-RPC messages on STDIN.
#   4. Use an MCP client connected to this script's STDIO to interact.
#
# Example Interaction (using a generic client):
#   -> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
#   <- {"jsonrpc":"2.0","id":1,"result":{"capabilities":{},"serverInfo":{"name":"Legate Agent Server","version":"x.y.z"}}}
#   -> {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
#   <- {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"run_agent_MY_AGENT_NAME","description":"Runs the Legate Agent 'MY_AGENT_NAME' with the given prompt.","inputSchema":{"type":"object","properties":{"prompt":{"type":"string","description":"The user input/prompt for the agent"}},"required":["prompt"]}}]}}
#   -> {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"run_agent_MY_AGENT_NAME","arguments":{"prompt":"Hello agent!"}}}
#   <- {"jsonrpc":"2.0","id":3,"result":"Hello from the agent!"} // (or whatever the agent returns)
#
# -------------------------------------------------------------

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'legate'
Legate.load_environment # Handle Bundler, Dotenv, etc.
require 'legate/mcp'
require 'legate/mcp/server/legate_agent_adapter' # Load the Agent adapter
require 'legate/session_service/in_memory' # Using in-memory for temporary sessions
require 'fast_mcp'

# --- ** Configuration: Replace with your agent name ** ---
AGENT_NAME = 'my_agent' # <<< CHANGE THIS
# ---------------------------------------------------------

Legate.configure do |config|
  # config.log_level = :debug
end

# --- 1. Create Session Service Instance ---
# LegateAgentAdapter needs this to create temporary sessions for each call.
# Using InMemory for simplicity, but RedisSessionService would also work.
session_service = Legate::SessionService::InMemory.new
Legate.logger.info("Using session service: #{session_service.class}")

# --- 2. Wrap the Legate Agent Definition ---
begin
  AdaptedAgent = Legate::Mcp::Server::LegateAgentAdapter.wrap(AGENT_NAME, session_service)
  Legate.logger.info("Successfully wrapped Legate Agent definition '#{AGENT_NAME}' for MCP.")
rescue Legate::Mcp::Error => e
  Legate.logger.fatal("Failed to wrap Legate Agent: #{e.message}")
  Legate.logger.fatal("Please ensure the agent '#{AGENT_NAME}' is defined.")
  exit(1)
rescue StandardError => e
  Legate.logger.fatal("Unexpected error during agent wrap: #{e.message}")
  Legate.logger.fatal(e.backtrace.join("\n"))
  exit(1)
end

# --- 3. Create fast-mcp Server Instance ---
mcp_server = FastMcp::Server::Stdio.new(
  server_info: {
    name: 'Legate Agent Server',
    version: Legate::VERSION
  },
  logger: Legate.logger
)
Legate.logger.info('Initialized FastMcp::Server::Stdio.')

# --- 4. Register the Wrapped Agent Tool ---
mcp_server.register_tool(AdaptedAgent)
Legate.logger.info("Registered adapted agent tool '#{AdaptedAgent.tool_name}' with fast-mcp server.")

# --- 5. Start the Server ---
Legate.logger.info("Starting MCP server on STDIO for agent '#{AGENT_NAME}'. Waiting for requests...")
puts "--- Legate MCP Agent Server (#{AGENT_NAME}) Ready --- "
begin
  mcp_server.start
rescue Interrupt
  Legate.logger.info('Received interrupt, shutting down server.')
rescue StandardError => e
  Legate.logger.fatal("MCP server crashed: #{e.class} - #{e.message}")
  Legate.logger.fatal(e.backtrace.join("\n"))
ensure
  Legate.logger.info('MCP server stopped.')
end
