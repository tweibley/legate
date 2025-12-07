# Task 48: Keyboard Search Shortcut

## Status: Pending

## Priority: High

## Description

Implement Cmd/Ctrl+K keyboard shortcut to focus the search box globally from any page, improving efficiency for power users.

## Acceptance Criteria

- [ ] Cmd+K (Mac) focuses search input
- [ ] Ctrl+K (Windows/Linux) focuses search input
- [ ] Works from any page in the application
- [ ] Visual hint displayed near search input showing shortcut
- [ ] Shortcut doesn't interfere with browser defaults when input is focused
- [ ] Search input scrolls into view if not visible

## Implementation Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/adk/web/views/layout.slim` | Add keyboard listener script |
| `lib/adk/web/views/agents.slim` | Add shortcut hint to search input |
| `lib/adk/web/public/styles/main.scss` | Styling for shortcut hint badge |

### JavaScript Implementation

```javascript
// In layout.slim or separate JS file
document.addEventListener('keydown', function(e) {
  // Cmd+K (Mac) or Ctrl+K (Windows/Linux)
  if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
    e.preventDefault();
    const searchInput = document.querySelector('#agent-search-input, .search-input');
    if (searchInput) {
      searchInput.focus();
      searchInput.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }
});
```

### Search Input with Hint

```slim
.field.has-addons
  .control.has-icons-left.is-expanded
    input.input#agent-search-input(type="text" placeholder="Search agents...")
    span.icon.is-left
      i.fas.fa-search
  .control
    span.keyboard-shortcut-hint
      kbd ⌘
      kbd K
```

### CSS Styling

```scss
/* Keyboard shortcut hint */
.keyboard-shortcut-hint {
  display: flex;
  align-items: center;
  gap: 2px;
  padding: 0 0.5rem;
  background: var(--color-bg-tertiary);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  
  kbd {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    padding: 2px 4px;
    background: var(--color-bg-secondary);
    border-radius: 3px;
    color: var(--color-text-muted);
  }
}
```

## Related

- Plan: [Web UI Phase 3 - UX Polish](../plans/features/web-ui-phase3-ux-polish-plan.md)
- User Story: US-P3-004

