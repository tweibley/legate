---
id: 24
title: 'Boats-for-Sale Example Agent with Puppeteer MCP'
status: completed
priority: medium
feature: Example Agents
dependencies: []
assigned_agent: claude
created_at: "2025-05-25T04:18:02Z"
started_at: "2025-05-25T04:22:42Z"
completed_at: "2025-12-05T04:22:00Z"
error_log: null
---

## Description

Create a comprehensive example agent that demonstrates web scraping capabilities using the Puppeteer MCP server to extract boat listing information from The Hull Truth forum.

**Update (Dec 2025):** Due to heavy Cloudflare bot protection, the agent now includes logic to detect challenge pages and prompt the user to manually solve the CAPTCHA in the headed browser window.

## Details

### Agent Configuration
- **Agent Type**: Sequential agent that processes boat listings in order
- **Target URL**: https://www.thehulltruth.com/boats-sale-17/
- **File Location**: `examples/boats-for-sale-actually-working.rb`
- **Agent Name**: `actually_working_boats_scraper`

### Core Functionality
- **Navigate to Forum**: Use Playwright (via MCP) to navigate to The Hull Truth boats for sale forum
- **Manual Verification**: Pauses execution if Cloudflare challenge is detected, allowing user to solve it.
- **Extract Thread List**: Identify and extract the first 5 "Normal" thread listings (excluding sticky/pinned posts)
- **Visit Individual Threads**: Navigate to each thread to extract detailed information
- **Data Extraction**: Extract the following information for each boat:
  - Thread title
  - Asking price
  - Thread URL
  - Location
  - Year
  - Size
  - Brief description
- **Output Format**: Display results in a formatted table/list

### Puppeteer/Playwright MCP Integration
- **MCP Server Configuration**: configured to use `@playwright/mcp` with a realistic User-Agent.
- **Tool Usage**: Utilize `browser_navigate` and `browser_snapshot`.

### Sequential Processing
- **Step 1**: Navigate to the main forum page (Handle CAPTCHA)
- **Step 2**: Extract list of thread URLs and titles using `BoatThreadParser`
- **Step 3**: For each thread:
  - Navigate to the thread (Handle CAPTCHA)
  - Extract boat details using `BoatDetailParser` and `LLMBoatAnalyzer`
- **Step 4**: Format and display results

### Data Structure
```ruby
boat_listing = {
  title: "Thread title",
  price: "$123,456",
  url: "...",
  location: "...",
  year: "...",
  size: "...",
  description: "..."
}
```
