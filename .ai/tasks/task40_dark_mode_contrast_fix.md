---
id: 40
title: 'Dark Mode Contrast Fix'
status: pending
priority: high
feature: Web UI Phase 2 Refinement
dependencies: []
assigned_agent: null
created_at: "2025-12-07T05:31:20Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Fix the accessibility issue where muted text in dark mode (#6b7280) has insufficient contrast against dark backgrounds (#1a1f26). Upgrade to #9ca3af for WCAG AA compliance.

## Details

- Locate `--color-text-muted` in the dark mode section of `main.scss`
- Change value from `#6b7280` to `#9ca3af`
- Verify the contrast ratio meets WCAG AA (minimum 4.5:1 for normal text)
- Review all uses of `--color-text-muted` in dark mode to ensure readability
- Check secondary labels, placeholders, and helper text throughout the UI

### Contrast calculation:

- Background: #1a1f26 
- Old muted: #6b7280 → Contrast ratio ~3.5:1 (FAILS AA)
- New muted: #9ca3af → Contrast ratio ~5.2:1 (PASSES AA)

### Files to modify:

- `lib/adk/web/public/styles/main.scss` - Dark mode variables section

## Test Strategy

1. Switch to dark mode in the application
2. Navigate to pages with muted/secondary text (agent descriptions, help text, labels)
3. Visually confirm text is readable without straining
4. Use browser DevTools or a contrast checker tool to verify ratio ≥4.5:1
5. Test on Agents list, Tools page, and Documentation pages

