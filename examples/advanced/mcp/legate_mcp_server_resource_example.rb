# File: ./examples/advanced/mcp/legate_mcp_server_resource_example.rb
# !/usr/bin/env ruby
# frozen_string_literal: true

# --- Example: Exposing a multi-tool Legate Agent via MCP ---
# -------------------------------------------------------------

ENV['LEGATE_LOG_LEVEL'] = 'ERROR'
ENV['LEGATE_LOG_TARGET'] = 'STDERR'

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'legate'
Legate.load_environment # Handle Bundler, Dotenv, etc.
require 'fast_mcp'
# require 'thread' # No longer needed
# require 'json' # No longer needed
# require 'singleton' # No longer needed
require 'logger'
require 'securerandom'
require 'net/http' # Needed for CatFactResource
require 'uri'      # Needed for CatFactResource

# Load the necessary Legate MCP components
require 'legate/mcp'
require 'legate/mcp/server/legate_direct_agent_adapter'

# Load Legate components for direct agent instantiation
require 'legate/agent'
require 'legate/session_service/in_memory'

# --- Load ALL required Legate Tool Classes ---
require 'legate/tools/calculator'
require 'legate/tools/agent_tool'
require 'legate/tools/random_number_tool'
require 'legate/tools/sleepy_tool'
require 'legate/tools/cat_facts'
require 'legate/tools/check_job_status_tool'
require 'legate/tools/echo'
# ------------------------------------------

# === FastMcp Components Setup ===

# --- NEW: Define MCP Resources based on Legate Tool functionality ---

# 1. Random Number Resource
class RandomNumberResource < FastMcp::Resource
  include Singleton
  uri 'random_number'
  resource_name 'RandomNumber'
  description 'Provides a random floating-point number between 0 and 1.'
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
  uri 'catfact'
  resource_name 'CurrentCatFact'
  description 'Provides a random cat fact from catfact.ninja.'
  mime_type 'application/json'

  CATFACT_API_URI = URI('https://catfact.ninja/fact')

  def read
    # Fetch a new fact on each read
    response = Net::HTTP.get_response(CATFACT_API_URI)
    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      { fact: data['fact'] || 'Could not retrieve fact.' }
    else
      Legate.logger.error("CatFactResource: Failed to fetch cat fact. Status: #{response.code}")
      { fact: "Error fetching fact: #{response.code}" }
    end
  rescue StandardError => e
    Legate.logger.error("CatFactResource: Error fetching cat fact: #{e.message}")
    { fact: "Error fetching fact: #{e.message}" }
  end

  def content
    JSON.generate(read)
  end
end

# --- NEW: Define MCP Tools to explicitly interact with the new Resources ---

class GetNewRandomNumberTool < FastMcp::Tool
  description 'Gets a new random number from the RandomNumber resource.'
  tool_name 'getrandomnumber'
  arguments {}
  def call(**_args)
    # Access the singleton instance and read its current state
    RandomNumberResource.instance.read[:value]
  end
end

class GetNewCatFactTool < FastMcp::Tool
  description 'Gets a new cat fact from the CatFact resource.'
  tool_name 'getcatfact'
  arguments {}
  def call(**_args)
    # Access the singleton instance and trigger a read
    CatFactResource.instance.read[:fact]
  end
end

# --- 1. Instantiate Master Legate Agent and Wrap it ---
begin
  # List all the tool CLASSES to be given to the agent
  all_tool_classes = [
    Legate::Tools::Calculator,
    Legate::Tools::AgentTool,
    Legate::Tools::RandomNumberTool,
    Legate::Tools::SleepyTool,
    Legate::Tools::CatFacts,
    Legate::Tools::CheckJobStatusTool,
    Legate::Tools::Echo,
    GetNewRandomNumberTool,
    GetNewCatFactTool
  ]

  # Create the Legate::Agent instance with all tools
  master_agent = Legate::Agent.new(
    name: 'master_agent',
    description: 'An agent with access to all built-in Legate tools.',
    model_name: 'gemini-3.5-flash',
    tool_classes: all_tool_classes
  )

  # Create a session service instance
  session_service = Legate::SessionService::InMemory.new

  # Use the direct adapter to wrap the master agent instance
  AdaptedMasterAgentTool = Legate::Mcp::Server::LegateDirectAgentAdapter.wrap(master_agent, session_service)
rescue StandardError => e
  warn "Error setting up Legate Master Agent or Adapter: #{e.message}"
  warn e.backtrace.join("\n")
  exit(1)
end
# === End FastMcp Components Setup ===

# === Setup and Start the MCP Server ===

mcp_server = FastMcp::Server.new(
  name: 'Legate Master Agent Server', # Updated server name
  version: Legate::VERSION
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
warn '--- Starting Legate Master Agent MCP Server (STDIO) ---'
warn "Resources: #{[RandomNumberResource.uri, CatFactResource.uri].join(', ')}"
warn "Tools Available: #{[AdaptedMasterAgentTool.tool_name, GetNewRandomNumberTool.tool_name,
                          GetNewCatFactTool.tool_name].join(', ')}"
warn 'Waiting for MCP client requests on STDIN...'
begin
  mcp_server.start
rescue Interrupt
rescue StandardError => e
  warn "MCP server crashed: #{e.class} - #{e.message}"
  warn e.backtrace.join("\n")
ensure
  warn "\n--- Legate Master Agent MCP Server Stopped ---"
end
