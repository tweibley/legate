# Task 53: Status Badge Pulse Animation

## Status: Pending

## Priority: Medium

## Description

Add a subtle breathing/pulse animation to "Running" status badges to indicate active state, while keeping "Stopped" badges static.

## Acceptance Criteria

- [ ] "Running" badges have subtle pulse animation
- [ ] "Stopped" badges remain static
- [ ] Animation is subtle, not distracting
- [ ] Works in both light and dark modes
- [ ] Respects prefers-reduced-motion preference
- [ ] Applied to agent list and agent detail status badges

## Implementation Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/adk/web/public/styles/main.scss` | Pulse animation CSS |
| `lib/adk/web/views/_agent_row.slim` | Add animation class to running badges |
| `lib/adk/web/views/_agent_status_controls.slim` | Add animation class |

### CSS Animation

```scss
/* Status Badge Animations */
@keyframes status-pulse {
  0%, 100% {
    opacity: 1;
    box-shadow: 0 0 0 0 rgba(var(--color-success-rgb), 0.4);
  }
  50% {
    opacity: 0.9;
    box-shadow: 0 0 0 4px rgba(var(--color-success-rgb), 0);
  }
}

.tag.is-success.is-running {
  animation: status-pulse 2s ease-in-out infinite;
}

/* Respect reduced motion preference */
@media (prefers-reduced-motion: reduce) {
  .tag.is-success.is-running {
    animation: none;
  }
}

/* Add RGB variable for box-shadow */
:root {
  --color-success-rgb: 34, 197, 94;
}

[data-theme="dark"] {
  --color-success-rgb: 74, 222, 128;
}
```

### Template Update

```slim
/ In _agent_row.slim
span.tag.is-medium(class="#{is_running ? 'is-success is-running' : 'is-danger'}")
  span.icon.is-small
    i(class="fas #{is_running ? 'fa-check-circle' : 'fa-stop-circle'}")
  span.ml-1 = is_running ? 'Running' : 'Stopped'
```

## Related

- Plan: [Web UI Phase 3 - UX Polish](../plans/features/web-ui-phase3-ux-polish-plan.md)

