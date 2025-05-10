# File: examples/mcp_server_adk_agent.rb
# frozen_string_literal: true

# --- Example: Exposing an ADK::Agent via MCP using fast-mcp ---
#
# This script demonstrates how to wrap an existing ADK::Agent definition
# (stored in Redis) and expose it as a single tool on an MCP server
# run over STDIO using the fast-mcp gem and AdkAgentAdapter.
#
# Prerequisites:
#   - Run `bundle install` in the adk-ruby directory.
#   - Ensure the `fast-mcp` gem is available (e.g., via Gemfile path).
#   - Redis server running and accessible via ADK configuration (e.g., REDIS_URL env var).
#   - An agent definition stored in Redis (e.g., using `adk agent create ...`).
#     Replace `MY_AGENT_NAME_IN_REDIS` below with the actual name.
#
# Usage:
#   1. Replace `MY_AGENT_NAME_IN_REDIS` with your agent's name.
#   2. Run this script from the adk-ruby root directory:
#      `bundle exec ruby examples/mcp_server_adk_agent.rb`
#   3. The script will start and wait for MCP JSON-RPC messages on STDIN.
#   4. Use an MCP client connected to this script's STDIO to interact.
#
# Example Interaction (using a generic client):
#   -> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
#   <- {"jsonrpc":"2.0","id":1,"result":{"capabilities":{},"serverInfo":{"name":"ADK Agent Server","version":"x.y.z"}}}
#   -> {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
#   <- {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"run_agent_MY_AGENT_NAME_IN_REDIS","description":"Runs the ADK Agent 'MY_AGENT_NAME_IN_REDIS' with the given prompt.","inputSchema":{"type":"object","properties":{"prompt":{"type":"string","description":"The user input/prompt for the agent"}},"required":["prompt"]}}]}}
#   -> {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"run_agent_MY_AGENT_NAME_IN_REDIS","arguments":{"prompt":"Hello agent!"}}}
#   <- {"jsonrpc":"2.0","id":3,"result":"Hello from the agent!"} // (or whatever the agent returns)
#
# -------------------------------------------------------------

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'adk'
ADK.load_environment # Handle Bundler, Dotenv, etc.
require 'adk/mcp'
require 'adk/mcp/server/adk_agent_adapter' # Load the Agent adapter
require 'adk/session_service/in_memory' # Using in-memory for temporary sessions
# require 'adk/session_service/redis'     # Or use Redis if preferred
require 'fast_mcp'

# --- ** Configuration: Replace with your agent name ** ---
AGENT_NAME_IN_REDIS = 'my_agent' # <<< CHANGE THIS
# ---------------------------------------------------------

ADK.configure do |config|
  # config.log_level = :debug
  # Ensure Redis URL is configured if not using default localhost
  # config.redis_url = ENV['REDIS_URL'] || 'redis://localhost:6379/0'
end

# --- 1. Create Session Service Instance ---
# AdkAgentAdapter needs this to create temporary sessions for each call.
# Using InMemory for simplicity, but RedisSessionService would also work.
session_service = ADK::SessionService::InMemory.new
ADK.logger.info("Using session service: #{session_service.class}")

# --- 2. Wrap the ADK Agent Definition ---
begin
  # Check Redis connection early (optional but recommended)
  ADK::Mcp::Server::AdkAgentAdapter.connect_redis
  ADK.logger.info('Redis connection check successful.')

  AdaptedAgent = ADK::Mcp::Server::AdkAgentAdapter.wrap(AGENT_NAME_IN_REDIS, session_service)
  ADK.logger.info("Successfully wrapped ADK Agent definition '#{AGENT_NAME_IN_REDIS}' for MCP.")
rescue ADK::Mcp::Error => e # Catch specific MCP errors (e.g., Redis connection)
  ADK.logger.fatal("Failed to wrap ADK Agent: #{e.message}")
  ADK.logger.fatal("Please ensure Redis is running and the agent '#{AGENT_NAME_IN_REDIS}' is defined.")
  exit(1)
rescue StandardError => e
  ADK.logger.fatal("Unexpected error during agent wrap: #{e.message}")
  ADK.logger.fatal(e.backtrace.join("\n"))
  exit(1)
end

# --- 3. Create fast-mcp Server Instance ---
mcp_server = FastMcp::Server::Stdio.new(
  server_info: {
    name: 'ADK Agent Server',
    version: ADK::VERSION
  },
  logger: ADK.logger
)
ADK.logger.info('Initialized FastMcp::Server::Stdio.')

# --- 4. Register the Wrapped Agent Tool ---
mcp_server.register_tool(AdaptedAgent)
ADK.logger.info("Registered adapted agent tool '#{AdaptedAgent.tool_name}' with fast-mcp server.")

# --- 5. Start the Server ---
ADK.logger.info("Starting MCP server on STDIO for agent '#{AGENT_NAME_IN_REDIS}'. Waiting for requests...")
puts "--- ADK MCP Agent Server (#{AGENT_NAME_IN_REDIS}) Ready --- "
begin
  mcp_server.start
rescue Interrupt
  ADK.logger.info('Received interrupt, shutting down server.')
rescue StandardError => e
  ADK.logger.fatal("MCP server crashed: #{e.class} - #{e.message}")
  ADK.logger.fatal(e.backtrace.join("\n"))
ensure
  ADK.logger.info('MCP server stopped.')
end
