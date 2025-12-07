# Task 47: Navbar Active State Indicator

## Status: Pending

## Priority: High

## Description

Add a visible indicator for the currently active page in the navigation bar to help users understand their current location in the application.

## Acceptance Criteria

- [ ] Active nav link has visible underline or background highlight
- [ ] Works in both light and dark modes
- [ ] Indicator matches Ruby ADK brand colors
- [ ] Smooth transition when switching pages
- [ ] Works for all main nav items: Agents, Tools, Authentication, Documentation

## Implementation Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/adk/web/views/layout.slim` | Add active class logic to nav items |
| `lib/adk/web/public/styles/main.scss` | Active state styling |

### Slim Template Update

```slim
/ In layout.slim navbar
.navbar-item
  a.navbar-link(href="/agents" class=(request.path_info.start_with?('/agents') ? 'is-active' : ''))
    | Agents
```

### CSS Styling

```scss
/* Navbar active state */
.navbar-link.is-active,
.navbar-item a.is-active {
  position: relative;
  color: var(--color-primary) !important;
  
  &::after {
    content: '';
    position: absolute;
    bottom: 0;
    left: 0.75rem;
    right: 0.75rem;
    height: 2px;
    background: var(--color-primary);
    border-radius: 1px;
  }
}

/* Dark mode */
[data-theme="dark"] .navbar-link.is-active,
[data-theme="dark"] .navbar-item a.is-active {
  color: var(--color-primary) !important;
}
```

## Related

- Plan: [Web UI Phase 3 - UX Polish](../plans/features/web-ui-phase3-ux-polish-plan.md)

