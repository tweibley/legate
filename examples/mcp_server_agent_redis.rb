#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Exposing a Redis-Defined ADK Agent via MCP
#
# This example demonstrates how to wrap an ADK Agent definition stored in Redis
# as a single MCP tool using AdkAgentAdapter and fast-mcp.
#
# Prerequisites:
#   - adk-ruby gem with MCP support installed.
#   - fast-mcp gem installed.
#   - Redis server running and configured for ADK (see ADK configuration).
#   - An agent definition created in Redis, e.g., using:
#     `bundle exec adk agent create my_redis_agent --description "Test agent in Redis" --tools echo,calculator`
#   - The tools used by the agent (e.g., EchoTool, CalculatorTool) must be registered
#     in the global ADK::ToolRegistry when this script runs.
#
# To Run:
#   1. Ensure Redis is running.
#   2. Create the agent definition in Redis (if not already done).
#   3. Execute this script: `bundle exec ruby examples/mcp_server_agent_redis.rb`
#   4. In another terminal, use mcp-inspector:
#      `npx @modelcontextprotocol/inspector examples/mcp_server_agent_redis.rb`
#   5. In the inspector, call the `run_agent_my_redis_agent` tool (or similar name)
#      with a prompt like "echo hello world" or "calculate 5 + 3".

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'adk'
ADK.load_environment # Handle Bundler, Dotenv, etc.

require 'fast_mcp'
require 'adk/mcp/server/adk_agent_adapter' # The Redis-based adapter
require 'adk/session_service/in_memory' # Example session service

# --- Configuration ---
# Ensure ADK is configured to find Redis
ADK.configure do |config|
  config.log_level = Logger::INFO
  # Make sure redis_options point to your running Redis instance
  # config.redis_options = { url: ENV.fetch('ADK_REDIS_URL', 'redis://localhost:6379/1') }
end

# The name of the agent as defined in Redis
AGENT_NAME_IN_REDIS = 'my_redis_agent' # <<< CHANGE THIS if your agent has a different name

# --- Ensure Agent's Tools are Registered Globally ---
# The AdkAgentAdapter loads the tool *names* from Redis but needs the tool *classes*
# to be available in the global registry when it instantiates the agent ephemerally.
require 'adk/tools/echo'
require 'adk/tools/calculator'
ADK::ToolRegistry.register(ADK::Tools::Echo)
ADK::ToolRegistry.register(ADK::Tools::Calculator)
ADK.logger.info "Globally registered tools: #{ADK::ToolRegistry.tools.keys}"

# --- Setup ---
session_service = ADK::SessionService::InMemory.new # Required by the adapter

# --- Wrap the Agent Definition ---
ADK.logger.info("Wrapping Redis agent definition: #{AGENT_NAME_IN_REDIS}")
begin
  # This uses the AdkAgentAdapter (Redis-based)
  AdaptedAgentRedis = ADK::Mcp::Server::AdkAgentAdapter.wrap(AGENT_NAME_IN_REDIS, session_service)
  ADK.logger.info("Agent wrapped successfully as MCP tool: #{AdaptedAgentRedis.tool_name}")
rescue ADK::Mcp::Error => e
  ADK.logger.fatal("ERROR: Failed to wrap agent '#{AGENT_NAME_IN_REDIS}'. #{e.message}")
  ADK.logger.fatal("Is Redis running and the agent definition present?")
  exit(1)
rescue NameError => e
  ADK.logger.fatal("ERROR: Failed to load dependencies. #{e.message}")
  ADK.logger.fatal("Ensure necessary tool files are required and classes are available.")
  exit(1)
rescue => e
  ADK.logger.fatal("ERROR: An unexpected error occurred during agent wrapping: #{e.class} - #{e.message}")
  ADK.logger.fatal(e.backtrace.join("\n"))
  exit(1)
end

# --- Create and Configure fast-mcp Server ---
mcp_server = FastMcp::Server.new(
  name: 'adk-agent-redis-server',
  version: '1.0.0',
  logger: ADK.logger
)

# --- Register the Wrapped Agent Tool ---
mcp_server.register_tool(AdaptedAgentRedis)

# --- Start the Server (STDIO) ---
puts "Starting ADK MCP Agent Server (Redis: '#{AGENT_NAME_IN_REDIS}') via STDIO..."
mcp_server.start # Blocks here

ADK.logger.info("Server finished.")
