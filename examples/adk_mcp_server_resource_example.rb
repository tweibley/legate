# File: ./examples/adk_mcp_server_resource_example.rb
# !/usr/bin/env ruby
# frozen_string_literal: true

# --- Example: Exposing a multi-tool ADK Agent via MCP ---
# -------------------------------------------------------------

ENV['ADK_LOG_LEVEL'] = 'ERROR'
ENV['ADK_LOG_TARGET'] = 'STDERR'

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'adk'
ADK.load_environment # Handle Bundler, Dotenv, etc.
require 'fast_mcp'
# require 'thread' # No longer needed
# require 'json' # No longer needed
# require 'singleton' # No longer needed
require 'logger'
require 'securerandom'
require 'net/http' # Needed for CatFactResource
require 'uri'      # Needed for CatFactResource

# Load the necessary ADK MCP components
require 'adk/mcp'
require 'adk/mcp/server/adk_direct_agent_adapter'

# Load ADK components for direct agent instantiation
require 'adk/agent'
require 'adk/session_service/in_memory'

# --- Load ALL required ADK Tool Classes ---
require 'adk/tools/calculator'
require 'adk/tools/agent_tool'
require 'adk/tools/random_number_tool'
require 'adk/tools/sleepy_tool'
require 'adk/tools/cat_facts'
require 'adk/tools/check_job_status_tool'
require 'adk/tools/echo'
# ------------------------------------------

# === FastMcp Components Setup ===

# --- NEW: Define MCP Resources based on ADK Tool functionality ---

# 1. Random Number Resource
class RandomNumberResource < FastMcp::Resource
  include Singleton
  uri 'random_number';
  resource_name 'RandomNumber'; description 'Provides a random floating-point number between 0 and 1.'
  mime_type 'application/json'

  def read
    # Generate a new random number on each read
    { value: rand }
  end

  def content
    JSON.generate(read)
  end
end

# 2. Cat Fact Resource
class CatFactResource < FastMcp::Resource
  include Singleton
  uri 'catfact'; resource_name 'CurrentCatFact'; description 'Provides a random cat fact from catfact.ninja.'
  mime_type 'application/json'

  CATFACT_API_URI = URI('https://catfact.ninja/fact')

  def read
    begin
      # Fetch a new fact on each read
      response = Net::HTTP.get_response(CATFACT_API_URI)
      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        { fact: data['fact'] || 'Could not retrieve fact.' }
      else
        ADK.logger.error("CatFactResource: Failed to fetch cat fact. Status: #{response.code}")
        { fact: "Error fetching fact: #{response.code}" }
      end
    rescue StandardError => e
      ADK.logger.error("CatFactResource: Error fetching cat fact: #{e.message}")
      { fact: "Error fetching fact: #{e.message}" }
    end
  end

  def content
    JSON.generate(read)
  end
end

# --- NEW: Define MCP Tools to explicitly interact with the new Resources ---

class GetNewRandomNumberTool < FastMcp::Tool
  description 'Gets a new random number from the RandomNumber resource.'; tool_name 'getrandomnumber'; arguments {}
  def call(**_args)
    # Access the singleton instance and read its current state
    RandomNumberResource.instance.read[:value]
  end
end

class GetNewCatFactTool < FastMcp::Tool
  description 'Gets a new cat fact from the CatFact resource.'; tool_name 'getcatfact'; arguments {}
  def call(**_args)
    # Access the singleton instance and trigger a read
    CatFactResource.instance.read[:fact]
  end
end

# --- 1. Instantiate Master ADK Agent and Wrap it ---
begin
  # List all the tool CLASSES to be given to the agent
  all_tool_classes = [
    ADK::Tools::Calculator,
    ADK::Tools::AgentTool,
    ADK::Tools::RandomNumberTool,
    ADK::Tools::SleepyTool,
    ADK::Tools::CatFacts,
    ADK::Tools::CheckJobStatusTool,
    ADK::Tools::Echo,
    GetNewRandomNumberTool,
    GetNewCatFactTool
  ]

  # Create the ADK::Agent instance with all tools
  master_agent = ADK::Agent.new(
    name: 'master_agent',
    description: 'An agent with access to all built-in ADK tools.',
    model_name: 'gemini-2.0-flash',
    tool_classes: all_tool_classes
  )

  # Create a session service instance
  session_service = ADK::SessionService::InMemory.new

  # Use the direct adapter to wrap the master agent instance
  AdaptedMasterAgentTool = ADK::Mcp::Server::AdkDirectAgentAdapter.wrap(master_agent, session_service)
rescue StandardError => e
  STDERR.puts "Error setting up ADK Master Agent or Adapter: #{e.message}"
  STDERR.puts e.backtrace.join("\n")
  exit(1)
end
# === End FastMcp Components Setup ===

# === Setup and Start the MCP Server ===

mcp_server = FastMcp::Server.new(
  name: 'ADK Master Agent Server', # Updated server name
  version: ADK::VERSION
)

# Register the new Resources
mcp_server.register_resource(RandomNumberResource)
mcp_server.register_resource(CatFactResource)

# Register the Tools (Master Agent + Resource-specific tools)
mcp_server.register_tools(
  AdaptedMasterAgentTool,
  GetNewRandomNumberTool,
  GetNewCatFactTool
)

# Start the server using STDIO transport
STDERR.puts '--- Starting ADK Master Agent MCP Server (STDIO) ---'
STDERR.puts "Resources: #{[RandomNumberResource.uri, CatFactResource.uri].join(', ')}"
STDERR.puts "Tools Available: #{[AdaptedMasterAgentTool.tool_name, GetNewRandomNumberTool.tool_name,
                                 GetNewCatFactTool.tool_name].join(', ')}"
STDERR.puts 'Waiting for MCP client requests on STDIN...'
begin
  mcp_server.start
rescue Interrupt
rescue StandardError => e
  STDERR.puts "MCP server crashed: #{e.class} - #{e.message}"
  STDERR.puts e.backtrace.join("\n")
ensure
  STDERR.puts "\n--- ADK Master Agent MCP Server Stopped ---"
end
