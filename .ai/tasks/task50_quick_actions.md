# Task 50: Dashboard Quick Action Buttons

## Status: Pending

## Priority: High

## Dependencies: Task 49

## Description

Add small "+" action buttons in the footer of dashboard cards to allow quick agent/tool creation without navigating away from the dashboard.

## Acceptance Criteria

- [ ] Agents card has "+" button that opens agent creation
- [ ] Tools card has link/action appropriate for tools context
- [ ] Buttons are subtle but discoverable
- [ ] Tooltip shows action description on hover
- [ ] Works in both light and dark modes
- [ ] Mobile-friendly touch target size

## Implementation Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/adk/web/views/index.slim` | Add quick action buttons to cards |
| `lib/adk/web/public/styles/main.scss` | Quick action button styling |

### Card Footer with Quick Action

```slim
.card.dashboard-card.agents-card
  .card-content
    / ... existing content ...
  .card-footer
    a.card-footer-item(href="/agents")
      span.icon
        i.fas.fa-arrow-right
      span View Agents
    a.card-footer-item.quick-action(href="/agents" onclick="openCreateAgentModal(); return false;" title="Create new agent")
      span.icon
        i.fas.fa-plus
```

### CSS Styling

```scss
/* Quick Action Buttons */
.dashboard-card .card-footer {
  border-top: 1px solid var(--color-border-light);
  
  .card-footer-item {
    padding: 0.75rem;
    color: var(--color-text-secondary);
    transition: all var(--transition-fast);
    
    &:hover {
      background: var(--color-bg-tertiary);
      color: var(--color-primary);
    }
    
    &.quick-action {
      flex: 0 0 auto;
      width: 48px;
      border-left: 1px solid var(--color-border-light);
      
      &:hover {
        background: var(--color-primary-light);
        color: var(--color-primary);
      }
    }
  }
}
```

## Related

- Plan: [Web UI Phase 3 - UX Polish](../plans/features/web-ui-phase3-ux-polish-plan.md)
- Designer Feedback: "Add small direct action buttons to reduce friction"

