# Task 52: Skeleton Loading Components

## Status: Complete

## Priority: Medium

## Dependencies: Task 46

## Description

Replace "Loading..." text placeholders with skeleton UI components featuring animated shimmer effects for a more polished loading experience.

## Acceptance Criteria

- [x] Skeleton components for table rows
- [x] Skeleton components for card content
- [x] Skeleton components for text blocks
- [x] Animated shimmer/pulse effect
- [x] Works in both light and dark modes
- [x] Replaces existing "Loading..." text in key areas
- [x] Accessible (respects prefers-reduced-motion)

## Implementation Details

### Files to Create/Modify

| File | Changes |
|------|---------|
| `lib/adk/web/views/_skeleton.slim` | New: Skeleton component partials |
| `lib/adk/web/public/styles/main.scss` | Skeleton CSS animations |
| Various views | Replace Loading text with skeleton partials |

### Skeleton Partial

```slim
/ _skeleton.slim
/ Usage: == slim :_skeleton, locals: { type: :table_row, count: 3 }

- type ||= :text
- count ||= 1

- count.times do
  - case type
  - when :table_row
    tr.skeleton-row
      td: .skeleton.skeleton-text
      td: .skeleton.skeleton-text.skeleton-short
      td: .skeleton.skeleton-text
      td: .skeleton.skeleton-badge
  - when :card
    .skeleton-card
      .skeleton.skeleton-title
      .skeleton.skeleton-text
      .skeleton.skeleton-text.skeleton-short
  - when :text
    .skeleton.skeleton-text
```

### CSS Styling

```scss
/* Skeleton Loading Components */
.skeleton {
  background: linear-gradient(
    90deg,
    var(--color-bg-tertiary) 0%,
    var(--color-bg-secondary) 50%,
    var(--color-bg-tertiary) 100%
  );
  background-size: 200% 100%;
  animation: skeleton-shimmer 1.5s ease-in-out infinite;
  border-radius: var(--radius-sm);
}

@keyframes skeleton-shimmer {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}

.skeleton-text {
  height: 1rem;
  margin-bottom: 0.5rem;
  
  &.skeleton-short {
    width: 60%;
  }
}

.skeleton-title {
  height: 1.5rem;
  width: 40%;
  margin-bottom: 1rem;
}

.skeleton-badge {
  height: 1.5rem;
  width: 80px;
  border-radius: var(--radius-full);
}

.skeleton-row td {
  padding: 1rem;
}

.skeleton-card {
  padding: 1.5rem;
  background: var(--color-bg-secondary);
  border-radius: var(--radius-md);
}

/* Respect reduced motion preference */
@media (prefers-reduced-motion: reduce) {
  .skeleton {
    animation: none;
  }
}
```

## Related

- Plan: [Web UI Phase 3 - UX Polish](../plans/features/web-ui-phase3-ux-polish-plan.md)
- User Story: US-P3-005

