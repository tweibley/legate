---
id: 35
title: 'Dashboard Homepage Refresh'
status: pending
priority: low
feature: Web UI Visual Enhancement
dependencies:
  - 29
  - 32
assigned_agent: null
created_at: "2025-12-07T04:44:19Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Update index.slim dashboard cards with accent borders and enhanced visual hierarchy.

## Details

### Update index.slim Cards

Add dashboard-card class and specific accent classes to each card:

```slim
/ Current structure (to be modified):
.columns.is-centered.is-multiline
  .column.is-one-third
    .card.has-text-centered
      .card-content
        ...

/ Updated structure:
.columns.is-centered.is-multiline
  .column.is-one-third
    .card.dashboard-card.agents-card.has-text-centered
      .card-content
        span.icon.is-large.has-text-danger.mb-3
          i.fas.fa-robot.fa-3x
        ...

  .column.is-one-third
    .card.dashboard-card.tools-card.has-text-centered
      .card-content
        span.icon.is-large.has-text-info.mb-3
          i.fas.fa-tools.fa-3x
        ...

  .column.is-one-third
    .card.dashboard-card.auth-card.has-text-centered
      .card-content
        span.icon.is-large.has-text-warning.mb-3
          i.fas.fa-shield-alt.fa-3x
        ...

  .column.is-one-third
    .card.dashboard-card.docs-card.has-text-centered
      .card-content
        span.icon.is-large.has-text-success.mb-3
          i.fas.fa-book.fa-3x
        ...
```

### Icon Color Updates

Use CSS variables for icon colors to work in dark mode:

```scss
// Dashboard card icons
.dashboard-card {
  .icon.has-text-danger i { color: var(--color-accent); }
  .icon.has-text-info i { color: var(--color-info); }
  .icon.has-text-warning i { color: var(--color-warning); }
  .icon.has-text-success i { color: var(--color-success); }
}

// Alternatively, update icon classes in slim to use inline styles or custom classes
// that reference CSS variables
```

### Update Icon Selection

Consider updating icons for better representation:
- Agents: `fa-robot` (already good)
- Tools: `fa-wrench` or `fa-toolbox` (more specific than `fa-tools`)
- Authentication: `fa-key` or `fa-lock` (more modern than shield)
- Documentation: `fa-book-open` (more inviting than closed book)

### Welcome Header Enhancement

```slim
.content.has-text-centered.mb-6
  h1.title.is-2 
    | Welcome to 
    span.has-text-primary Ruby ADK
  p.subtitle.is-4.has-text-grey Agent Development Kit for Ruby
```

### Dark Mode Considerations

Ensure card backgrounds and text work in dark mode:

```scss
[data-theme="dark"] {
  .dashboard-card {
    background: var(--color-bg-secondary);
    
    .title {
      color: var(--color-text-primary);
    }
    
    p {
      color: var(--color-text-secondary);
    }
  }
}
```

## Test Strategy

1. Start web server and navigate to homepage
2. Verify each card has colored accent bar at top:
   - Agents: Ruby red
   - Tools: Blue (info)
   - Authentication: Yellow/amber (warning)
   - Documentation: Green (success)
3. Hover over cards - verify lift animation works
4. Switch to dark mode - verify cards are visible and readable
5. Verify icons are visible in both themes
6. Click each card - verify navigation works
7. Test on mobile view - verify cards stack properly
8. Verify welcome header displays correctly

## Agent Notes

Files to modify:
- `lib/adk/web/views/index.slim`
- `lib/adk/web/public/styles/main.scss` (if additional dark mode styles needed)

