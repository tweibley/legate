# File: examples/mcp_client_agent.rb
# frozen_string_literal: true

# --- Example: Using an ADK::Agent as an MCP Client ---
#
# This script demonstrates how to configure an ADK::Agent to connect
# to an external MCP server (running via STDIO) and potentially use its tools.
#
# Prerequisites:
#   - Run `bundle install` in the adk-ruby directory.
#   - Have an MCP-compliant server ready to run via a command.
#     Example using the official filesystem server:
#       npm install -g @modelcontextprotocol/server-filesystem
#
# Usage:
#   1. Make sure the MCP server command is correct in `mcp_server_config` below.
#   2. Run this script from the adk-ruby root directory:
#      `bundle exec ruby examples/mcp_client_agent.rb`
#   3. The script will:
#      - Initialize an ADK::Agent with the MCP server config.
#      - Start the agent, which connects to the server and lists its tools.
#      - (If uncommented) Attempt to run a task using a tool from the server.
#      - Stop the agent, disconnecting the server.
#
# -------------------------------------------------------------

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'adk'
ADK.load_environment # Handle Bundler, Dotenv, etc.

require 'adk/mcp'
require 'adk/agent'
require 'adk/session_service/in_memory' # Example session service

ADK.configure do |config|
  # config.log_level = :debug # Use debug for detailed MCP communication
end

# --- 1. Configure Connection to External MCP Server ---
# Replace with the actual command to start your MCP server via stdio.
# Example using @modelcontextprotocol/server-filesystem:
mcp_server_config = {
  type: :stdio,
  command: 'npx',
  args: ['@modelcontextprotocol/server-filesystem', '--stdio']
  # Example using the server from mcp_server_adk_tool.rb:
  # command: 'bundle',
  # args: ['exec', 'ruby', 'examples/mcp_server_adk_tool.rb']
}
ADK.logger.info("Using MCP Server Config: #{mcp_server_config}")

# --- 2. Initialize ADK::Agent with MCP Config ---
ADK.logger.info('Initializing agent...')

mcp_client_agent_definition = ADK::AgentDefinition.new.define do |a|
  a.name :mcp_client_example_agent
  a.description 'This agent connects to an external MCP server.'
  a.instruction 'You are an agent that can leverage tools from an MCP server. Please use them as needed.'
  # Pass the single mcp_server_config hash to the mcp_servers DSL method
  a.mcp_servers mcp_server_config
  # If there were native tools, they would be added here, e.g.:
  # a.use_tool :calculator
end

agent = ADK::Agent.new(definition: mcp_client_agent_definition)

# --- 3. Start Agent Runtime (Connects to MCP) ---
begin
  ADK.logger.info('Starting agent runtime...')
  agent.start # This connects to the MCP server and registers tools
  ADK.logger.info('Agent started.')

  # Log available tools (should include those from the MCP server)
  available_tools = agent.available_tools_metadata.map { |t| t[:name].to_s }.sort
  ADK.logger.info("Agent Tools Available (Native + MCP): #{available_tools.join(', ')}")

  # --- 4. (Optional) Run a Task Using an MCP Tool ---
  # Uncomment this section to try executing a task.
  # Assumes the MCP server provides a tool like 'readFile' or 'listDirectory'.
  # Adjust the prompt and tool name based on the specific server.
  # ADK.logger.info("Attempting to run task using MCP tool...")
  # session_service = ADK::SessionService::InMemory.new
  # session = session_service.create_session(app_name: agent.name, user_id: 'mcp_client_user')
  # prompt = "Read the content of 'README.md' using the readFile tool."
  # prompt = "List files in the current directory."
  #
  # if agent.running? && session
  #   final_event = agent.run_task(
  #     session_id: session.id,
  #     user_input: prompt,
  #     session_service: session_service
  #   )
  #   ADK.logger.info("Task finished. Final Agent Event Content:")
  #   pp final_event.content # Use pp for potentially large results
  # else
  #   ADK.logger.error("Agent not running or session not created, skipping task execution.")
  # end
rescue ADK::Mcp::Error => e
  ADK.logger.fatal("MCP Error during agent lifecycle: #{e.message}")
rescue StandardError => e
  ADK.logger.fatal("Unexpected error: #{e.class} - #{e.message}")
  ADK.logger.fatal(e.backtrace.join("\n"))
  finally
  # --- 5. Stop Agent Runtime (Disconnects MCP) ---
  if agent&.running?
    ADK.logger.info('Stopping agent runtime...')
    agent.stop
    ADK.logger.info('Agent stopped.')
  else
    ADK.logger.info('Agent runtime was not running or failed to start.')
  end
end

puts 'MCP Client Agent Example Finished.'
