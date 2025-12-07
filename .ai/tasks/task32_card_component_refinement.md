---
id: 32
title: 'Card & Component Refinement'
status: pending
priority: medium
feature: Web UI Visual Enhancement
dependencies:
  - 29
assigned_agent: null
created_at: "2025-12-07T04:44:19Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Add hover lift animations, improved shadows, and accent borders to cards. Refine buttons, inputs, and table styling.

## Details

### Card Hover Effects

```scss
.card, .box {
  background: var(--color-bg-secondary);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-md);
  transition: transform var(--transition-normal), 
              box-shadow var(--transition-normal);
  
  &:hover {
    transform: translateY(-4px);
    box-shadow: var(--shadow-hover);
  }
}
```

### Dashboard Card Accents

Add accent classes for dashboard cards:

```scss
.dashboard-card {
  position: relative;
  overflow: hidden;
  
  &::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 3px;
    background: var(--color-primary);
  }
  
  &.agents-card::before { background: var(--color-accent); }
  &.tools-card::before { background: var(--color-info); }
  &.auth-card::before { background: var(--color-warning); }
  &.docs-card::before { background: var(--color-success); }
}
```

### Button Refinement

```scss
.button {
  border-radius: var(--radius-md);
  font-weight: 500;
  transition: all var(--transition-fast);
  
  &:hover:not(:disabled) {
    transform: translateY(-1px);
  }
  
  &:focus {
    box-shadow: 0 0 0 3px rgba(var(--color-primary-rgb), 0.3);
  }
}
```

### Input Refinement

```scss
.input, .textarea, .select select {
  border-radius: var(--radius-md);
  border-color: var(--color-border);
  background: var(--color-bg-secondary);
  transition: border-color var(--transition-fast), 
              box-shadow var(--transition-fast);
  
  &:focus {
    border-color: var(--color-primary);
    box-shadow: 0 0 0 3px var(--color-primary-light);
  }
}

.label {
  font-weight: 600;
  font-size: 0.875rem;
  color: var(--color-text-primary);
}
```

### Table Refinement

```scss
.table-container {
  background: var(--color-bg-secondary);
  border-radius: var(--radius-lg);
  border: 1px solid var(--color-border);
  overflow: hidden;
}

.table {
  background: transparent;
  
  thead th {
    background: var(--color-bg-tertiary);
    color: var(--color-text-secondary);
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    font-weight: 600;
    padding: 0.875rem 1rem;
  }
  
  tbody tr {
    transition: background var(--transition-fast);
    
    &:hover {
      background: var(--color-primary-light);
    }
  }
}
```

### Status Badges

```scss
.status-badge {
  padding: 0.25rem 0.75rem;
  border-radius: 9999px;
  font-size: 0.75rem;
  font-weight: 600;
  
  &.running { background: #dcfce7; color: #166534; }
  &.stopped { background: #fee2e2; color: #991b1b; }
  &.pending { background: #fef3c7; color: #92400e; }
}

[data-theme="dark"] .status-badge {
  &.running { background: #166534; color: #dcfce7; }
  &.stopped { background: #991b1b; color: #fee2e2; }
  &.pending { background: #92400e; color: #fef3c7; }
}
```

## Test Strategy

1. Start web server and navigate to homepage
2. Hover over cards - verify lift animation (translateY) and shadow change
3. Navigate to Agents page - verify table styling
4. Test button hover states
5. Test input focus states
6. Verify transitions are smooth (not jarring)
7. Test all in dark mode to ensure visibility
8. Check agent status tags display correctly
9. Verify no layout shifts from added borders/shadows

## Agent Notes

Files to modify:
- `lib/adk/web/public/styles/main.scss`

Note: Dashboard card classes will be added to HTML in task 35.

