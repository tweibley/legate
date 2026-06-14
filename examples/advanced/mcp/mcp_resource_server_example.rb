#!/usr/bin/env ruby
# frozen_string_literal: true

# --- Usage ---
# 1. Run this script from your project root:
#    bundle exec ruby examples/advanced/mcp/mcp_resource_server_example.rb
#
# 2. In another terminal, inspect using mcp-inspector:
#    npx mcp-inspector --stdio 'bundle exec ruby examples/advanced/mcp/mcp_resource_server_example.rb'
#
# 3. Example inspector commands:
#    > resources/list
#    > resources/read {"uri": "counter"}
#    > tools/list # Should show counter tools AND run_calculator_agent
#    > tools/call {"name": "run_calculator_agent", "arguments": {"prompt": "What is 5 * 8?"}}
#    > tools/call {"name": "run_calculator_agent", "arguments": {"prompt": "Add 100 and 23"}}
#    > tools/call {"name": "incrementcounter", "arguments": {}}
# -------------------------------------------------------------

# --- IMPORTANT: Configure Legate logging for MCP compatibility ---
# Configure ENV variables before requiring Legate to control logging
ENV['LEGATE_LOG_LEVEL'] = 'ERROR' # Set high level to minimize Legate output
ENV['LEGATE_LOG_TARGET'] = 'STDERR' # Redirect Legate logs to STDERR

# Now load the libraries
$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'legate'
Legate.load_environment # Handle Bundler, Dotenv, etc.
require 'fast_mcp' # Load the fast-mcp library
require 'json'     # Needed for JSON generation in #content
require 'singleton' # Needed for Singleton pattern
require 'logger' # For Logger constant access
# ---------------------------------------------

# === Legate Components Setup ===

# 1. Define the Legate Agent that uses the Calculator
calculator_agent = Legate::Agent.new(
  name: 'calculator_agent_instance', # Runtime instance name
  description: 'An agent that can perform calculations.',
  model_name: 'gemini-test-model', # Specify a model (even if dummy for this example)
  tool_classes: [Legate::Tools::Calculator] # Provide the CLASS
)
# Start the agent runtime (needed for run_task)
calculator_agent.start

# 2. Create a Session Service for the Agent
# Using InMemory for this self-contained example
session_service = Legate::SessionService::InMemory.new

# === End Legate Components Setup ===

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
    @lock.synchronize {
      @count += 1
      new_value = @count
    }
    notify_change # Moved here
    new_value
  end

  def decrement
    new_value = nil
    @lock.synchronize {
      @count -= 1
      new_value = @count
    }
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
  def call(**_args)
    counter = CounterResource.instance
    counter.get_value
  end
end

# --- 3. Define the Legate Agent Adapter Tool ---
class InlineAgentToolAdapter < FastMcp::Tool
  # --- Define metadata via class methods ---
  def self.tool_name
    'run_calculator_agent'
  end

  def self.description
    'Runs the internal Legate Calculator Agent with the given prompt.'
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
    raise 'Agent not configured via InlineAgentToolAdapter.setup' unless @@agent
    raise 'Session service not configured via InlineAgentToolAdapter.setup' unless @@session_service

    temp_session = nil
    # Legate logs are silenced via ENV var setup

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

      raise StandardError, "Agent task finished with unexpected event format: #{final_event.inspect}" unless final_event.is_a?(Legate::Event) && final_event.role == :agent && final_event.content.is_a?(Hash)

      result_content = final_event.content

      case result_content[:status]
      when :success
        result_content[:result]
      when :error
        err_msg = result_content[:error_message] || 'Agent execution failed.'
        raise StandardError, "Agent Error: #{err_msg}"
      when :pending
        job_id = result_content[:job_id]
        msg = result_content[:message] || 'Agent task resulted in a pending job.'
        { status: 'pending', job_id: job_id, message: msg }
      else
        raise StandardError, "Agent task finished with unknown status: #{result_content[:status]}"
      end
    rescue StandardError => e
      # Log error to STDERR since Legate logger might be fully silenced
      warn "InlineAgentToolAdapter Error during call: #{e.class} - #{e.message}"
      warn e.backtrace.first(5).join("\n")
      raise # Re-raise the error for fast-mcp to handle
    ensure
      if temp_session && @@session_service
        begin
          @@session_service.delete_session(session_id: temp_session.id)
        rescue StandardError => e
          # Log deletion error to STDERR
          warn "InlineAgentToolAdapter: Error deleting temp session #{temp_session.id}: #{e.message}"
        end
      end
    end
  end
end
# --- End Legate Agent Adapter Tool ---

# === Setup and Start the MCP Server ===

# --- Configure the adapter class BEFORE registration ---
InlineAgentToolAdapter.setup(calculator_agent, session_service)
# --- END Configure Adapter ---

# --- Create server without logger (following sample) ---
mcp_server = FastMcp::Server.new(
  name: 'Legate Combined Example Server',
  version: Legate::VERSION
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
warn '--- Starting Legate Combined MCP Server (STDIO) ---'
warn 'Resource: counter'
warn 'Tools: incrementcounter, decrementcounter, getcounter, run_calculator_agent'
warn 'Waiting for MCP client requests on STDIN...'
begin
  mcp_server.start # This uses STDIO by default
rescue Interrupt
  # Expected on Ctrl+C
rescue StandardError => e
  warn "MCP server crashed: #{e.class} - #{e.message}"
  warn e.backtrace.join("\n")
ensure
  warn "\n--- Legate Combined MCP Server Stopped ---"
  # Ensure the Legate agent runtime is stopped on exit
  calculator_agent.stop if calculator_agent&.running?
end
