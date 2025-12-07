# Task 46: Breadcrumb Navigation Component

## Status: Pending

## Priority: High

## Description

Add breadcrumb navigation to detail pages to help users understand their location within the application hierarchy and navigate back easily.

## Acceptance Criteria

- [ ] Breadcrumb component displays on agent detail page (e.g., "Agents > cat facts only")
- [ ] Breadcrumb component displays on tool detail page (e.g., "Tools > calculator")
- [ ] Parent links are clickable and navigate to list pages
- [ ] Current page shown as non-linked text
- [ ] Styled consistently with Ruby ADK theme (both light and dark mode)
- [ ] Uses Bulma's breadcrumb component with custom styling

## Implementation Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/adk/web/views/layout.slim` | Add breadcrumb container in main content area |
| `lib/adk/web/views/agent.slim` | Pass breadcrumb data to layout |
| `lib/adk/web/views/tool.slim` | Pass breadcrumb data to layout (if exists) |
| `lib/adk/web/public/styles/main.scss` | Breadcrumb styling for both themes |

### Breadcrumb Structure

```slim
/ In layout.slim or as partial
- if @breadcrumbs && @breadcrumbs.any?
  nav.breadcrumb.mb-4(aria-label="breadcrumbs")
    ul
      - @breadcrumbs.each_with_index do |crumb, index|
        - if index == @breadcrumbs.length - 1
          li.is-active
            a(href="#" aria-current="page")= crumb[:label]
        - else
          li
            a(href=crumb[:path])= crumb[:label]
```

### Route Updates

```ruby
# In agent detail route
@breadcrumbs = [
  { label: 'Agents', path: '/agents' },
  { label: agent_name, path: nil }
]
```

### CSS Styling

```scss
/* Breadcrumb styling */
.breadcrumb {
  background: transparent;
  padding: 0;
  
  li + li::before {
    color: var(--color-text-muted);
  }
  
  a {
    color: var(--color-primary);
    
    &:hover {
      color: var(--color-primary-dark);
    }
  }
  
  li.is-active a {
    color: var(--color-text-secondary);
  }
}
```

## Related

- Plan: [Web UI Phase 3 - UX Polish](../plans/features/web-ui-phase3-ux-polish-plan.md)
- User Story: US-P3-001

