# File: examples/advanced/mcp/mcp_server_async_tools.rb
# frozen_string_literal: true

# --- Example: MCP Server with Async Legate Tools ---
#
# This script demonstrates how to expose both async tools and the
# CheckJobStatusTool via MCP. It shows:
# 1. How to wrap async tools for MCP exposure
# 2. How to expose the CheckJobStatusTool
# 3. How to use both tools together via MCP
#
# Prerequisites:
#   - Run `bundle install` to install dependencies
#   - Run this script: bundle exec ruby examples/advanced/mcp/mcp_server_async_tools.rb
#
# Example MCP client interactions:
#   Initialize server:
#   {"jsonrpc": "2.0", "method": "initialize", "params": {}, "id": 1}
#
#   List tools:
#   {"jsonrpc": "2.0", "method": "listTools", "params": {}, "id": 2}
#
#   Call SleepyTool:
#   {"jsonrpc": "2.0", "method": "callTool", "params": {"name": "sleepy_tool", "parameters": {"duration": 5}}, "id": 3}
#
#   Check job status:
#   {"jsonrpc": "2.0", "method": "callTool", "params": {"name": "check_job_status", "parameters": {"job_id": "job_id_from_sleepy_tool"}}, "id": 4}
#
# -------------------------------------------------------------

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'legate'
Legate.load_environment # Handle Bundler, Dotenv, etc.

require 'legate'
require 'legate/mcp'
require 'fast_mcp'
require 'legate/tools/sleepy_tool'
require 'legate/tools/check_job_status_tool'

# Configure Legate logger
Legate.logger.level = Logger::INFO

# Create and register the SleepyTool
class SleepyToolWrapper < FastMcp::Tool
  description 'Sleep for a specified duration'

  arguments do
    required(:duration).filled(:integer, gt?: 0).description('Duration to sleep in seconds')
    required(:message).filled(:string).description('A message to include in the final result')
  end

  def call(args)
    tool = Legate::Tools::SleepyTool.new
    context = Legate::ToolContext.new(
      session_id: 'mcp-session',
      user_id: 'mcp-user',
      app_name: 'mcp-server',
      tool_registry: Legate::ToolRegistry.new
    )
    result = tool.execute({ duration: args[:duration], message: args[:message] }, context)

    case result[:status]
    when :success
      result[:result]
    when :pending
      {
        status: 'pending',
        job_id: result[:job_id],
        message: "Sleepy job started with duration #{args[:duration]}s and message: #{args[:message]}"
      }
    when :error
      raise StandardError, result[:error_message]
    end
  end
end

# Create and register the CheckJobStatusTool
class CheckJobStatusToolWrapper < FastMcp::Tool
  description 'Check the status of a background job'

  arguments do
    required(:job_id).filled(:string, min_size?: 1).description('The ID of the job to check')
  end

  def call(args)
    tool = Legate::Tools::CheckJobStatusTool.new
    context = Legate::ToolContext.new(
      session_id: 'mcp-session',
      user_id: 'mcp-user',
      app_name: 'mcp-server',
      tool_registry: Legate::ToolRegistry.new
    )
    result = tool.execute({ job_id: args[:job_id] }, context)

    case result[:status]
    when :success
      result[:result]
    when :pending
      { status: 'pending', job_id: args[:job_id], message: result[:message] }
    when :error
      raise StandardError, result[:error_message]
    end
  end
end

# Register the tools with the server
server = FastMcp::Server.new(
  name: 'async-tools',
  version: '1.0.0'
)

server.register_tool(SleepyToolWrapper)
server.register_tool(CheckJobStatusToolWrapper)

# Start the server
Legate.logger.info('Starting MCP server with async tools...')
begin
  server.start
rescue Interrupt
  Legate.logger.info('Shutting down MCP server...')
end
