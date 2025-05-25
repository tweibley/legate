---
id: 24
title: 'Boats-for-Sale Example Agent with Puppeteer MCP'
status: inprogress
priority: medium
feature: Example Agents
dependencies: []
assigned_agent: claude
created_at: "2025-05-25T04:18:02Z"
started_at: "2025-05-25T04:22:42Z"
completed_at: null
error_log: null
---

## Description

Create a comprehensive example agent that demonstrates web scraping capabilities using the Puppeteer MCP server to extract boat listing information from The Hull Truth forum.

## Details

### Agent Configuration
- **Agent Type**: Sequential agent that processes boat listings in order
- **Target URL**: https://www.thehulltruth.com/boats-sale-17/
- **File Location**: `examples/boats-for-sale.rb`
- **Agent Name**: `boats_for_sale_agent`

### Core Functionality
- **Navigate to Forum**: Use Puppeteer to navigate to The Hull Truth boats for sale forum
- **Extract Thread List**: Identify and extract the first 5 "Normal" thread listings (excluding sticky/pinned posts)
- **Visit Individual Threads**: Navigate to each thread to extract detailed information
- **Data Extraction**: Extract the following information for each boat:
  - Thread title (boat name/description)
  - Asking price (if available)
  - Thread URL
  - Post date/time
  - Location (if mentioned)
  - Brief description/summary
- **Output Format**: Display results in a formatted table for easy reading

### Puppeteer MCP Integration
- **MCP Server Configuration**: Configure the agent to use the Puppeteer MCP server
- **Tool Usage**: Utilize all relevant Puppeteer tools:
  - `puppeteer_navigate` - Navigate to pages
  - `puppeteer_screenshot` - Take screenshots for debugging
  - `puppeteer_click` - Click on thread links
  - `puppeteer_fill` - Fill forms if needed
  - `puppeteer_evaluate` - Execute JavaScript to extract data
  - `puppeteer_hover` - Hover over elements if needed

### Sequential Processing
- **Step 1**: Navigate to the main forum page
- **Step 2**: Extract list of thread URLs and titles
- **Step 3**: Filter for "Normal" threads (exclude sticky/announcements)
- **Step 4**: Limit to first 5 threads
- **Step 5**: For each thread:
  - Navigate to the thread
  - Extract boat details and pricing information
  - Store the data
- **Step 6**: Format and display results in a table

### Error Handling
- **Navigation Errors**: Handle cases where pages don't load
- **Missing Data**: Gracefully handle threads without pricing information
- **Rate Limiting**: Implement appropriate delays between requests
- **Timeout Handling**: Set reasonable timeouts for page loads

### Data Structure
Create a structured approach to store and format the extracted data:
```ruby
boat_listing = {
  title: "Thread title",
  price: "Asking price or 'Not specified'",
  url: "Full thread URL",
  date: "Post date",
  location: "Location if available",
  summary: "Brief description"
}
```

### Output Format
Display results in a formatted table:
```
| Boat | Price | Location | Date | URL |
|------|-------|----------|------|-----|
| ... | ... | ... | ... | ... |
```

### MCP Server Configuration
- **Server Type**: stdio
- **Command**: Path to Puppeteer MCP server executable
- **Tools**: All Puppeteer tools should be available to the agent

### Example Usage
The agent should be usable via:
1. **Direct execution**: `ruby examples/boats-for-sale.rb`
2. **ADK CLI**: Integration with the ADK command-line interface
3. **Web UI**: Accessible through the ADK web interface

### Documentation
- **Inline Comments**: Comprehensive code documentation
- **Usage Examples**: Clear examples of how to run the agent
- **MCP Setup**: Instructions for configuring the Puppeteer MCP server
- **Troubleshooting**: Common issues and solutions

### Ethical Considerations
- **Respectful Scraping**: Implement appropriate delays and respect robots.txt
- **Data Usage**: Only extract publicly available information
- **Rate Limiting**: Avoid overwhelming the target website
- **User-Agent**: Use appropriate user-agent strings

## Test Strategy

### Manual Testing
1. **MCP Server Setup**: Verify Puppeteer MCP server is properly configured and accessible
2. **Agent Execution**: Run the agent and verify it successfully:
   - Navigates to The Hull Truth forum
   - Extracts thread listings
   - Visits individual threads
   - Extracts boat information
   - Displays results in table format
3. **Error Scenarios**: Test behavior when:
   - Website is unavailable
   - Threads have no pricing information
   - Navigation fails
4. **Data Validation**: Verify extracted data is accurate and properly formatted

### Integration Testing
1. **ADK Integration**: Test agent works within the ADK framework
2. **Tool Availability**: Verify all Puppeteer tools are accessible
3. **Sequential Processing**: Confirm agent processes threads in correct order
4. **Output Format**: Validate table output is properly formatted and readable

### Performance Testing
1. **Execution Time**: Measure total time to process 5 boat listings
2. **Memory Usage**: Monitor memory consumption during execution
3. **Network Efficiency**: Verify appropriate delays between requests

### Documentation Testing
1. **Setup Instructions**: Follow documentation to set up and run the agent
2. **Example Verification**: Verify all provided examples work correctly
3. **Troubleshooting Guide**: Test common troubleshooting scenarios 