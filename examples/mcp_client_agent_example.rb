#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Using an ADK Agent as an MCP Client
#
# This example demonstrates how to configure an ADK::Agent to connect to an
# external MCP server (like the @modelcontextprotocol/server-filesystem) and use its tools.
#
# Key Concepts:
#   - MCP Server Configuration: Defining how to connect to the external server (e.g., via stdio).
#   - Selected Tool Names: Explicitly telling the agent which tools from the MCP server it is allowed to use.
#     The names provided in `selected_tool_names` MUST exactly match the tool names exposed by the specific
#     MCP server you are connecting to (check server logs or capabilities if unsure).
#   - Runtime Start/Stop: Managing the connection lifecycle to the MCP server.
#   - Using External Tools: Making requests that the agent's planner can map to the available MCP tools.
#
# Requires:
#   - adk-ruby gem with MCP support installed
#   - An external MCP server running. For testing, you can use:
#     `npx @modelcontextprotocol/server-filesystem --stdio path/to/a/directory`
#     (Replace `path/to/a/directory` with a real directory the server can access)
#
# To Run:
#   1. Start the external MCP server in one terminal (e.g., the filesystem server command above).
#   2. Ensure the directory specified in `mcp_server_config[:args]` exists and is accessible.
#   3. Run this script in another terminal: `bundle exec ruby examples/mcp_client_agent_example.rb`
#   4. Observe the logs: The agent should initialize, connect to the MCP server, and list available tools
#      (including the ones explicitly selected via `selected_tool_names`, like `:read_file` in this example).
#   5. The script will then attempt to run a task using the `read_file` tool from the MCP server.

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'adk'
ADK.load_environment # Handle Bundler, Dotenv, etc.

require 'adk/mcp' # Ensure MCP modules are loaded

# Configure ADK logger
ENV['ADK_LOG_LEVEL'] = 'DEBUG'
dirname = File.expand_path(File.dirname(File.dirname(__FILE__)))

# --- 1. Define a Native ADK Tool (Optional) ---
class NativeEchoTool < ADK::Tool
  define_metadata(
    name: :native_echo,
    description: 'Echoes back the provided message (native ADK tool).',
    parameters: {
      message: { type: :string, required: true, description: 'Message to echo' }
    }
  )
  def perform_execution(params, context)
    ADK.logger.info("[NativeEchoTool] Echoing: #{params[:message]}")
    { status: :success, result: "Native echo: #{params[:message]}" }
  end
end

# --- 2. Configure the External MCP Server Connection ---
# NOTE: Adjust the command and args based on how you run *your* external server.
# This example assumes the filesystem server.
# Make sure the directory path exists and is accessible!
mcp_server_config = {
  type: 'stdio',
  command: 'npx', # Command to start the server
  args: [         # Arguments for the command
    '--',
    '@modelcontextprotocol/server-filesystem',
    # '--stdio',
    dirname # <<< IMPORTANT: Change this to a real, accessible directory!
    # Create this directory before running: mkdir /tmp/mcp_fs_test_dir
  ]
}
# Check if args include a placeholder path and warn if so
if mcp_server_config[:args].any? { |arg| arg.include?('path/to/') || arg.include?('tmp/mcp_fs_test_dir') }
  ADK.logger.warn('MCP server config in example still uses a placeholder directory.')
  ADK.logger.warn('Please edit examples/mcp_client_agent_example.rb and set a real directory path in `mcp_server_config[:args]`.')
  # Optionally exit if you want to enforce configuration
  # exit(1)
end

# --- 3. Initialize the ADK Agent ---
ADK.logger.info('Initializing agent...')
my_agent = ADK::Agent.new(
  name: 'mcp_client_agent',
  description: 'An agent using native and external MCP tools.',
  tool_classes: [NativeEchoTool], # Add native tools here
  mcp_servers: [mcp_server_config], # Add MCP server configs here
  selected_tool_names: [:read_file] # <<< CHANGED: Match actual tool name from server logs
  # model_name: 'gemini-pro-1.5' # Optional: Specify model
)

# --- 4. Start the Agent Runtime ---
# This connects to the MCP server and registers its tools.
ADK.logger.info('Starting agent runtime...')
my_agent.start
ADK.logger.info("Agent started. Available tool names: #{my_agent.tool_registry.tools.keys}")
ADK.logger.info("Full metadata: #{my_agent.available_tools_metadata.inspect}")

# --- 5. Run a Task (Optional Example) ---
# Uncomment this section to try running a task.
# Requires setting up a session service and ensuring the external server
# provides the tool mentioned in the user_input (e.g., `filesystem/readFile`).

puts "\n--- Running Task Example ---"
begin
  session_service = ADK::SessionService::InMemory.new
  session = session_service.create_session(app_name: 'mcp_client_test', user_id: 'test_user')
  puts "Created session: #{session.id}"

  # Create a dummy file for the filesystem tool to read
  # Ensure the directory matches the one in mcp_server_config[:args]
  dummy_file_path = "#{dirname}/hello.txt"
  begin
    File.write(dummy_file_path, 'Hello from ADK client example!')
    puts "Created dummy file: #{dummy_file_path}"
  rescue => e
    puts "Warning: Could not create dummy file '#{dummy_file_path}': #{e.message}"
    puts 'Filesystem tool example might fail.'
  end

  # Input asking to use a tool likely provided by the filesystem server
  # user_input = "What files are in the #{dirname}? What are the contents of hello.txt in #{dirname}?"
  user_input = "Read the content of the file named 'hello.txt' in #{dirname} using the filesystem tool." # <<< MODIFIED: More specific input
  puts "User Input: #{user_input}"

  final_event = my_agent.run_task(
    session_id: session.id,
    user_input: user_input,
    session_service: session_service
  )

  puts 'Final Agent Event:'
  require 'pp' # Pretty print
  pp final_event
rescue => e
  puts "Error running task: #{e.message}"
  puts e.backtrace
end
puts "--------------------------\n"

# Delete the dummy file after the task is complete
File.delete(dummy_file_path) if File.exist?(dummy_file_path)

#--- 6. Stop the Agent Runtime ---
# This disconnects from the MCP server.
ADK.logger.info('Stopping agent runtime...')
my_agent.stop
ADK.logger.info('Agent stopped.')
