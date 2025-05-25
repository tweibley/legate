#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Get 10 Boat Links Agent with Playwright MCP
#
# This example demonstrates how to create an agent that uses the Playwright MCP server
# to scrape the first 10 "Normal" boat listing URLs from The Hull Truth forum.
#
# Key Concepts:
#   - Single Agent: Performs a specific scraping task.
#   - Playwright MCP Integration: Uses Playwright tools for web scraping.
#   - Data Extraction: Extracts specific URLs.
#   - Error Handling: Basic error handling.
#
# Requires:
#   - adk-ruby gem installed
#   - Playwright MCP server available via npx
#   - Internet connection to access The Hull Truth forum
#
# To Run:
#   bundle exec ruby examples/get-10-boats.rb

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'adk'
ADK.load_environment

require 'adk/mcp'

# Configure logging
ENV['ADK_LOG_LEVEL'] = 'DEBUG'

puts '=== Get 10 Boat Links Agent with Playwright MCP ==='
puts 'This agent scrapes the first 10 "Normal" boat listing URLs from The Hull Truth forum'
puts 'Target: https://www.thehulltruth.com/boats-sale-17/'
puts

# Clear any existing registrations
ADK::GlobalDefinitionRegistry.instance_variable_set(:@definitions, {})

# Ensure required tools are registered
unless ADK::GlobalToolManager.registered_tool_names.include?(:echo)
  ADK::GlobalToolManager.register_tool(ADK::Tools::Echo)
end

# Custom tool for parsing Hull Truth forum threads
class HullTruthParser < ADK::Tool
  tool_description 'Parses Hull Truth forum accessibility tree to extract Normal thread URLs'
  parameter :snapshot_data

  private
  
  def perform_execution(params, context)
    begin
      snapshot_data_input = params[:snapshot_data] || params['snapshot_data']

      if snapshot_data_input.nil? || (snapshot_data_input.is_a?(String) && snapshot_data_input.empty?)
        return { status: :error, error_message: "HullTruthParser received empty or nil snapshot_data. The agent might have failed to pass the snapshot result." }
      end

      data_to_parse = nil
      if snapshot_data_input.is_a?(Hash)
        data_to_parse = snapshot_data_input
      elsif snapshot_data_input.is_a?(String)
        begin
          data_to_parse = JSON.parse(snapshot_data_input)
        rescue JSON::ParserError => e
          return { status: :error, error_message: "HullTruthParser failed to parse snapshot_data string: #{e.message}" }
        end
      else
        return { status: :error, error_message: "HullTruthParser received invalid snapshot_data type: #{snapshot_data_input.class}" }
      end

      # Now, data_to_parse is a Hash. We need to find the YAML text.
      # It could be nested like:
      # 1. ADK-wrapped: { "result" => { "content" => [ { "text" => "YAML..." } ] } } or { result: { content: [ { text: "YAML..." } ] } }
      # 2. Direct MCP:   { "content" => [ { "text" => "YAML..." } ] } or { content: [ { text: "YAML..." } ] }

      yaml_text = nil
      
      # Try ADK-wrapped structure first
      adk_result_payload = data_to_parse['result'] || data_to_parse[:result]
      if adk_result_payload.is_a?(Hash)
        mcp_content_array = adk_result_payload['content'] || adk_result_payload[:content]
        if mcp_content_array.is_a?(Array) && mcp_content_array.first.is_a?(Hash)
          yaml_text = mcp_content_array.first['text'] || mcp_content_array.first[:text]
        end
      end

      # If not found in ADK-wrapped structure, try direct MCP structure
      if yaml_text.nil?
        mcp_content_array = data_to_parse['content'] || data_to_parse[:content]
        if mcp_content_array.is_a?(Array) && mcp_content_array.first.is_a?(Hash)
          yaml_text = mcp_content_array.first['text'] || mcp_content_array.first[:text]
        end
      end
      
      unless yaml_text
        # Log the structure if YAML text is not found, to help debug
        ADK.logger.debug("HullTruthParser: Could not find yaml_text. Data structure received: #{data_to_parse.inspect}")
        return { status: :error, error_message: 'Could not find accessibility tree text in the provided snapshot data structure.' }
      end
      
      # Find the YAML section between ```yaml and ```
      yaml_match = yaml_text.match(/```yaml\n(.*?)\n```/m)
      unless yaml_match && yaml_match[1]
        return { status: :error, error_message: 'Could not find or extract YAML content from accessibility tree text (no ```yaml ... ``` block or empty block found).' }
      end
      
      yaml_content = yaml_match[1]
      
      lines = yaml_content.split("\n")
      
      normal_threads_index = nil
      lines.each_with_index do |line, index|
        if line.include?('Normal Threads')
          normal_threads_index = index
          break
        end
      end
      
      unless normal_threads_index
        return { status: :error, error_message: 'Could not find "Normal Threads" section header in YAML content.' }
      end
      
      urls = []
      current_index = normal_threads_index + 1
      
      while current_index < lines.length && urls.length < 10
        line = lines[current_index]
        
        # Simplified check for a thread item start
        # Example line: "                - generic [ref=e576]:"
        if line.strip.start_with?("- generic ") && line.strip.end_with?("]:")
          thread_end_index = find_thread_end(lines, current_index)
          thread_block_lines = lines[current_index..(thread_end_index)]
          
          url = extract_url_from_thread_block(thread_block_lines)
          if url && url.start_with?('https://www.thehulltruth.com') && !url.include?("do=whoposted") && !url.include?("/members/")
            urls << url unless urls.include?(url)
          end
          
          current_index = thread_end_index + 1
        else
          current_index += 1
        end
      end
      
      { status: :success, result: urls }

    rescue JSON::ParserError => e
      ADK.logger.error("HullTruthParser JSON Parsing Error: #{e.message} for input: #{snapshot_data_input.inspect}")
      { status: :error, error_message: "JSON Parsing Error for snapshot_data string: #{e.message}" }
    rescue => e
      ADK.logger.error("HullTruthParser Internal Error: #{e.message}\nBacktrace: #{e.backtrace.join("\n")}")
      { status: :error, error_message: "Internal HullTruthParser error: #{e.message}" }
    end
  end
  
  def find_thread_end(lines, start_index)
    start_indentation = get_indentation(lines[start_index])
    
    (start_index + 1...lines.length).each do |i|
      line = lines[i]
      next if line.strip.empty?
      
      current_indentation = get_indentation(line)
      if current_indentation <= start_indentation && line.strip.start_with?("- ")
        return i - 1
      end
    end
    
    lines.length - 1
  end
  
  def get_indentation(line)
    line.match(/^(\s*)/)[1].length
  end
  
  def extract_url_from_thread_block(thread_lines)
    thread_lines.each do |line|
      url_match = line.match(/- \/url:\s*(https?:\/\/www\.thehulltruth\.com\/boats-sale\/[^#\s]+)/)
      return url_match[1].strip if url_match
    end
    nil
  end
end

# Register the custom tool
ADK::GlobalToolManager.register_tool(HullTruthParser)

# ----- MCP Server Configuration -----
playwright_mcp_config = [
  {
    "type" => "stdio",
    "command" => "npx",
    "args" => ["-y", "@playwright/mcp@latest"]
  }
]

puts "Playwright MCP Configuration:"
puts playwright_mcp_config.inspect
puts

# ----- Define the Link Extraction Agent -----
link_extractor_agent_def = ADK::AgentDefinition.new.define do |a|
  a.name :ten_boats_link_extractor
  a.description 'Navigates to The Hull Truth forum and captures page snapshot.'
  a.instruction <<~INSTRUCTION
    You are a web navigation specialist. Your task is to navigate to The Hull Truth boats for sale forum
    and capture a snapshot of the page content.

    Perform these actions STRICTLY in this order:
    1. Use `browser_navigate` to go to the URL: https://www.thehulltruth.com/boats-sale-17/.
       IMPORTANT: When using `browser_navigate`, ensure you explicitly use a wait condition that allows the page to fully load its dynamic content. Try using the `waitUntil: 'networkidle'` parameter for the tool. If problems persist, `waitUntil: 'load'` could be an alternative.
       - If `browser_navigate` indicates a Cloudflare challenge, stop immediately and do not proceed to step 2.
    2. Use `browser_snapshot` to get the page's accessibility tree. This will capture the current state of the page and should be your final action.

    Do NOT use any other tools after browser_snapshot.
    Do NOT use echo or any other tools.
    The browser_snapshot result should be your final output.
  INSTRUCTION
  a.model_name 'gemini-2.0-flash'
  a.output_key :page_snapshot
  a.mcp_servers playwright_mcp_config
  a.use_tool :browser_navigate
  a.use_tool :browser_snapshot
end

# Register the agent
ADK::GlobalDefinitionRegistry.register(link_extractor_agent_def)

# ----- Initialize and Run the Agent -----

puts "Initializing boat link extraction process..."

# Create session service
session_service = ADK::SessionService::InMemory.new
session = session_service.create_session(app_name: 'get_10_boats', user_id: 'example_user')
session_id = session.id
puts "Created session: #{session_id}"

puts "Processing boat link extraction request..."

# Create the agent instance
link_extractor_agent = ADK::Agent.new(definition: link_extractor_agent_def, session_service: session_service)

# Start the agent
puts "Starting agent..."
link_extractor_agent.start
puts "Agent started successfully!"
puts "Beginning boat link extraction..."
puts

# Run the agent to capture the page snapshot
result = link_extractor_agent.run_task(
  session_id: session_id,
  user_input: "Navigate to The Hull Truth boats for sale forum and capture page snapshot",
  session_service: session_service
)

puts "\n✅ Page snapshot capture attempt completed!"

# Get the captured page snapshot from session state
page_snapshot_output = session_service.get_state(session_id: session_id, key: :page_snapshot)

if page_snapshot_output && !page_snapshot_output.empty?
  puts "\n=== PROCESSING CAPTURED SNAPSHOT ==="
  puts "------------------------------------"
  puts "Raw snapshot data structure:"
  puts page_snapshot_output.inspect

  # Use the HullTruthParser tool to extract URLs from the snapshot
  parser = HullTruthParser.new
  parser_result = parser.execute({ snapshot_data: page_snapshot_output }, nil)

  puts "\nParser result:"
  puts parser_result.inspect

  if parser_result[:status] == :success && parser_result[:result].is_a?(Array)
    urls = parser_result[:result]
    puts "\n=== EXTRACTED BOAT THREAD URLS ==="
    puts "Found #{urls.length} thread URLs:"
    urls.each_with_index do |url, index|
      puts "#{index + 1}. #{url}"
    end
  else
    puts "\n❌ Parser failed or returned no URLs:"
    puts "Status: #{parser_result[:status]}"
    puts "Error: #{parser_result[:error_message]}" if parser_result[:error_message]
  end
else
  puts "\n❌ No page snapshot data found in session state."
  puts "The agent may have failed to capture the page snapshot."
end

puts "=== EXTRACTION COMPLETE ==="

# Clean up - stop the agent
puts "\nStopping agent..."
begin
  link_extractor_agent.stop if link_extractor_agent
  puts "Agent stopped successfully."
rescue => e
  puts "Warning: Error stopping agent: #{e.message}"
end 