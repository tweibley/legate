#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Exposing ADK Tools via MCP using Rack Middleware
#
# This example demonstrates how to wrap an ADK tool (CalculatorTool)
# using AdkToolAdapter and expose it via MCP using fast-mcp's
# Rack middleware integration.
#
# Requires:
#   - adk-ruby gem with MCP support installed
#   - fast-mcp gem installed
#   - rack and puma gems installed (`bundle add rack puma`)
#
# To Run:
#   1. Execute this script: `bundle exec ruby examples/mcp_server_rack.rb`
#   2. The server will start on http://localhost:9292.
#   3. In another terminal, use mcp-inspector (select SSE transport):
#      `npx @modelcontextprotocol/inspector`
#      Connect to: `http://localhost:9292/mcp/sse`
#   4. In the inspector:
#      - Call the 'my_calculator' tool with parameters like:
#        { "a": 10, "b": 5, "op": "*" }
#      - Observe the result.

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'adk'
ADK.load_environment # Handle Bundler, Dotenv, etc.

require 'fast_mcp'
require 'adk/mcp/server/adk_tool_adapter'
require 'adk/tools/calculator' # The ADK tool we want to expose
require 'rack'
require 'rack/handler/puma'

ENV['ADK_LOG_LEVEL'] = 'FATAL'

# Configure ADK logger
# ADK.configure { |c| c.log_level = Logger::INFO }

# --- Define a simple base Rack app ---
# This is the app that runs alongside the MCP middleware.
# You could replace this with your Rails/Sinatra app.
base_app = lambda do |env|
  if env['PATH_INFO'] == '/'
    [200, { 'Content-Type' => 'text/html' }, [
      '<html><body>',
      '<h1>ADK MCP Rack Server Example</h1>',
      '<p>MCP endpoints are active at /mcp/sse and /mcp/messages.</p>',
      '</body></html>'
    ]]
  else
    [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
  end
end

# --- Wrap the ADK Tool ---
begin
  AdaptedCalculator = ADK::Mcp::Server::AdkToolAdapter.wrap(ADK::Tools::Calculator)
  ADK.logger.info("Wrapped CalculatorTool as: #{AdaptedCalculator.tool_name}")
rescue ArgumentError => e
  ADK.logger.fatal("Failed to wrap CalculatorTool: #{e.message}")
  exit(1)
end

# --- Create the MCP Middleware ---
# This adds the /mcp/sse and /mcp/messages endpoints to the base_app.
mcp_middleware = FastMcp.rack_middleware(
  base_app,
  name: 'adk-rack-server',
  version: '1.0.0',
  logger: ADK.logger,
  allowed_origins: ['localhost', '127.0.0.1'] # Optional: Customize allowed origins
) do |server|
  # Register the wrapped tool with the server instance managed by the middleware
  server.register_tool(AdaptedCalculator)
  ADK.logger.info("Registered adapted tools with fast-mcp middleware server.")
end

# --- Run the Rack Application with Puma ---
puts 'Starting Rack application with MCP middleware on http://localhost:9292'
puts 'MCP endpoints:'
puts '  - http://localhost:9292/mcp/sse (SSE endpoint)'
puts '  - http://localhost:9292/mcp/messages (JSON-RPC endpoint)'
puts 'Press Ctrl+C to stop'

Rack::Handler::Puma.run mcp_middleware, Port: 9292

ADK.logger.info("Server finished.")
