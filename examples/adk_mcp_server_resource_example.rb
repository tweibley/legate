#!/usr/bin/env ruby
# frozen_string_literal: true

# --- Prerequisites ---
# (Same as before)
# --- Usage ---
# 1. Run this script from your project root:
#    bundle exec ruby examples/mcp_adk_calculator_example.rb # <-- Renamed example file
#
# 2. In another terminal, inspect using mcp-inspector:
#    npx mcp-inspector --stdio 'bundle exec ruby examples/mcp_adk_calculator_example.rb'
#
# 3. Example inspector commands:
#    > resources/list
#    > resources/read {"uri": "counter"}
#    > tools/list # Should show counter tools AND run_calculator_agent
#    > tools/call {"name": "run_calculator_agent", "arguments": {"prompt": "What is 5 * 8?"}}
#    > tools/call {"name": "run_calculator_agent", "arguments": {"prompt": "Add 100 and 23"}}
#    > tools/call {"name": "incrementcounter", "arguments": {}}
# -------------------------------------------------------------

# --- IMPORTANT: Configure ADK logging for MCP compatibility ---
# Configure ENV variables before requiring ADK to control logging
ENV['ADK_LOG_LEVEL'] = 'ERROR'
ENV['ADK_LOG_TARGET'] = 'STDERR'

# Now load the libraries
require 'bundler/setup'
require 'adk'      # Load ADK framework
require 'fast_mcp' # Load the fast-mcp library
require 'thread'   # For Mutex
require 'json'     # Needed for JSON generation in #content
require 'singleton' # Needed for Singleton pattern
require 'logger' # For Logger
require 'securerandom' # For generating random session IDs
# ---------------------------------------------

# === ADK Components Setup ===

# 1. Define the ADK Agent that uses the Calculator
calculator_agent = ADK::Agent.new(
  name: 'calculator_agent_instance', # Runtime instance name
  description: 'An agent that can perform calculations.',
  model_name: 'gemini-1.5-flash', # Specify a model (even if dummy for this example)
  tool_classes: [ADK::Tools::Calculator] # Provide the tool class directly
)

# Start the agent runtime (needed for run_task)
calculator_agent.start

# 2. Create a Session Service for the Agent
# Using InMemory for this self-contained example
adk_session_service = ADK::SessionService::InMemory.new

# === End ADK Components Setup ===

# === FastMcp Components Setup ===

# --- 1. Define the Counter Resource (Same as before) ---
class CounterResource < FastMcp::Resource
  include Singleton

  uri 'counter'
  resource_name 'Counter'
  description 'A simple counter resource'
  mime_type 'application/json'
  attr_reader :count

  def initialize
    @count = 0
    @lock = Mutex.new
    super # Call super to ensure proper initialization
  end

  def read; @lock.synchronize { { value: @count } }; end
  def content; JSON.generate(read); end
  def increment; @lock.synchronize { @count += 1 }; @count; end
  def decrement; @lock.synchronize { @count -= 1 }; @count; end
  def get_value; @lock.synchronize { @count }; end
end

# --- 2. Define Counter Tools (Same as before) ---
class IncrementCounterTool < FastMcp::Tool
  description 'Increments the counter resource by 1'
  tool_name 'incrementcounter'
  arguments {}

  def call(**_args)
    counter = CounterResource.instance
    new_value = counter.increment
    # Use notify_resource_updated with the uri
    notify_resource_updated('counter')
    "Counter incremented. New value: #{new_value}"
  end
end

class DecrementCounterTool < FastMcp::Tool
  description 'Decrements the counter resource by 1'
  tool_name 'decrementcounter'
  arguments {}

  def call(**_args)
    counter = CounterResource.instance
    new_value = counter.decrement
    # Use notify_resource_updated with the uri
    notify_resource_updated('counter')
    "Counter decremented. New value: #{new_value}"
  end
end

class GetCounterTool < FastMcp::Tool
  description 'Gets the current value of the counter resource'
  tool_name 'getcounter'
  arguments {}

  def call(**_args)
    counter = CounterResource.instance
    current_value = counter.get_value
    current_value
  end
end

# --- 3. Define the ADK Agent Adapter Tool ---
class InlineAgentToolAdapter < FastMcp::Tool
  description "Runs the internal ADK Calculator Agent with the given prompt."
  tool_name "run_calculator_agent"

  SUPPORTED_OPERATIONS = ['+', '-', '*', '/'].freeze

  arguments do
    required(:operand1).filled(:string).description('The first operand for the calculator')
    required(:operand2).filled(:string).description('The second operand for the calculator')
    required(:operation).filled(:string).description('The operation for the calculator (must be one of: +, -, *, /)')
  end

  # Reference to the agent and session service (class variables)
  # Will be set before registration
  @@agent = nil
  @@session_service = nil
  @@calculator_tool = nil

  # Class method to set up the references needed for initialization
  def self.setup(agent, session_service)
    @@agent = agent
    @@session_service = session_service
    @@calculator_tool = ADK::Tools::Calculator.new
  end

  def call(operand1:, operand2:, operation:)
    # Validate operation
    unless SUPPORTED_OPERATIONS.include?(operation)
      raise StandardError, "Calculator Error: Operation must be one of: #{SUPPORTED_OPERATIONS.join(', ')}"
    end

    # Validate operands are numbers
    begin
      Float(operand1)
      Float(operand2)
    rescue ArgumentError
      raise StandardError, "Calculator Error: Both operands must be valid numbers"
    end

    # Make sure dependencies are set up
    raise "Calculator tool not configured" unless @@calculator_tool

    # Execute the calculation directly using the calculator tool
    result = @@calculator_tool.execute(
      operand1: operand1,
      operand2: operand2,
      operation: operation
    )

    case result[:status]
    when :success
      return result[:result]
    when :error
      raise StandardError, "Calculator Error: #{result[:error_message]}"
    else
      raise StandardError, "Calculator returned unexpected status: #{result[:status]}"
    end
  end
end

# Configure the adapter with agent and session service
InlineAgentToolAdapter.setup(calculator_agent, adk_session_service)

# === Setup and Start the MCP Server ===

# Create the MCP server
mcp_server = FastMcp::Server.new(
  name: 'ADK Combined Example Server',
  version: ADK::VERSION
)

# Register the resource class
mcp_server.register_resource(CounterResource)

# Register the TOOL CLASSES
mcp_server.register_tools(IncrementCounterTool, DecrementCounterTool, GetCounterTool, InlineAgentToolAdapter)

# Start the server (defaults to STDIO transport)
STDERR.puts "--- Starting ADK Combined MCP Server (STDIO) ---"
STDERR.puts "Resource: counter"
STDERR.puts "Tools: incrementcounter, decrementcounter, getcounter, run_calculator_agent"
STDERR.puts "Waiting for MCP client requests on STDIN..."
begin
  mcp_server.start
rescue Interrupt
  # Expected on Ctrl+C
rescue StandardError => e
  STDERR.puts "MCP server crashed: #{e.class} - #{e.message}"
  STDERR.puts e.backtrace.join("\n")
ensure
  STDERR.puts "\n--- ADK Combined MCP Server Stopped ---"
  # Ensure the ADK agent runtime is stopped on exit
  calculator_agent.stop if calculator_agent&.running?
end
