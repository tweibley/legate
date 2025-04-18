#!/usr/bin/env ruby
# frozen_string_literal: true

# --- Configure Logging First! ---
# Set log level and target *before* requiring ADK to ensure logger initializes correctly.
ENV['ADK_LOG_LEVEL'] = 'ERROR' # Or INFO/DEBUG for more verbose output
ENV['ADK_LOG_TARGET'] = 'STDERR' # Send logs to STDERR to avoid interfering with MCP STDOUT communication
# -------------------------------

# Example: Exposing Async ADK Tools via MCP using fast-mcp
#
# This example demonstrates how to wrap an asynchronous ADK tool (like SleepyTool)
# and the necessary ADK::Tools::CheckJobStatusTool using the AdkToolAdapter
# so they can be called by an MCP client.
#
# Requires:
#   - adk-ruby gem with MCP support installed
#   - fast-mcp gem installed
#   - Sidekiq running (for the async tool to execute)
#
# To Run:
#   1. Ensure Sidekiq is running and configured for ADK jobs.
#   2. Execute this script: `bundle exec ruby examples/mcp_server_async.rb`
#   3. In another terminal, use mcp-inspector: `npx @modelcontextprotocol/inspector examples/mcp_server_async.rb`
#   4. In the inspector:
#      - Call 'start_sleepy_job' (tool name from SleepyTool metadata) with duration (e.g., 5 seconds).
#      - Observe the pending response with a job_id.
#      - Call 'check_job_status' with the received job_id.
#      - Check status repeatedly until it shows success or error.

require 'bundler/setup'
require 'adk' # Load ADK framework (logger will initialize using ENV vars now)
require 'fast_mcp' # Load fast-mcp gem

# Ensure required ADK components are loaded
require 'adk/tools/base_async_job_tool'
require 'adk/tools/sleepy_tool' # Example async tool
require 'adk/tools/check_job_status_tool' # Tool to check job status
require 'adk/mcp/server/adk_tool_adapter' # The adapter itself

# --- Create the FastMcp Server Instance ---
ADK.logger.info("Creating fast-mcp server...")
# Use the logger from ADK for consistency
mcp_server = FastMcp::Server.new(name: 'adk-async-mcp-server', version: '1.0.0')

# --- Wrap the ADK Tools using the Adapter ---
ADK.logger.info("Wrapping ADK tools for MCP...")

begin
  # Wrap the asynchronous tool (SleepyTool)
  wrapped_sleepy_tool = ADK::Mcp::Server::AdkToolAdapter.wrap(ADK::Tools::SleepyTool)
  ADK.logger.info("Wrapped SleepyTool as: #{wrapped_sleepy_tool.tool_name}")

  # Wrap the CheckJobStatusTool
  wrapped_check_job_tool = ADK::Mcp::Server::AdkToolAdapter.wrap(ADK::Tools::CheckJobStatusTool)
  ADK.logger.info("Wrapped CheckJobStatusTool as: #{wrapped_check_job_tool.tool_name}")

  # --- Register Wrapped Tools with the FastMcp Server ---
  ADK.logger.info("Registering wrapped tools with fast-mcp server...")
  mcp_server.register_tool(wrapped_sleepy_tool)
  mcp_server.register_tool(wrapped_check_job_tool)
rescue ArgumentError => e
  ADK.logger.fatal("Failed to wrap ADK tools: #{e.message}")
  ADK.logger.fatal("Ensure the ADK::Tool classes have complete metadata.")
  exit(1)
rescue StandardError => e
  ADK.logger.fatal("An unexpected error occurred during setup: #{e.message}")
  ADK.logger.fatal(e.backtrace.join("\n"))
  exit(1)
end

# --- Start the Server (using STDIO transport) ---
ADK.logger.info("Starting fast-mcp server with STDIO transport...")
# This will block and listen for JSON-RPC messages on STDIN/STDOUT
mcp_server.start

ADK.logger.info("Server finished.")
