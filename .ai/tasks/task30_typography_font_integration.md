---
id: 30
title: 'Typography & Font Integration'
status: pending
priority: high
feature: Web UI Visual Enhancement
dependencies:
  - 29
assigned_agent: null
created_at: "2025-12-07T04:44:19Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Add Google Fonts (Inter, JetBrains Mono) to layout.slim and update main.scss to apply fonts throughout the UI with proper fallbacks.

## Details

- Add Google Fonts link to layout.slim head section:
  ```html
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
  ```
- Update body font-family in main.scss:
  ```scss
  body {
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
  }
  ```
- Update code/monospace elements:
  ```scss
  code, pre, .CodeMirror {
    font-family: 'JetBrains Mono', 'Fira Code', monospace;
  }
  ```
- Add `-webkit-font-smoothing: antialiased` for better rendering
- Update heading styles with `letter-spacing: -0.025em` for tighter headlines
- Ensure font weights are properly applied (400 body, 500 buttons, 600 headers, 700 titles)
- Use CSS variables for font-family if beneficial for theming

## Test Strategy

1. Start the web server and open the UI in a browser
2. Open browser DevTools > Network tab and verify Google Fonts are loading
3. Inspect body text - should show "Inter" in computed styles
4. Inspect code blocks - should show "JetBrains Mono" in computed styles
5. Verify headings have tighter letter-spacing
6. Check no layout shifts when fonts load (display=swap)
7. Test on different pages (Agents, Tools, Documentation)

## Agent Notes

Files to modify:
- `lib/adk/web/views/layout.slim`
- `lib/adk/web/public/styles/main.scss`

