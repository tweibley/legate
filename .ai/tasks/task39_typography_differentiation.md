---
id: 39
title: 'Typography Differentiation'
status: completed
priority: high
feature: Web UI Phase 2 Refinement
dependencies: []
assigned_agent: null
created_at: "2025-12-07T05:31:20Z"
started_at: "2025-12-07T05:35:00Z"
completed_at: "2025-12-07T05:38:10Z"
error_log: null
---

## Description

Replace the generic Inter font with a distinctive typeface (DM Sans, Geist, or Satoshi) to differentiate Ruby ADK from generic admin dashboards and establish a unique visual identity.

## Details

- Update Google Fonts link in `layout.slim` to load DM Sans (or chosen alternative) instead of Inter
- Modify `--font-sans` CSS variable in `main.scss` to use the new font with appropriate fallbacks
- Ensure font weights 400, 500, 600, 700 are loaded for proper hierarchy
- Keep JetBrains Mono for code/monospace elements unchanged
- Test font rendering in both light and dark modes
- Verify no layout shifts occur during font loading (font-display: swap)

### Font Options (choose one):

1. **DM Sans** - Geometric with personality, good x-height
   - `https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap`
   
2. **Satoshi** - Contemporary with character (may need self-hosting)

3. **Geist** - Modern, technical feel (Vercel's font, may need self-hosting)

### Files to modify:

- `lib/adk/web/views/layout.slim` - Google Fonts link
- `lib/adk/web/public/styles/main.scss` - `--font-sans` variable

## Test Strategy

1. Load the application in a browser
2. Verify the new font is applied to headings and body text
3. Confirm JetBrains Mono still applies to code elements
4. Check DevTools Network tab to ensure font loads without errors
5. Test in both Chrome and Firefox for rendering consistency
6. Visually compare before/after to confirm differentiation from Inter

