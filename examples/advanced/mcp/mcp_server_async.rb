#!/usr/bin/env ruby
# frozen_string_literal: true

# --- Configure Logging First! ---
# Set log level and target *before* requiring Legate to ensure logger initializes correctly.
ENV['LEGATE_LOG_LEVEL'] = 'ERROR' # Or INFO/DEBUG for more verbose output
ENV['LEGATE_LOG_TARGET'] = 'STDERR' # Send logs to STDERR to avoid interfering with MCP STDOUT communication
# -------------------------------

# Example: Exposing Async Legate Tools via MCP using fast-mcp
#
# This example demonstrates how to wrap an asynchronous Legate tool (like SleepyTool)
# and the necessary Legate::Tools::CheckJobStatusTool using the LegateToolAdapter
# so they can be called by an MCP client.
#
# Requires:
#   - legate gem with MCP support installed
#   - fast-mcp gem installed
#
# To Run:
#   1. Execute this script: `bundle exec ruby examples/advanced/mcp/mcp_server_async.rb`
#   2. In another terminal, use mcp-inspector: `npx @modelcontextprotocol/inspector examples/advanced/mcp/mcp_server_async.rb`
#   3. In the inspector:
#      - Call 'start_sleepy_job' (tool name from SleepyTool metadata) with duration (e.g., 5 seconds).
#      - Observe the pending response with a job_id.
#      - Call 'check_job_status' with the received job_id.
#      - Check status repeatedly until it shows success or error.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'legate'
Legate.load_environment # Handle Bundler, Dotenv, etc.
require 'fast_mcp' # Load fast-mcp gem

# Ensure required Legate components are loaded
require 'legate/tools/base_async_job_tool'
require 'legate/tools/sleepy_tool' # Example async tool
require 'legate/tools/check_job_status_tool' # Tool to check job status
require 'legate/mcp/server/legate_tool_adapter' # The adapter itself

# --- Create the FastMcp Server Instance ---
Legate.logger.info('Creating fast-mcp server...')
# Use the logger from Legate for consistency
mcp_server = FastMcp::Server.new(name: 'legate-async-mcp-server', version: '1.0.0')

# --- Wrap the Legate Tools using the Adapter ---
Legate.logger.info('Wrapping Legate tools for MCP...')

begin
  # Wrap the asynchronous tool (SleepyTool)
  wrapped_sleepy_tool = Legate::Mcp::Server::LegateToolAdapter.wrap(Legate::Tools::SleepyTool)
  Legate.logger.info("Wrapped SleepyTool as: #{wrapped_sleepy_tool.tool_name}")

  # Wrap the CheckJobStatusTool
  wrapped_check_job_tool = Legate::Mcp::Server::LegateToolAdapter.wrap(Legate::Tools::CheckJobStatusTool)
  Legate.logger.info("Wrapped CheckJobStatusTool as: #{wrapped_check_job_tool.tool_name}")

  # --- Register Wrapped Tools with the FastMcp Server ---
  Legate.logger.info('Registering wrapped tools with fast-mcp server...')
  mcp_server.register_tool(wrapped_sleepy_tool)
  mcp_server.register_tool(wrapped_check_job_tool)
rescue ArgumentError => e
  Legate.logger.fatal("Failed to wrap Legate tools: #{e.message}")
  Legate.logger.fatal('Ensure the Legate::Tool classes have complete metadata.')
  exit(1)
rescue StandardError => e
  Legate.logger.fatal("An unexpected error occurred during setup: #{e.message}")
  Legate.logger.fatal(e.backtrace.join("\n"))
  exit(1)
end

# --- Start the Server (using STDIO transport) ---
Legate.logger.info('Starting fast-mcp server with STDIO transport...')
# This will block and listen for JSON-RPC messages on STDIN/STDOUT
mcp_server.start

Legate.logger.info('Server finished.')
