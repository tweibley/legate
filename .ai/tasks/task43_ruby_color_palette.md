---
id: 43
title: 'Ruby-Inspired Color Palette'
status: completed
priority: medium
feature: Web UI Phase 2 Refinement
dependencies: [39, 40]
assigned_agent: null
created_at: "2025-12-07T05:31:20Z"
started_at: "2025-12-07T05:35:00Z"
completed_at: "2025-12-07T05:38:10Z"
error_log: null
---

## Description

Shift the primary color from generic indigo to a ruby red to align with the "Ruby ADK" brand identity. Add warm gold as a complementary accent color.

## Details

- Update `--color-primary` from indigo (hsl 230) to ruby red (hsl ~348)
- Update related primary variants (dark, light) 
- Add/update `--color-accent` to warm gold (hsl ~38)
- Preserve existing semantic colors (success, warning, danger, info)
- Update both light mode and dark mode palettes
- Review all primary color usages to ensure they still look good

### New color values:

```scss
:root {
  /* --- Brand Colors (Ruby Theme) --- */
  --color-primary: hsl(348, 83%, 47%);           /* Ruby red - main actions */
  --color-primary-dark: hsl(348, 83%, 40%);      /* Ruby darker - hover */
  --color-primary-light: hsl(348, 83%, 95%);     /* Ruby tint - backgrounds */
  --color-accent: hsl(38, 92%, 50%);             /* Warm gold - brand accent */
  --color-accent-light: hsl(38, 92%, 94%);       /* Gold tint */
}

[data-theme="dark"] {
  --color-primary: hsl(348, 80%, 60%);           /* Lighter ruby for dark mode */
  --color-primary-dark: hsl(348, 80%, 50%);
  --color-primary-light: hsl(348, 50%, 20%);
  --color-accent: hsl(38, 92%, 55%);
  --color-accent-light: hsl(38, 50%, 20%);
}
```

### Areas affected:

- Buttons (`.button.is-link`, `.button.is-primary`)
- Links and active states
- Navbar brand text color
- Focus rings and outlines
- Active tab indicators
- Dashboard card accent borders (agents card already uses accent/red)

### Files to modify:

- `lib/adk/web/public/styles/main.scss` - CSS variables section

### Consideration:

The agents card already uses `--color-accent` (ruby red) for its top border. With this change, we may want to swap the accent colors - agents card could use the new gold accent while primary actions use ruby red.

## Test Strategy

1. Compile SCSS and load application
2. Check primary buttons appear in ruby red
3. Verify links and interactive elements use new primary color
4. Test hover states maintain proper contrast
5. Navigate through all pages to check color consistency
6. Verify dark mode primary colors are appropriately adjusted
7. Ensure semantic colors (success green, danger red, etc.) are unchanged

