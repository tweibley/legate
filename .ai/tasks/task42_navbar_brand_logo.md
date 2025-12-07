---
id: 42
title: 'Navbar Brand Logo'
status: completed
priority: medium
feature: Web UI Phase 2 Refinement
dependencies: []
assigned_agent: null
created_at: "2025-12-07T05:31:20Z"
started_at: "2025-12-07T05:35:00Z"
completed_at: "2025-12-07T05:38:10Z"
error_log: null
---

## Description

Add a visual Ruby gem icon next to the "Ruby ADK" text in the navbar to strengthen brand identity and create a more memorable visual anchor.

## Details

- Add a gem/diamond icon from Font Awesome next to "Ruby ADK" in navbar
- Use `fa-gem` (solid gem icon) which represents a ruby/gem
- Apply ruby red color to the icon to reinforce brand
- Ensure icon scales appropriately with navbar
- Icon should be visible in both light and dark modes

### Font Awesome icon options:

1. `fa-gem` - Solid gem shape (recommended)
2. `fa-diamond` - Alternative diamond shape

### Implementation in layout.slim:

```slim
a.navbar-item href="/"
  span.icon.has-text-danger.mr-2
    i.fas.fa-gem
  strong.has-text-link Ruby ADK
```

Or with custom color:

```slim
a.navbar-item href="/"
  span.icon.mr-2 style="color: hsl(348, 83%, 47%);"
    i.fas.fa-gem
  strong.has-text-link Ruby ADK
```

### Files to modify:

- `lib/adk/web/views/layout.slim` - Navbar brand section

### CSS consideration (optional):

Add subtle animation on hover:

```scss
.navbar-brand .icon {
  transition: transform var(--transition-fast);
  
  &:hover {
    transform: rotate(15deg) scale(1.1);
  }
}
```

## Test Strategy

1. Load the application and verify gem icon appears in navbar
2. Check icon color matches ruby/brand red
3. Test in both light and dark modes for visibility
4. Verify icon doesn't break navbar layout on mobile
5. Check hover state if animation is added

