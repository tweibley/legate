---
id: 45
title: 'Table Row Hover Accent'
status: pending
priority: low
feature: Web UI Phase 2 Refinement
dependencies: [43]
assigned_agent: null
created_at: "2025-12-07T05:31:20Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Add a subtle left-border accent on table row hover to provide clear visual feedback for row selection across the Agents, Tools, and other list tables.

## Details

- Add CSS for table row hover state with left border accent
- Use primary color (ruby red after task 43) for the accent
- Ensure accent doesn't shift table layout (use pseudo-element or existing border)
- Apply to all data tables (agents list, tools list, etc.)
- Maintain existing hover background color change

### CSS Implementation:

```scss
.table tbody tr {
  position: relative;
  transition: background-color var(--transition-fast);
  
  &::before {
    content: '';
    position: absolute;
    left: 0;
    top: 0;
    bottom: 0;
    width: 3px;
    background: var(--color-primary);
    opacity: 0;
    transition: opacity var(--transition-fast);
  }
  
  &:hover {
    &::before {
      opacity: 1;
    }
  }
}

// Ensure table container allows overflow for the accent
.table-container {
  overflow: visible;
}
```

### Alternative approach (using border):

```scss
.table tbody tr {
  border-left: 3px solid transparent;
  transition: border-color var(--transition-fast), background-color var(--transition-fast);
  
  &:hover {
    border-left-color: var(--color-primary);
  }
}
```

### Files to modify:

- `lib/adk/web/public/styles/main.scss` - Table styles section

### Affected tables:

- Agents list table
- Tools list table
- Authentication schemes table
- Documentation index table

## Test Strategy

1. Navigate to Agents page with at least one agent
2. Hover over table rows and verify left accent appears
3. Verify accent color matches primary (ruby red)
4. Check that accent doesn't cause layout shift
5. Test in Tools and other list pages
6. Verify works in both light and dark modes

