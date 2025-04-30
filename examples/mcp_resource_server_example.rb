#!/usr/bin/env ruby
# frozen_string_literal: true

# --- Prerequisites ---
# (Same as before)
# --- Usage ---
# 1. Run this script from your project root:
#    bundle exec ruby examples/mcp_adk_calculator_example.rb # <-- File name
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
ENV['ADK_LOG_LEVEL'] = 'ERROR' # Set high level to minimize ADK output
ENV['ADK_LOG_TARGET'] = 'STDERR' # Redirect ADK logs to STDERR

# Now load the libraries
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'adk'
ADK.load_environment # Handle Bundler, Dotenv, etc.
require 'fast_mcp' # Load the fast-mcp library
require 'thread'   # For Mutex
require 'json'     # Needed for JSON generation in #content
require 'singleton' # Needed for Singleton pattern
require 'logger' # For Logger constant access
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

# --- 1. Define the Counter Resource ---
class CounterResource < FastMcp::Resource
  include Singleton # Use Singleton pattern

  # --- Define metadata via class methods ---
  def self.uri
    'counter'
  end

  def self.resource_name
    'Counter' # Changed back to capitalized as per original example convention
  end

  def self.description
    'A simple counter resource'
  end

  def self.mime_type
    'application/json'
  end
  # --- End metadata via class methods ---

  attr_reader :count

  def initialize # Singleton's initialize
    # Removed super call
    @count = 0
    @lock = Mutex.new
  end

  def read; @lock.synchronize { { value: @count } }; end
  def content; JSON.generate(read); end

  def increment
    new_value = nil
    @lock.synchronize { @count += 1; new_value = @count }
    notify_change # Moved here
    new_value
  end

  def decrement
    new_value = nil
    @lock.synchronize { @count -= 1; new_value = @count }
    notify_change # Moved here
    new_value
  end

  def get_value; @lock.synchronize { @count }; end
end

# --- 2. Define Counter Tools ---
class IncrementCounterTool < FastMcp::Tool
  # --- Define metadata via class methods ---
  def self.tool_name
    'incrementcounter'
  end

  def self.description
    'Increments the counter resource by 1'
  end
  # --- End metadata via class methods ---

  # Server accessor needed by FastMcp for notify_change
  attr_accessor :server

  arguments {} # Define arguments block
  def call(**_args)
    counter = CounterResource.instance
    new_value = counter.increment # Resource handles notify_change
    "Counter incremented. New value: #{new_value}"
  end
end

class DecrementCounterTool < FastMcp::Tool
  # --- Define metadata via class methods ---
  def self.tool_name
    'decrementcounter'
  end

  def self.description
    'Decrements the counter resource by 1'
  end
  # --- End metadata via class methods ---

  # Server accessor needed by FastMcp for notify_change
  attr_accessor :server

  arguments {} # Define arguments block
  def call(**_args)
    counter = CounterResource.instance
    new_value = counter.decrement # Resource handles notify_change
    "Counter decremented. New value: #{new_value}"
  end
end

class GetCounterTool < FastMcp::Tool
  # --- Define metadata via class methods ---
  def self.tool_name
    'getcounter'
  end

  def self.description
    'Gets the current value of the counter resource'
  end
  # --- End metadata via class methods ---

  # Server accessor needed by FastMcp
  attr_accessor :server

  arguments {} # Define arguments block
  def call(**_args); counter = CounterResource.instance; counter.get_value; end
end

# --- 3. Define the ADK Agent Adapter Tool ---
class InlineAgentToolAdapter < FastMcp::Tool
  # --- Define metadata via class methods ---
  def self.tool_name
    "run_calculator_agent"
  end

  def self.description
    "Runs the internal ADK Calculator Agent with the given prompt."
  end
  # --- End metadata via class methods ---

  # Server accessor needed by FastMcp
  attr_accessor :server

  # --- Define arguments using DSL block ---
  arguments do
    required(:prompt).filled(:string).description('The user input/prompt for the agent')
  end
  # --- End arguments block ---

  # --- Use class variables for dependencies (workaround for class-based registration) ---
  @@agent = nil
  @@session_service = nil

  # Class method to set up the references needed *before* registration
  def self.setup(agent, session_service)
    @@agent = agent
    @@session_service = session_service
  end
  # --- End class variables setup ---

  # No instance initialize needed if dependencies are class-level

  def call(prompt:)
    # Make sure dependencies are set up via the class method
    raise "Agent not configured via InlineAgentToolAdapter.setup" unless @@agent
    raise "Session service not configured via InlineAgentToolAdapter.setup" unless @@session_service

    temp_session = nil
    # ADK logs are silenced via ENV var setup

    begin
      temp_session = @@session_service.create_session(
        app_name: @@agent.name, # Use agent name from class variable
        user_id: "mcp_inline_#{SecureRandom.hex(4)}"
      )

      final_event = @@agent.run_task( # Use agent from class variable
        session_id: temp_session.id,
        user_input: prompt,
        session_service: @@session_service # Use service from class variable
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
      # Log error to STDERR since ADK logger might be fully silenced
      STDERR.puts "InlineAgentToolAdapter Error during call: #{e.class} - #{e.message}"
      STDERR.puts e.backtrace.first(5).join("\n")
      raise # Re-raise the error for fast-mcp to handle
    ensure
      if temp_session && @@session_service
        begin
          @@session_service.delete_session(session_id: temp_session.id)
        rescue StandardError => del_e
          # Log deletion error to STDERR
          STDERR.puts "InlineAgentToolAdapter: Error deleting temp session #{temp_session.id}: #{del_e.message}"
        end
      end
    end
  end
end
# --- End ADK Agent Adapter Tool ---

# === Setup and Start the MCP Server ===

# --- Configure the adapter class BEFORE registration ---
InlineAgentToolAdapter.setup(calculator_agent, adk_session_service)
# --- END Configure Adapter ---

# --- Create server without logger (following sample) ---
mcp_server = FastMcp::Server.new(
  name: 'ADK Combined Example Server',
  version: ADK::VERSION
)
# --- END ---

# Register the resource class
mcp_server.register_resource(CounterResource)

# --- Register TOOL CLASSES ---
mcp_server.register_tools(
  IncrementCounterTool,
  DecrementCounterTool,
  GetCounterTool,
  InlineAgentToolAdapter # Register the adapter class
)
# --- END Registration ---

# Start the server (defaults to STDIO transport)
# Output status messages to STDERR so they don't interfere with STDOUT protocol
STDERR.puts "--- Starting ADK Combined MCP Server (STDIO) ---"
STDERR.puts "Resource: counter"
STDERR.puts "Tools: incrementcounter, decrementcounter, getcounter, run_calculator_agent"
STDERR.puts "Waiting for MCP client requests on STDIN..."
begin
  mcp_server.start # This uses STDIO by default
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
