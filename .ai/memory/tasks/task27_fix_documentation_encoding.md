---
id: 27
title: 'Fix Documentation Encoding Error'
status: completed
priority: high
feature: Web UI Bug Fixes
dependencies:
  - 26
assigned_agent: null
created_at: "2025-12-05T05:21:43Z"
started_at: "2025-12-05T05:31:53Z"
completed_at: "2025-12-05T05:33:38Z"
error_log: null
---

## Description

Fix the "invalid byte sequence in US-ASCII" error in documentation_routes.rb by properly handling UTF-8 encoding when scanning documentation files.

## Details

### Error Details

From server logs:
```
ERROR: Error scanning documentation directory: invalid byte sequence in US-ASCII
ERROR: /Users/tweibley/adk-ruby/lib/adk/web/routes/documentation_routes.rb:140:in 'Regexp#match'
```

### Root Cause

The documentation scanner uses regex matching on file contents without explicitly handling file encoding. When documentation files contain non-ASCII characters (UTF-8), the regex match fails.

### Solution

1. Force UTF-8 encoding when reading documentation files
2. Handle encoding errors gracefully with a fallback
3. Log a warning if a file has encoding issues instead of failing

### Files to Modify

- `lib/adk/web/routes/documentation_routes.rb` - Add encoding handling around line 140

### Code Change

Around line 140 in `documentation_routes.rb`, when reading file content for regex matching:

```ruby
# Before
content = File.read(file_path)
content.match(pattern)

# After
content = File.read(file_path, encoding: 'UTF-8')
content.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
content.match(pattern)
```

Or wrap in a begin/rescue block to handle encoding errors gracefully.

## Test Strategy

1. Start the web UI: `bundle exec adk web start`
2. Navigate to http://localhost:4567/docs
3. Verify the documentation page loads without errors
4. Check server logs for any encoding-related errors
5. Verify all documentation categories display correctly
6. Create a test documentation file with non-ASCII characters to verify handling

