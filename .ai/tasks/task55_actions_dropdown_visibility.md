# Task 55: Actions Dropdown Visibility

## Status: Complete

## Priority: Medium

## Description

Make the table row actions dropdown (ellipsis menu) more visible and discoverable, potentially adding "Actions" text or a more prominent button style.

## Acceptance Criteria

- [x] Actions button is more visible than current ellipsis icon
- [x] Clear affordance that it's clickable/interactive
- [x] Consistent styling across agent and tool tables
- [x] Works in both light and dark modes
- [x] Maintains dropdown functionality
- [x] Mobile-friendly touch target

## Implementation Notes

The actions were implemented as inline icon buttons (Gmail/Notion style) rather than a dropdown menu. This provides:
- Better discoverability with colored action buttons (green for start, red for stop/delete)
- Clear visual feedback on hover with background color changes
- 32px touch targets for mobile usability
- Consistent styling in both light and dark modes

## Implementation Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/adk/web/views/_agent_row.slim` | Update actions button markup |
| `lib/adk/web/public/styles/main.scss` | Actions button styling |

### Option A: Text + Icon Button

```slim
/ In _agent_row.slim - Actions column
td.has-text-right
  .dropdown.is-hoverable.is-right
    .dropdown-trigger
      button.button.is-small.actions-button(aria-haspopup="true")
        span Actions
        span.icon.is-small
          i.fas.fa-chevron-down
    .dropdown-menu
      / ... dropdown content
```

### Option B: Enhanced Icon Button

```slim
/ In _agent_row.slim - Actions column
td.has-text-right
  .dropdown.is-hoverable.is-right
    .dropdown-trigger
      button.button.is-small.is-outlined.actions-button(aria-haspopup="true" title="Actions")
        span.icon
          i.fas.fa-ellipsis-h
    .dropdown-menu
      / ... dropdown content
```

### CSS Styling

```scss
/* Actions Button Enhancement */
.actions-button {
  opacity: 0.6;
  transition: all var(--transition-fast);
  
  &:hover {
    opacity: 1;
    background: var(--color-bg-tertiary);
  }
}

/* Show on row hover */
tr:hover .actions-button {
  opacity: 1;
}

/* Option A: Text button styling */
.actions-button {
  font-size: 0.75rem;
  padding: 0.25em 0.75em;
  height: auto;
  
  .icon {
    margin-left: 0.25em !important;
    font-size: 0.6rem;
  }
}

/* Option B: Icon button with border on hover */
.actions-button.is-outlined {
  border-color: transparent;
  
  &:hover {
    border-color: var(--color-border);
    background: var(--color-bg-secondary);
  }
}

/* Ensure dropdown menu is visible */
.dropdown-menu {
  min-width: 140px;
}

.dropdown-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  
  .icon {
    width: 1.25rem;
  }
}
```

### Recommendation

**Option A (Text + Icon)** is recommended because:
- More discoverable for new users
- Clearer affordance of interactivity
- "Actions" text is self-explanatory
- Still compact enough for table cells

## Related

- Plan: [Web UI Phase 3 - UX Polish](../plans/features/web-ui-phase3-ux-polish-plan.md)

