# File: ./examples/adk_mcp_server_resource_example.rb
#!/usr/bin/env ruby
# frozen_string_literal: true

# --- Prerequisites & Usage --- (Same as before)
# -------------------------------------------------------------

ENV['ADK_LOG_LEVEL'] = 'ERROR'
ENV['ADK_LOG_TARGET'] = 'STDERR'

require 'bundler/setup'
require 'adk'
require 'fast_mcp'
require 'thread'
require 'json'
require 'singleton'
require 'logger'
require 'securerandom'

# Load the necessary ADK MCP components, including the new adapter
require 'adk/mcp'
require 'adk/mcp/server/adk_tool_adapter'
require 'adk/tools/calculator' # Need the ADK Calculator class itself

# === FastMcp Components Setup ===

# --- 1. Define the Counter Resource --- (Same as before)
class CounterResource < FastMcp::Resource
  include Singleton
  uri 'counter'; resource_name 'Counter'; description 'A simple counter resource.'
  mime_type 'application/json'
  attr_reader :count
  def initialize; @count = 0; @lock = Mutex.new; super; end
  def read; @lock.synchronize { { value: @count } }; end
  def content; JSON.generate(read); end
  def increment; new_value = nil; @lock.synchronize { @count += 1; new_value = @count }; new_value; end
  def decrement; new_value = nil; @lock.synchronize { @count -= 1; new_value = @count }; new_value; end
  def get_value; @lock.synchronize { @count }; end
end

# --- 2. Define MCP Tools to Interact with the Counter Resource --- (Same as before)
class IncrementCounterTool < FastMcp::Tool
  description 'Increments the counter resource by 1'; tool_name 'incrementcounter'; arguments {}
  def call(**_args); counter = CounterResource.instance; new_value = counter.increment; notify_resource_updated('counter'); "Counter incremented. New value: #{new_value}"; end
end
class DecrementCounterTool < FastMcp::Tool
  description 'Decrements the counter resource by 1'; tool_name 'decrementcounter'; arguments {}
  def call(**_args); counter = CounterResource.instance; new_value = counter.decrement; notify_resource_updated('counter'); "Counter decremented. New value: #{new_value}"; end
end
class GetCounterTool < FastMcp::Tool
  description 'Gets the current value of the counter resource'; tool_name 'getcounter'; arguments {}
  def call(**_args); CounterResource.instance.get_value; end
end

# --- 3. Wrap the ADK Calculator Tool using the Adapter ---
# This replaces the manual AdkCalculatorAdapterTool definition
begin
  # Use the wrap method to generate the fast-mcp compatible class
  AdaptedAdkCalculatorTool = ADK::Mcp::Server::AdkToolAdapter.wrap(ADK::Tools::Calculator)
rescue ArgumentError => e
  # Handle potential errors during wrapping (e.g., missing metadata)
  STDERR.puts "Error wrapping ADK::Tools::Calculator: #{e.message}"
  exit(1)
end
# === End FastMcp Components Setup ===

# === Setup and Start the MCP Server ===

# Create the MCP server instance (no logger passed)
mcp_server = FastMcp::Server.new(
  name: 'ADK Combined Example Server',
  version: ADK::VERSION
)

# Assign server instance to tools needing it
IncrementCounterTool.server = mcp_server
DecrementCounterTool.server = mcp_server
GetCounterTool.server = mcp_server
# The generated AdaptedAdkCalculatorTool doesn't need the server ref directly

# Register the resource class
mcp_server.register_resource(CounterResource)

# Register the TOOL CLASSES
mcp_server.register_tools(
  IncrementCounterTool,
  DecrementCounterTool,
  GetCounterTool,
  AdaptedAdkCalculatorTool # Register the *generated* adapter class
)

# Start the server using STDIO transport
STDERR.puts "--- Starting ADK Combined MCP Server (STDIO) ---"
STDERR.puts "Resource URI: counter"
# Use the generated tool name from the adapter
STDERR.puts "Tools: incrementcounter, decrementcounter, getcounter, #{AdaptedAdkCalculatorTool.tool_name}"
STDERR.puts "Waiting for MCP client requests on STDIN..."
begin
  mcp_server.start
rescue Interrupt
rescue StandardError => e
  STDERR.puts "MCP server crashed: #{e.class} - #{e.message}"
  STDERR.puts e.backtrace.join("\n")
ensure
  STDERR.puts "\n--- ADK Combined MCP Server Stopped ---"
end