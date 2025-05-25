#!/usr/bin/env ruby

require 'bundler/setup'
require 'adk'
require 'json'

puts "🚢 Actually Working Hull Truth Boats Scraper"
puts "============================================"
puts

# Clear any existing registrations
ADK::GlobalDefinitionRegistry.instance_variable_set(:@definitions, {})

# Ensure required tools are registered
unless ADK::GlobalToolManager.registered_tool_names.include?(:echo)
  ADK::GlobalToolManager.register_tool(ADK::Tools::Echo)
end

# Custom tool for parsing Hull Truth forum threads and extracting boat URLs
class BoatThreadParser < ADK::Tool
  tool_description 'Parses Hull Truth forum accessibility tree to extract boat thread URLs'
  parameter :snapshot_data

  private
  
  def perform_execution(params, context)
    begin
      snapshot_data_input = params[:snapshot_data] || params['snapshot_data']
      
      puts "DEBUG: Snapshot data type: #{snapshot_data_input.class}"
      puts "DEBUG: Snapshot data keys: #{snapshot_data_input.keys if snapshot_data_input.respond_to?(:keys)}"
      
      data_to_parse = if snapshot_data_input.is_a?(String)
        JSON.parse(snapshot_data_input)
      elsif snapshot_data_input.is_a?(Hash)
        snapshot_data_input
      else
        return { status: :error, error_message: "Invalid snapshot data type: #{snapshot_data_input.class}" }
      end

      yaml_content = extract_yaml_text(data_to_parse)
      unless yaml_content
        puts "DEBUG: Failed to extract YAML content"
        puts "DEBUG: Data structure: #{data_to_parse.inspect[0..500]}"
        return { status: :error, error_message: 'Could not find accessibility tree text in snapshot' }
      end
      
      puts "DEBUG: Successfully extracted YAML content (#{yaml_content.length} chars)"
      boat_threads = extract_boat_threads(yaml_content)
      { status: :success, result: boat_threads }

    rescue => e
      { status: :error, error_message: "Parser error: #{e.message}" }
    end
  end

  def extract_yaml_text(data)
    puts "DEBUG: Attempting to extract YAML from data structure"
    
    # Try multiple possible data structures
    possible_paths = [
      # Path 1: Direct result with content array
      lambda { data['result']['content'][0]['text'] if data['result'] && data['result']['content'] && data['result']['content'][0] },
      # Path 2: ADK wrapped result
      lambda { data[:result]['content'][0]['text'] if data[:result] && data[:result]['content'] && data[:result]['content'][0] },
      # Path 3: Direct content array
      lambda { data['content'][0]['text'] if data['content'] && data['content'][0] },
      # Path 4: Symbol keys
      lambda { data[:content][0][:text] if data[:content] && data[:content][0] },
      # Path 5: String result
      lambda { data['result'] if data['result'].is_a?(String) },
      lambda { data[:result] if data[:result].is_a?(String) }
    ]
    
    text_content = nil
    possible_paths.each_with_index do |path_lambda, index|
      begin
        result = path_lambda.call
        if result && result.is_a?(String) && result.length > 100
          puts "DEBUG: Found text content via path #{index + 1} (#{result.length} chars)"
          text_content = result
          break
        end
      rescue => e
        # Continue to next path
      end
    end
    
    return nil unless text_content
    
    # Extract YAML from the markdown-wrapped content
    if text_content.include?('```yaml')
      yaml_match = text_content.match(/```yaml\n(.*?)\n```/m)
      if yaml_match && yaml_match[1]
        puts "DEBUG: Successfully extracted YAML from markdown wrapper"
        return yaml_match[1]
      end
    end
    
    # If no markdown wrapper, check if the content itself is YAML-like
    if text_content.include?('heading ') && text_content.include?('- /url:')
      puts "DEBUG: Using raw text content as YAML"
      return text_content
    end
    
    puts "DEBUG: No YAML content found in text"
    nil
  end

  def extract_boat_threads(yaml_content)
    threads = []
    lines = yaml_content.split("\n")
    
    puts "DEBUG: Processing #{lines.length} lines of YAML content"
    
    # Look for heading elements that look like actual boat listings
    # Skip administrative/sticky threads
    skip_patterns = [
      'Marketing Tips', 'Bumping Threads', 'COMPLETE TRADING', 'Editing Your Thread',
      'How to post', 'Guidelines', 'Rules', 'READ THIS', 'PLEASE READ', 'IMPORTANT'
    ]
    
    # Find all headings with level=4 (these are thread titles)
    thread_headings = []
    lines.each_with_index do |line, index|
      if line.include?('heading ') && line.include?('"') && line.include?('[level=4]')
        # Extract the title from the heading
        title_match = line.match(/heading\s+"([^"]+)"\s+\[level=4\]/)
        if title_match
          title = title_match[1]
          
          # Skip administrative threads
          should_skip = skip_patterns.any? { |pattern| title.include?(pattern) }
          next if should_skip
          
          # Look for boat-related keywords or patterns
          boat_keywords = ['boat', 'yacht', 'vessel', 'ft', 'foot', "'", 'sale', 'sold', '$', 'price']
          has_boat_keywords = boat_keywords.any? { |keyword| title.downcase.include?(keyword.downcase) }
          
          # Also include threads that look like boat models/years
          has_year = title.match?(/\b(19[5-9]\d|20[0-3]\d)\b/)
          has_size = title.match?(/\b\d+\s*(?:ft|foot|')\b/i)
          
          if has_boat_keywords || has_year || has_size || title.length < 50
            thread_headings << { title: title, line_index: index }
          end
        end
      end
    end
    
    puts "DEBUG: Found #{thread_headings.length} potential boat thread headings"
    
    # Now find URLs for these headings
    thread_headings.first(3).each do |heading_info|  # Limit to 3 for testing
      title = heading_info[:title]
      line_index = heading_info[:line_index]
      
      # Look for the corresponding URL in nearby lines (within 10 lines)
      url = nil
      start_search = [line_index - 5, 0].max
      end_search = [line_index + 10, lines.length - 1].min
      
      (start_search..end_search).each do |url_index|
        url_line = lines[url_index]
        if url_line.include?('- /url:') && url_line.include?('/boats-sale/')
          url_match = url_line.match(/- \/url:\s*(https?:\/\/www\.thehulltruth\.com\/boats-sale\/[^\s]+)/)
          if url_match
            potential_url = url_match[1]
            # Remove any trailing fragments or parameters we don't want
            potential_url = potential_url.split('#').first  # Remove fragment
            
            # Skip URLs that are clearly not boat listings
            next if potential_url.include?("do=whoposted") || 
                   potential_url.include?("/members/") ||
                   potential_url.include?("profile-badges") ||
                   potential_url.include?("check-your-passwords") ||
                   potential_url.include?("guidelines") ||
                   potential_url.include?("rules")
            
            url = potential_url
            break
          end
        end
      end
      
      # Only add if we found both title and URL
      if title && url
        threads << {
          title: title.strip,
          url: url,
          index: threads.length
        }
        puts "  Found boat thread: #{title} -> #{url}"
      end
    end
    
    threads
  end
end

class BoatDetailParser < ADK::Tool
  tool_description 'Extracts boat details from individual thread page accessibility tree'
  parameter :snapshot_data
  parameter :thread_info

  private
  
  def perform_execution(params, context)
    begin
      snapshot_data = params[:snapshot_data] || params['snapshot_data']
      thread_info = params[:thread_info] || params['thread_info']
      data = snapshot_data.is_a?(String) ? JSON.parse(snapshot_data) : snapshot_data
      yaml_text = extract_yaml_text(data)
      unless yaml_text
        return { status: :error, error_message: "Could not extract page content from snapshot for thread: #{thread_info[:title]}" }
      end
      details = extract_boat_details(yaml_text, thread_info)
      { status: :success, result: details }
    rescue => e
      { status: :error, error_message: "Detail extraction error for thread '#{thread_info[:title]}': #{e.message}" }
    end
  end

  def extract_yaml_text(data)
    # Use the same extraction logic as BoatThreadParser
    possible_paths = [
      lambda { data['result']['content'][0]['text'] if data['result'] && data['result']['content'] && data['result']['content'][0] },
      lambda { data[:result]['content'][0]['text'] if data[:result] && data[:result]['content'] && data[:result]['content'][0] },
      lambda { data['content'][0]['text'] if data['content'] && data['content'][0] },
      lambda { data[:content][0][:text] if data[:content] && data[:content][0] },
      lambda { data['result'] if data['result'].is_a?(String) },
      lambda { data[:result] if data[:result].is_a?(String) }
    ]
    
    text_content = nil
    possible_paths.each do |path_lambda|
      begin
        result = path_lambda.call
        if result && result.is_a?(String) && result.length > 100
          text_content = result
          break
        end
      rescue => e
        # Continue to next path
      end
    end
    
    return nil unless text_content
    
    # Extract YAML from the markdown-wrapped content
    if text_content.include?('```yaml')
      yaml_match = text_content.match(/```yaml\n(.*?)\n```/m)
      return yaml_match[1] if yaml_match && yaml_match[1]
    end
    
    # If no markdown wrapper, use raw content
    if text_content.include?('heading ') || text_content.include?('- /url:')
      return text_content
    end
    
    nil
  end

  def extract_boat_details(yaml_text, thread_info)
    content = yaml_text
    
    {
      index: thread_info['index'] || thread_info[:index] || 0,
      title: thread_info['title'] || thread_info[:title] || 'Unknown Boat',
      url: thread_info['url'] || thread_info[:url] || '',
      price: extract_price(content),
      location: extract_location(content),
      year: extract_year(content),
      size: extract_size(content),
      description: extract_description(content)
    }
  end

  def extract_price(content)
    price_patterns = [ 
      /\$[\d,]+(?:\.?\d{2})?/, 
      /asking[:\s]*\$?[\d,]+/i, 
      /price[:\s]*\$?[\d,]+/i,
      /\b[\d,]+\s*(?:dollars?|k|K)\b/i
    ]
    price_patterns.each do |pattern|
      match = content.match(pattern)
      if match
        price = match[0].strip.gsub(/asking[:\s]*/i, '').gsub(/price[:\s]*/i, '')
        price = "$#{price}" unless price.start_with?('$')
        return price
      end
    end
    "Price not listed"
  end

  def extract_location(content)
    states = %w[AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY]
    location_patterns = [ 
      /(?:location|located)[:\s]*([^,\n]+(?:,\s*(?:#{states.join('|')}))?)(?:\s|$)/i, 
      /([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*,\s*(?:#{states.join('|')}))(?:\s|$)/, 
      /(#{states.join('|')})(?:\s|$)/ 
    ]
    location_patterns.each do |pattern|
      match = content.match(pattern)
      if match && match[1] && match[1].strip.length > 2
        return match[1].strip
      end
    end
    "Location not specified"
  end

  def extract_year(content)
    year_match = content.match(/\b(19[5-9]\d|20[0-3]\d)\b/)
    year_match ? year_match[1] : "Year not specified"
  end

  def extract_size(content)
    size_patterns = [ /(\d+(?:\.\d+)?)\s*(?:ft|feet|')/i, /(\d+)\s*foot/i ]
    size_patterns.each do |pattern|
      match = content.match(pattern)
      if match && match[1]
        return "#{match[1]} ft"
      end
    end
    "Size not specified"
  end

  def extract_description(content)
    lines = content.split("\n")
    descriptive_lines = lines.select do |line|
      line.strip.length > 20 && line.strip.length < 200 &&
      !line.match?(/(?:text:|generic|link|button|heading)/i) &&
      line.match?(/[a-zA-Z]/)
    end
    if descriptive_lines.any?
      desc = descriptive_lines.first.strip.gsub(/^[:\-\s]+/, '')
      desc = desc[0..97] + "..." if desc.length > 100
      return desc
    end
    "No description available"
  end
end

ADK::GlobalToolManager.register_tool(BoatThreadParser)
ADK::GlobalToolManager.register_tool(BoatDetailParser)

playwright_mcp_config = [{ "type" => "stdio", "command" => "npx", "args" => ["-y", "@playwright/mcp@latest"] }]

MAIN_FORUM_URL = "https://www.thehulltruth.com/boats-sale-17/"

# Create an agent with VERY explicit instructions that force tool usage
working_agent_def = ADK::AgentDefinition.new.define do |a|
  a.name :actually_working_boats_scraper
  a.description 'Boat scraper that actually executes Playwright tools'
  a.instruction <<~INSTRUCTION
    You are a boat scraper that MUST actually execute Playwright browser tools.

    CRITICAL: You MUST use the actual tools, not just describe what you would do.

    When asked to navigate and take a snapshot, you MUST:
    1. Call browser_navigate with the URL
    2. Call browser_snapshot to capture the page
    3. Return the actual snapshot data

    DO NOT just say "I have navigated" or "I have taken a snapshot".
    You MUST actually call the tools and return their results.

    Available tools:
    - browser_navigate: Navigate to URLs (YOU MUST CALL THIS)
    - browser_snapshot: Capture page content (YOU MUST CALL THIS)
    - echo: Echo back input

    EXAMPLE of what you MUST do:
    User: "Navigate to https://example.com and take a snapshot"
    You MUST:
    1. Call browser_navigate with URL "https://example.com"
    2. Call browser_snapshot
    3. Return the snapshot result

    DO NOT just respond with text - USE THE TOOLS!
  INSTRUCTION
  a.model_name 'gemini-2.0-flash'
  a.output_key :scraping_result
  a.mcp_servers playwright_mcp_config
  a.use_tool :browser_navigate
  a.use_tool :browser_snapshot
  a.use_tool :echo
end

ADK::GlobalDefinitionRegistry.register(working_agent_def)

puts "Initializing actually working boat scraper..."
session_service = ADK::SessionService::InMemory.new
session = session_service.create_session(app_name: 'boats_scraper_actually_working', user_id: 'user')
session_id = session.id
puts "Created session: #{session_id}"

agent = ADK::Agent.new(definition: working_agent_def, session_service: session_service)
puts "Starting actually working agent..."
agent.start
puts "Agent started successfully!"

begin
  puts "\n=== STEP 1: Navigate to main forum page ==="
  puts "Sending explicit tool usage request..."
  
  result = agent.run_task(
    session_id: session_id,
    user_input: "You MUST use browser_navigate to go to #{MAIN_FORUM_URL} and then use browser_snapshot to capture the page. Do not just describe - actually call the tools and return the snapshot data.",
    session_service: session_service
  )
  
  main_page_snapshot = session_service.get_state(session_id: session_id, key: :scraping_result)
  
  puts "DEBUG: Main page snapshot type: #{main_page_snapshot.class}"
  puts "DEBUG: Main page snapshot keys: #{main_page_snapshot.keys if main_page_snapshot.respond_to?(:keys)}"
  
  # Check if we actually got browser data vs just text
  if main_page_snapshot.is_a?(Hash) && main_page_snapshot['result'].is_a?(String) && 
     main_page_snapshot['result'].include?("I have navigated")
    puts "❌ AGENT IS NOT USING TOOLS - just describing actions!"
    puts "Agent response: #{main_page_snapshot['result']}"
    puts "\nTrying a more forceful approach..."
    
    # Try again with even more explicit instructions
    result = agent.run_task(
      session_id: session_id,
      user_input: "STOP describing and START doing! Call browser_navigate('#{MAIN_FORUM_URL}') RIGHT NOW, then call browser_snapshot() RIGHT NOW. I need the actual browser data, not descriptions!",
      session_service: session_service
    )
    
    main_page_snapshot = session_service.get_state(session_id: session_id, key: :scraping_result)
    puts "DEBUG: Second attempt snapshot: #{main_page_snapshot.inspect[0..200]}"
  end

  if main_page_snapshot && !main_page_snapshot.empty?
    puts "✅ Main page snapshot captured successfully"
    puts "\n=== STEP 2: Extract boat thread information ==="
    parser = BoatThreadParser.new
    parser_result = parser.execute({ snapshot_data: main_page_snapshot }, nil)

    if parser_result[:status] == :success && parser_result[:result].is_a?(Array) && !parser_result[:result].empty?
      boat_threads = parser_result[:result]
      puts "✅ Found #{boat_threads.length} boat threads"
      boat_threads.each_with_index do |thread, index|
        puts "  #{index + 1}. Title: '#{thread[:title]}', URL: #{thread[:url]}"
      end
      
      puts "\n=== STEP 3: Navigate to each thread directly ==="
      boat_details_list = []
      
      boat_threads.each_with_index do |thread, index|
        puts "\n--- Processing thread #{index + 1} of #{boat_threads.length}: #{thread[:title]} ---"
        
        puts "  🌐 Forcing navigation to thread URL: #{thread[:url]}"
        nav_result = agent.run_task(
          session_id: session_id,
          user_input: "EXECUTE browser_navigate('#{thread[:url]}') then EXECUTE browser_snapshot(). Return the actual snapshot data, not descriptions!",
          session_service: session_service
        )
        
        puts "  ⏳ Waiting for thread page to load..."
        sleep(2)
        
        thread_page_snapshot = session_service.get_state(session_id: session_id, key: :scraping_result)
        
        if thread_page_snapshot && !thread_page_snapshot.empty? && !(thread_page_snapshot.is_a?(Hash) && thread_page_snapshot['status'] == 'error')
          puts "  ✅ Thread page snapshot captured."
          detail_parser = BoatDetailParser.new
          detail_result = detail_parser.execute({ snapshot_data: thread_page_snapshot, thread_info: thread }, nil)
          
          if detail_result[:status] == :success
            boat_details_list << detail_result[:result]
            puts "  ✅ Boat details extracted for '#{thread[:title]}'"
          else
            puts "  ❌ Failed to extract details for '#{thread[:title]}': #{detail_result[:error_message]}"
            boat_details_list << { index: index, title: thread[:title], url: thread[:url], error: "Detail extraction failed: #{detail_result[:error_message]}" }
          end
        else
          puts "  ❌ Failed to capture thread page snapshot for '#{thread[:title]}'"
          boat_details_list << { index: index, title: thread[:title], url: thread[:url], error: "Snapshot failed" }
        end
      end
      
      puts "\n=== STEP 4: Display results ==="
      if boat_details_list.any?
        puts "\n🚢 BOAT LISTINGS FOUND:"
        puts "=" * 80
        boat_details_list.each do |boat|
          next if boat[:error]
          puts "\n#{boat[:index] + 1}. #{boat[:title]}"
          puts "   Price: #{boat[:price]}"
          puts "   Location: #{boat[:location]}"
          puts "   Year: #{boat[:year]}"
          puts "   Size: #{boat[:size]}"
          puts "   Description: #{boat[:description]}"
          puts "   URL: #{boat[:url]}"
        end
        puts "\n✅ Processed #{boat_details_list.length} boat listings."
      else
        puts "❌ No boat details were processed or extracted."
      end
    else
      puts "❌ Failed to extract boat threads or no threads found: #{parser_result[:error_message]}"
    end
  else
    puts "❌ Failed to capture main page snapshot. Result: #{result.inspect}"
  end

rescue => e
  puts "❌ Top-level error during execution: #{e.message}"
  puts e.backtrace.first(10).join("\n")
ensure
  puts "\nStopping actually working agent..."
  agent.stop if agent
  puts "Agent stopped."
end

puts "\n🎉 Actually working scraping complete!" 