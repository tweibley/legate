---
id: 29
title: 'CSS Variable System Foundation'
status: pending
priority: critical
feature: Web UI Visual Enhancement
dependencies: []
assigned_agent: null
created_at: "2025-12-07T04:44:19Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Establish the CSS variable system in main.scss for comprehensive theming support. Define color palette, shadows, radii, and transitions as CSS custom properties.

## Details

- Add CSS custom properties (variables) to `:root` in main.scss
- Define brand colors:
  - Primary: Indigo `hsl(230, 70%, 55%)`
  - Accent: Ruby red `hsl(354, 80%, 50%)`
- Define semantic colors:
  - Success: `hsl(152, 68%, 40%)`
  - Warning: `hsl(38, 92%, 50%)`
  - Danger: `hsl(0, 72%, 51%)`
  - Info: `hsl(201, 96%, 46%)`
- Define neutral colors for light mode:
  - `--color-bg-primary: #f4f6f8`
  - `--color-bg-secondary: #ffffff`
  - `--color-bg-tertiary: #eef1f5`
  - `--color-text-primary: #1a202c`
  - `--color-text-secondary: #4a5568`
  - `--color-text-muted: #718096`
  - `--color-border: #e2e8f0`
- Define shadow variables:
  - `--shadow-sm`, `--shadow-md`, `--shadow-lg`, `--shadow-hover`
- Define transition variables:
  - `--transition-fast: 150ms ease`
  - `--transition-normal: 250ms ease`
- Define radius variables:
  - `--radius-sm: 6px`, `--radius-md: 10px`, `--radius-lg: 14px`
- Update existing hardcoded color values to use CSS variables where applicable
- Ensure backward compatibility - existing styles should still work

## Test Strategy

1. Run `bin/compile-sass` to compile SCSS to CSS
2. Start the web server and verify the UI loads without errors
3. Check browser DevTools to confirm CSS variables are defined in `:root`
4. Verify existing page layouts and colors remain functional
5. Check no console errors related to CSS

## Agent Notes

Files to modify:
- `lib/adk/web/public/styles/main.scss`

