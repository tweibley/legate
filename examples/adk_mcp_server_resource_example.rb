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
require 'singleton'# Needed for Singleton pattern
require 'logger'   # For Logger
# ---------------------------------------------

# === ADK Components Setup ===

# 1. Define the ADK Agent that uses the Calculator
calculator_agent = ADK::Agent.new(
  name: 'calculator_agent_instance', # Runtime instance name
  description: 'An agent that can perform calculations.',
  model_name: 'gemini-test-model', # Specify a model (even if dummy for this example)
  tool_classes: [ADK::Tools::Calculator] # Provide the CLASS
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

  arguments do
    required(:prompt).filled(:string).description('The user input/prompt for the agent')
  end

  # Reference to the agent and session service (class variables)
  # Will be set before registration
  @@agent = nil
  @@session_service = nil

  # Class method to set up the references needed for initialization
  def self.setup(agent, session_service)
    @@agent = agent
    @@session_service = session_service
  end

  def call(prompt:)
    # Make sure dependencies are set up
    raise "Agent not configured" unless @@agent
    raise "Session service not configured" unless @@session_service

    temp_session = nil
    
    begin
      temp_session = @@session_service.create_session(
        app_name: @@agent.name,
        user_id: "mcp_inline_#{SecureRandom.hex(4)}"
      )

      final_event = @@agent.run_task(
        session_id: temp_session.id,
        user_input: prompt,
        session_service: @@session_service
      )

      unless final_event.is_a?(ADK::Event) && final_event.role == :agent && final_event.content.is_a?(Hash)
        raise StandardError, "Agent task finished with unexpected event format: #{final_event.inspect}"
      end

      result_content = final_event.content

      case result_content[:status]
      when :success
        return result_content[:result]
      when :error
        err_msg = result_content[:error_message] || "Agent execution failed."
        raise StandardError, "Agent Error: #{err_msg}"
      when :pending
        job_id = result_content[:job_id]
        msg = result_content[:message] || "Agent task resulted in a pending job."
        return { status: 'pending', job_id: job_id, message: msg }
      else
        raise StandardError, "Agent task finished with unknown status: #{result_content[:status]}"
      end
    rescue StandardError => e
      raise # Re-raise the error for fast-mcp to handle
    ensure
      if temp_session && @@session_service
        begin
          @@session_service.delete_session(session_id: temp_session.id)
        rescue StandardError => del_e
          # Silently handle session deletion error
        end
      end
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