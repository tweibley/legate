# File: ./examples/adk_mcp_server_resource_example.rb
# !/usr/bin/env ruby
# frozen_string_literal: true

# --- Prerequisites & Usage --- (Similar to before, but focuses on agent)
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

# Load the necessary ADK MCP components
require 'adk/mcp'
# require 'adk/mcp/server/adk_tool_adapter' # No longer needed
require 'adk/mcp/server/adk_direct_agent_adapter' # Require the new adapter

# Load ADK components for direct agent instantiation
require 'adk/agent'
require 'adk/tools/calculator' # Need the Calculator class for agent config
require 'adk/session_service/in_memory' # Need a session service implementation

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
  def call(**_args);
    counter = CounterResource.instance;
    new_value = counter.increment;
    notify_resource_updated('counter'); "Counter incremented. New value: #{new_value}"; end
end

class DecrementCounterTool < FastMcp::Tool
  description 'Decrements the counter resource by 1'; tool_name 'decrementcounter'; arguments {}
  def call(**_args);
    counter = CounterResource.instance;
    new_value = counter.decrement;
    notify_resource_updated('counter'); "Counter decremented. New value: #{new_value}"; end
end

class GetCounterTool < FastMcp::Tool
  description 'Gets the current value of the counter resource'; tool_name 'getcounter'; arguments {}
  def call(**_args); CounterResource.instance.get_value; end
end

# --- 3. Instantiate ADK Agent and Wrap it using the Direct Adapter ---
begin
  # Create an ADK::Agent instance configured with the calculator tool
  calculator_agent = ADK::Agent.new(
    name: 'calculator_agent',
    description: 'An agent that can perform calculations.',
    model_name: 'gemini-2.0-flash', # Use Sonnet model
    tool_classes: [ADK::Tools::Calculator]
  )

  # Create a session service instance (needed by the adapter)
  session_service = ADK::SessionService::InMemory.new

  # Use the new direct adapter to wrap the agent instance
  AdaptedAgentTool = ADK::Mcp::Server::AdkDirectAgentAdapter.wrap(calculator_agent, session_service)
rescue StandardError => e
  # Handle potential errors during agent instantiation or wrapping
  STDERR.puts "Error setting up ADK Agent or Adapter: #{e.message}"
  STDERR.puts e.backtrace.join("\n")
  exit(1)
end
# === End FastMcp Components Setup ===

# === Setup and Start the MCP Server ===

# Create the MCP server instance (no logger passed, ADK logger might be used internally by adapter)
mcp_server = FastMcp::Server.new(
  name: 'ADK Combined Example Server',
  version: ADK::VERSION
)

# Assign server instance to tools needing it (Counter tools)
IncrementCounterTool.server = mcp_server
DecrementCounterTool.server = mcp_server
GetCounterTool.server = mcp_server
# The generated AdaptedAgentTool doesn't need the server ref directly

# Register the resource class
mcp_server.register_resource(CounterResource)

# Register the TOOL CLASSES
mcp_server.register_tools(
  IncrementCounterTool,
  DecrementCounterTool,
  GetCounterTool,
  AdaptedAgentTool # Register the *generated* agent adapter class
)

# Start the server using STDIO transport
STDERR.puts "--- Starting ADK Combined MCP Server (STDIO) ---"
STDERR.puts "Resource URI: counter"
# Use the generated tool name from the adapter
STDERR.puts "Tools: incrementcounter, decrementcounter, getcounter, #{AdaptedAgentTool.tool_name}"
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
