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
      'How to post', 'Guidelines', 'Rules', 'READ THIS', 'PLEASE READ', 'IMPORTANT',
      'Attn sponsors', 'Attention sponsors', 'Sponsors', 'SPONSORS', 'STICKY',
      'Moderator', 'Admin', 'Announcement', 'ANNOUNCEMENT', 'Forum Rules',
      'Trading Guidelines', 'Posting Guidelines', 'PINNED', 'Pin:', 'Sticky:'
    ]
    
    # Find all headings with level=4 (these are thread titles)
    thread_headings = []
    lines.each_with_index do |line, index|
      if line.include?('heading ') && line.include?('"') && line.include?('[level=4]')
        # Extract the title from the heading
        title_match = line.match(/heading\s+"([^"]+)"\s+\[level=4\]/)
        if title_match
          title = title_match[1]
          
          # Skip administrative threads (case insensitive)
          should_skip = skip_patterns.any? { |pattern| title.downcase.include?(pattern.downcase) }
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
    
    # Now find URLs for these headings - increased from 3 to 10
    thread_headings.first(10).each do |heading_info|
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
    
    # Extract all text content from posts, prioritizing the original post
    posts = extract_posts_content(content)
    
    # Use the new LLM analyzer for better extraction
    analyzer = LLMBoatAnalyzer.new
    analysis_result = analyzer.execute({ posts_content: posts, thread_info: thread_info }, nil)
    
    if analysis_result[:status] == :success
      enhanced_details = analysis_result[:result]
      {
        index: thread_info['index'] || thread_info[:index] || 0,
        title: thread_info['title'] || thread_info[:title] || 'Unknown Boat',
        url: thread_info['url'] || thread_info[:url] || '',
        price: enhanced_details[:price],
        location: enhanced_details[:location],
        year: enhanced_details[:year],
        size: enhanced_details[:size],
        description: enhanced_details[:description]
      }
    else
      # Fallback to original extraction methods
      puts "DEBUG: LLM analysis failed, using fallback: #{analysis_result[:error_message]}"
      {
        index: thread_info['index'] || thread_info[:index] || 0,
        title: thread_info['title'] || thread_info[:title] || 'Unknown Boat',
        url: thread_info['url'] || thread_info[:url] || '',
        price: extract_price_from_posts(posts),
        location: extract_location_from_posts(posts),
        year: extract_year_from_posts(posts),
        size: extract_size_from_posts(posts),
        description: extract_description_from_posts(posts)
      }
    end
  end

  def extract_posts_content(yaml_text)
    posts = []
    lines = yaml_text.split("\n")
    current_post = nil
    in_post_content = false
    
    puts "DEBUG: Starting post extraction from #{lines.length} lines"
    
    lines.each_with_index do |line, index|
      # Look for post markers (post numbers like #1, #2, etc.)
      if line.match?(/link\s+"(\d+)"\s+.*cursor=pointer.*:/)
        post_number = line.match(/link\s+"(\d+)"/)[1].to_i
        if current_post
          puts "DEBUG: Completed post ##{current_post[:post_number]} with #{current_post[:content].length} content items"
          posts << current_post
        end
        current_post = { post_number: post_number, content: [], is_thread_starter: false }
        in_post_content = false
        puts "DEBUG: Started new post ##{post_number}"
      elsif line.include?('Thread Starter') && current_post
        current_post[:is_thread_starter] = true
        puts "DEBUG: Post ##{current_post[:post_number]} marked as thread starter"
      elsif line.include?('- separator') && current_post
        # Separator often indicates start of actual post content
        in_post_content = true
      elsif line.include?('- text:') && current_post
        # Extract the actual text content
        text_match = line.match(/- text:\s*(.+)/)
        if text_match && text_match[1]
          text_content = text_match[1].strip
          
          # Skip user metadata and UI elements more aggressively
          skip_patterns = [
            /^(Reply|Like|Quote|#\d+|Joined|Posts|From|Likes|Admirals Club|\d+\s+Year Member)$/i,
            /^\d+$/,
            /cursor=pointer/,
            /^(Jun|Jul|Aug|Sep|Oct|Nov|Dec|Jan|Feb|Mar|Apr|May)\s+\d{4}$/,
            /^Received\s+\d+\s+Likes/i,
            /^(Naples|Tampa|Fort|Miami|Orlando),?\s+(Florida|FL)$/i,
            /^"(Joined|Posts|From|Likes):"$/,
            /^(Thread Starter|Admiral|Member)$/i,
            /^\d{2}-\d{2}-\d{4}\s+\|\s+\d{2}:\d{2}\s+(AM|PM)$/,
            /^(Old|Default)$/i
          ]
          
          should_skip = text_content.length < 5 || 
                       skip_patterns.any? { |pattern| text_content.match?(pattern) }
          
          # Only include content that seems like actual post text
          if !should_skip && (in_post_content || text_content.length > 15)
            current_post[:content] << text_content
          end
        end
      end
    end
    
    # Add the last post
    if current_post
      puts "DEBUG: Completed final post ##{current_post[:post_number]} with #{current_post[:content].length} content items"
      posts << current_post
    end
    
    # Sort posts by post number, with thread starter first
    sorted_posts = posts.sort_by { |post| [post[:is_thread_starter] ? 0 : 1, post[:post_number]] }
    
    puts "DEBUG: Found #{sorted_posts.length} total posts"
    sorted_posts.each do |post|
      puts "DEBUG: Post ##{post[:post_number]} (#{post[:is_thread_starter] ? 'STARTER' : 'reply'}): #{post[:content].length} items"
      if post[:content].length > 0
        puts "DEBUG:   First few items: #{post[:content].first(3).join(' | ')}"
      end
    end
    
    sorted_posts
  end

  def extract_price_from_posts(posts)
    # Look for price information across all posts, prioritizing original post
    all_content = posts.map { |post| post[:content].join(' ') }.join(' ')
    
    puts "DEBUG: Price extraction analyzing content: #{all_content[0..300]}..."
    
    # Enhanced price patterns that are more specific to boat listings
    price_patterns = [
      # Price reduction patterns (highest priority)
      /price\s*reduction[:\s-]*\$\s*([\d,]+(?:\.\d+)?)\s*(?:million|mil|m|k|obo|firm)?\b/i,
      /reduced\s*to[:\s-]*\$\s*([\d,]+(?:\.\d+)?)\s*(?:million|mil|m|k|obo|firm)?\b/i,
      # Specific boat sale patterns with million/thousand handling
      /(?:for sale|asking|price)[:\s-]*\$\s*([\d,]+(?:\.\d+)?)\s*(million|mil|m)\b/i,
      /(?:for sale|asking|price)[:\s-]*\$\s*([\d,]+(?:\.\d+)?)\s*k\b/i,
      /(?:for sale|asking|price)[:\s-]*\$\s*([\d,]+(?:\.\d+)?)\s*(?:obo|firm)?\s*$/i,
      # Standalone price with context indicators
      /\$\s*([\d,]+(?:\.\d+)?)\s*(million|mil|m)\b/i,
      /\$\s*([\d,]+(?:\.\d+)?)\s*k\b/i,
      /\$\s*([\d,]+(?:\.\d+)?)\s*(?:obo|firm|negotiable)\b/i,
      # Large amounts that are clearly boat prices (6+ digits or with commas)
      /\$\s*([1-9]\d{5,}(?:,\d{3})*)\b/,
      /\$\s*(\d{1,3}(?:,\d{3})+)\b/
    ]
    
    found_prices = []
    
    price_patterns.each_with_index do |pattern, pattern_index|
      matches = all_content.scan(pattern)
      puts "DEBUG: Pattern #{pattern_index + 1} found #{matches.length} matches: #{matches.inspect}"
      matches.each do |match|
        if match.is_a?(Array)
          price_str = match[0]
          unit = match[1] if match.length > 1
        else
          price_str = match
          unit = nil
        end
        
        next unless price_str
        
        puts "DEBUG: Processing price string: '#{price_str}' with unit: '#{unit}'"
        
        # Clean up the price string
        clean_price = price_str.gsub(/[^\d,.]/, '')
        next if clean_price.empty?
        
        # Convert to number for validation
        base_price = clean_price.gsub(',', '').to_f
        
        # Apply unit multipliers
        price_num = case unit&.downcase
                   when 'million', 'mil', 'm'
                     base_price * 1_000_000
                   when 'k'
                     base_price * 1_000
                   else
                     base_price
                   end
        
        puts "DEBUG: Cleaned price: '#{clean_price}' -> base: #{base_price}, unit: #{unit}, final: #{price_num}"
        
        # Only consider realistic boat prices (over $5,000 and under $50M)
        if price_num >= 5000 && price_num <= 50_000_000
          # Format nicely
          formatted_price = if price_num >= 1_000_000
            "$#{(price_num / 1_000_000).round(1)}M"
          elsif price_num >= 1000
            "$#{price_num.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
          else
            "$#{price_num.to_i}"
          end
          
          # Give priority to price reductions (patterns 1-2)
          priority = pattern_index < 2 ? 1 : 0
          
          puts "DEBUG: Valid price found: #{formatted_price} (raw: #{price_num}, priority: #{priority})"
          found_prices << { price: formatted_price, raw_price: price_num, priority: priority }
        else
          puts "DEBUG: Price #{price_num} out of realistic range, skipping"
        end
      end
    end
    
    puts "DEBUG: Total valid prices found: #{found_prices.length}"
    found_prices.each { |p| puts "DEBUG:   - #{p[:price]} (#{p[:raw_price]}, priority: #{p[:priority]})" }
    
    if found_prices.any?
      # Return the highest priority price, then highest price
      best_price = found_prices.max_by { |p| [p[:priority], p[:raw_price]] }
      puts "DEBUG: Selected best price: #{best_price[:price]}"
      best_price[:price]
    else
      puts "DEBUG: No valid prices found"
      "Price not listed"
    end
  end

  def extract_location_from_posts(posts)
    all_content = posts.map { |post| post[:content].join(' ') }.join(' ')
    
    puts "DEBUG: Location extraction analyzing content: #{all_content[0..200]}..."
    
    states = %w[AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY]
    
    location_patterns = [
      # Specific location indicators with better boundaries
      /(?:located\s+in|location)[:\s]*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*(?:,\s*(?:#{states.join('|')}))?)(?:\s+\d|\s*$|\s*[,.])/i,
      /(?:from)[:\s]*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*(?:,\s*(?:#{states.join('|')}))?)(?:\s+\d|\s*$|\s*[,.])/i,
      # Specific pattern for "Ft Lauderdale" which appears in our content
      /\b(Ft\.?\s+Lauderdale)(?:\s+\d|\s*$|\s*[,.])/i,
      # City, State patterns with word boundaries
      /\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*,\s*(?:#{states.join('|')}))\b/,
      # Specific city names with state abbreviations
      /\b((Fort|Ft\.?|Miami|Tampa|Orlando|Jacksonville|Naples)\s+[A-Z][a-z]*(?:,\s*(?:#{states.join('|')}))?)(?:\s+\d|\s*$|\s*[,.])/i,
      # State abbreviations as fallback
      /\b(#{states.join('|')})\b/
    ]
    
    location_patterns.each_with_index do |pattern, index|
      match = all_content.match(pattern)
      puts "DEBUG: Location pattern #{index + 1} match: #{match ? match[1] : 'none'}"
      if match && match[1] && match[1].strip.length > 1
        location = match[1].strip
        # Clean up common artifacts
        location = location.gsub(/^(From|In|Located in)[:\s]*/i, '')
        location = location.gsub(/\s+/, ' ').strip
        location = location.gsub(/[,.]$/, '') # Remove trailing punctuation
        
        # Validate it's a reasonable location (not just a number or single letter)
        if location.length > 1 && !location.match?(/^\d+$/) && location.match?(/[A-Za-z]/)
          puts "DEBUG: Found location: '#{location}'"
          return location
        end
      end
    end
    
    puts "DEBUG: No location found"
    "Location not specified"
  end

  def extract_year_from_posts(posts)
    all_content = posts.map { |post| post[:content].join(' ') }.join(' ')
    
    # Look for years in boat context
    year_patterns = [
      /(?:^|\s)(19[5-9]\d|20[0-3]\d)(?:\s|$)/,
      /(?:year|model)[:\s]*(19[5-9]\d|20[0-3]\d)/i
    ]
    
    year_patterns.each do |pattern|
      match = all_content.match(pattern)
      if match && match[1]
        year = match[1].to_i
                 # Validate reasonable boat year range
         current_year = Time.now.year
         if year >= 1950 && year <= current_year + 1
           return year.to_s
         end
      end
    end
    
    "Year not specified"
  end

  def extract_size_from_posts(posts)
    all_content = posts.map { |post| post[:content].join(' ') }.join(' ')
    
    size_patterns = [
      /(\d+(?:\.\d+)?)\s*(?:ft|feet|foot|')/i,
      /(\d+)\s*foot/i
    ]
    
    size_patterns.each do |pattern|
      match = all_content.match(pattern)
      if match && match[1]
        size = match[1].to_f
        # Validate reasonable boat size (10-200 feet)
        if size >= 10 && size <= 200
          return "#{size.to_i} ft"
        end
      end
    end
    
    "Size not specified"
  end

  def extract_description_from_posts(posts)
    # Get content from the original post (thread starter)
    original_post = posts.find { |post| post[:is_thread_starter] }
    content_lines = original_post ? original_post[:content] : []
    
    if content_lines.empty?
      # Fallback to first post
      content_lines = posts.first[:content] if posts.any?
    end
    
    return "No description available" if content_lines.empty?
    
    # Find the most descriptive line
    descriptive_lines = content_lines.select do |line|
      line.length > 20 && line.length < 200 &&
      !line.match?(/^(For sale|Located|Price|Call|Contact|PM)/i) &&
      line.match?(/[a-zA-Z]/) &&
      !line.match?(/^\d+$/)
    end
    
    if descriptive_lines.any?
      desc = descriptive_lines.first.strip
      desc = desc[0..97] + "..." if desc.length > 100
      return desc
    end
    
    # Fallback to first substantial line
    substantial_line = content_lines.find { |line| line.length > 10 && line.match?(/[a-zA-Z]/) }
    if substantial_line
      desc = substantial_line.strip
      desc = desc[0..97] + "..." if desc.length > 100
      return desc
    end
    
    "No description available"
  end
end

# New LLM-powered analysis tool for better detail extraction
class LLMBoatAnalyzer < ADK::Tool
  tool_description 'Uses LLM to analyze all posts in a boat thread for comprehensive detail extraction'
  parameter :posts_content
  parameter :thread_info

  private
  
  def perform_execution(params, context)
    begin
      posts_content = params[:posts_content] || params['posts_content']
      thread_info = params[:thread_info] || params['thread_info']
      
      # Format all posts for LLM analysis
      formatted_posts = format_posts_for_analysis(posts_content)
      
      # Create analysis prompt
      analysis_prompt = create_analysis_prompt(formatted_posts, thread_info)
      
      # For now, return a structured analysis - in a real implementation,
      # you would send this to an LLM service
      analysis_result = analyze_with_fallback_logic(formatted_posts, thread_info)
      
      { status: :success, result: analysis_result }
    rescue => e
      { status: :error, error_message: "LLM analysis error: #{e.message}" }
    end
  end

  def format_posts_for_analysis(posts)
    formatted = []
    posts.each do |post|
      post_text = post[:content].join(' ')
      next if post_text.strip.empty?
      
      formatted << {
        post_number: post[:post_number],
        is_original_post: post[:is_thread_starter],
        content: post_text
      }
    end
    formatted
  end

  def create_analysis_prompt(posts, thread_info)
    posts_text = posts.map do |post|
      marker = post[:is_original_post] ? "[ORIGINAL POST]" : "[REPLY ##{post[:post_number]}]"
      "#{marker}\n#{post[:content]}\n"
    end.join("\n---\n")

    <<~PROMPT
      Analyze this boat forum thread to extract key details. Pay special attention to:
      
      1. PRICE: Look for the most recent/current price, including any price reductions mentioned in later posts
      2. LOCATION: Where the boat is located
      3. YEAR: Year of manufacture
      4. SIZE: Length of the boat
      5. DESCRIPTION: Brief description of the boat
      
      Thread Title: #{thread_info[:title]}
      
      Posts Content:
      #{posts_text}
      
      Please extract and return the information in this exact JSON format:
      {
        "price": "extracted price with any reductions noted",
        "location": "boat location",
        "year": "year of boat",
        "size": "boat length",
        "description": "brief description"
      }
    PROMPT
  end

  def analyze_with_fallback_logic(posts, thread_info)
    # Enhanced analysis logic that looks across all posts
    all_content = posts.map { |post| post[:content] }.join(' ')
    
    # Look for price reductions across all posts with enhanced patterns
    price = extract_enhanced_price(posts)
    location = extract_enhanced_location(all_content)
    year = extract_enhanced_year(all_content)
    size = extract_enhanced_size(all_content)
    description = extract_enhanced_description(posts)
    
    {
      price: price,
      location: location,
      year: year,
      size: size,
      description: description
    }
  end

  def extract_enhanced_price(posts)
    # Analyze posts chronologically to find the most recent price
    all_prices = []
    
    posts.each do |post|
      content = post[:content]
      post_number = post[:post_number]
      
      # Enhanced price patterns with context
      price_patterns = [
        # Price reduction patterns (highest priority)
        /(?:price\s*)?(?:reduction|reduced|lowered|dropped|cut)[:\s-]*(?:to\s*)?\$\s*([\d,]+(?:\.\d+)?)\s*(?:million|mil|m|k|obo|firm)?\b/i,
        /(?:new\s*price|updated\s*price|current\s*price)[:\s-]*\$\s*([\d,]+(?:\.\d+)?)\s*(?:million|mil|m|k|obo|firm)?\b/i,
        # Standard price patterns
        /(?:asking|price|for\s*sale)[:\s-]*\$\s*([\d,]+(?:\.\d+)?)\s*(?:million|mil|m|k|obo|firm)?\b/i,
        # Standalone prices with units
        /\$\s*([\d,]+(?:\.\d+)?)\s*(million|mil|m|k)\b/i,
        /\$\s*([\d,]+(?:\.\d+)?)\s*(?:obo|firm|negotiable)\b/i,
        # Large standalone prices
        /\$\s*([1-9]\d{5,}(?:,\d{3})*)\b/,
        /\$\s*(\d{1,3}(?:,\d{3})+)\b/
      ]
      
      price_patterns.each_with_index do |pattern, pattern_index|
        matches = content.scan(pattern)
        matches.each do |match|
          price_str = match.is_a?(Array) ? match[0] : match
          unit = match.is_a?(Array) && match.length > 1 ? match[1] : nil
          
          next unless price_str
          
          # Convert to numeric value
          clean_price = price_str.gsub(/[^\d,.]/, '')
          next if clean_price.empty?
          
          base_price = clean_price.gsub(',', '').to_f
          
          # Apply unit multipliers
          price_num = case unit&.downcase
                     when 'million', 'mil', 'm'
                       base_price * 1_000_000
                     when 'k'
                       base_price * 1_000
                     else
                       base_price
                     end
          
          # Validate realistic boat price range
          if price_num >= 5000 && price_num <= 50_000_000
            # Format price
            formatted_price = if price_num >= 1_000_000
              "$#{(price_num / 1_000_000).round(1)}M"
            elsif price_num >= 1000
              "$#{price_num.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
            else
              "$#{price_num.to_i}"
            end
            
            # Priority: reduction patterns get higher priority, later posts get higher priority
            priority = (pattern_index < 2 ? 100 : 0) + post_number
            
            all_prices << {
              price: formatted_price,
              raw_price: price_num,
              priority: priority,
              post_number: post_number,
              is_reduction: pattern_index < 2
            }
          end
        end
      end
    end
    
    if all_prices.any?
      # Sort by priority (reductions first, then by post number for recency)
      best_price = all_prices.max_by { |p| p[:priority] }
      reduction_note = best_price[:is_reduction] ? " (REDUCED)" : ""
      "#{best_price[:price]}#{reduction_note}"
    else
      "Price not listed"
    end
  end

  def extract_enhanced_location(content)
    states = %w[AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY]
    
    location_patterns = [
      /(?:located\s+(?:in|at)|location|boat\s+(?:is\s+)?(?:in|at))[:\s]*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*(?:,\s*(?:#{states.join('|')}))?)(?:\s|$|[,.])/i,
      /(?:from|in)[:\s]*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*(?:,\s*(?:#{states.join('|')}))?)(?:\s|$|[,.])/i,
      /\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*,\s*(?:#{states.join('|')}))\b/,
      /\b((Fort|Ft\.?|Miami|Tampa|Orlando|Jacksonville|Naples|Key\s+West)\s*[A-Z][a-z]*(?:,\s*(?:#{states.join('|')}))?)(?:\s|$|[,.])/i
    ]
    
    location_patterns.each do |pattern|
      match = content.match(pattern)
      if match && match[1] && match[1].strip.length > 1
        location = match[1].strip.gsub(/^(From|In|Located in)[:\s]*/i, '').gsub(/\s+/, ' ').strip
        return location if location.length > 1 && location.match?(/[A-Za-z]/)
      end
    end
    
    "Location not specified"
  end

  def extract_enhanced_year(content)
    year_patterns = [
      /(?:^|\s)(19[5-9]\d|20[0-3]\d)(?:\s|$)/,
      /(?:year|model|built)[:\s]*(19[5-9]\d|20[0-3]\d)/i
    ]
    
    year_patterns.each do |pattern|
      match = content.match(pattern)
      if match && match[1]
        year = match[1].to_i
        current_year = Time.now.year
        return year.to_s if year >= 1950 && year <= current_year + 1
      end
    end
    
    "Year not specified"
  end

  def extract_enhanced_size(content)
    size_patterns = [
      /(\d+(?:\.\d+)?)\s*(?:ft|feet|foot|')/i,
      /(\d+)\s*foot/i
    ]
    
    size_patterns.each do |pattern|
      match = content.match(pattern)
      if match && match[1]
        size = match[1].to_f
        return "#{size.to_i} ft" if size >= 10 && size <= 200
      end
    end
    
    "Size not specified"
  end

  def extract_enhanced_description(posts)
    # Get the original post content
    original_post = posts.find { |post| post[:is_original_post] }
    content_lines = original_post ? original_post[:content].split(/[.!?]+/) : []
    
    if content_lines.empty? && posts.any?
      content_lines = posts.first[:content].split(/[.!?]+/)
    end
    
    return "No description available" if content_lines.empty?
    
    # Find the most descriptive sentence
    descriptive_sentences = content_lines.select do |sentence|
      sentence = sentence.strip
      sentence.length > 30 && sentence.length < 200 &&
      !sentence.match?(/^(For sale|Located|Price|Call|Contact|PM|Email)/i) &&
      sentence.match?(/[a-zA-Z]/) &&
      !sentence.match?(/^\d+$/) &&
      sentence.split.length > 5
    end
    
    if descriptive_sentences.any?
      desc = descriptive_sentences.first.strip
      desc = desc[0..97] + "..." if desc.length > 100
      return desc
    end
    
    # Fallback to first substantial sentence
    substantial_sentence = content_lines.find { |sentence| sentence.strip.length > 20 && sentence.strip.match?(/[a-zA-Z]/) }
    if substantial_sentence
      desc = substantial_sentence.strip
      desc = desc[0..97] + "..." if desc.length > 100
      return desc
    end
    
    "No description available"
  end
end

ADK::GlobalToolManager.register_tool(BoatThreadParser)
ADK::GlobalToolManager.register_tool(BoatDetailParser)
ADK::GlobalToolManager.register_tool(LLMBoatAnalyzer)

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