---
id: 33
title: 'Navigation Enhancement'
status: pending
priority: medium
feature: Web UI Visual Enhancement
dependencies:
  - 29
  - 31
assigned_agent: null
created_at: "2025-12-07T04:44:19Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Improve navbar active state indicators, add subtle refinements, and ensure navigation works in both themes.

## Details

### Navbar Base Styling

```scss
.navbar {
  background: var(--color-bg-secondary);
  border-bottom: 1px solid var(--color-border);
  transition: background-color var(--transition-normal),
              border-color var(--transition-normal);
}

.navbar-brand {
  .navbar-item {
    font-weight: 700;
    font-size: 1.1rem;
  }
}
```

### Active State Indicator

Replace the current light background with a more visible underline indicator:

```scss
.navbar-item {
  position: relative;
  border-radius: var(--radius-sm);
  margin: 0 0.125rem;
  transition: all var(--transition-fast);
  
  &.is-active {
    background: var(--color-primary-light);
    color: var(--color-primary);
    font-weight: 600;
    
    &::after {
      content: '';
      position: absolute;
      bottom: 0;
      left: 50%;
      transform: translateX(-50%);
      width: 70%;
      height: 3px;
      background: var(--color-primary);
      border-radius: 3px 3px 0 0;
    }
  }
  
  &:hover:not(.is-active) {
    background: var(--color-bg-tertiary);
    color: var(--color-text-primary);
  }
}
```

### Theme Toggle Button Styling

```scss
.theme-toggle {
  background: transparent;
  border: none;
  cursor: pointer;
  padding: 0.5rem;
  border-radius: var(--radius-sm);
  color: var(--color-text-secondary);
  transition: all var(--transition-fast);
  
  &:hover {
    background: var(--color-bg-tertiary);
    color: var(--color-text-primary);
  }
  
  i {
    font-size: 1.1rem;
  }
}
```

### Dark Mode Navbar Adjustments

```scss
[data-theme="dark"] {
  .navbar {
    background: var(--color-bg-secondary);
    border-color: var(--color-border);
  }
  
  .navbar-item {
    color: var(--color-text-primary);
    
    &.is-active {
      background: rgba(99, 102, 241, 0.2); // Indigo at 20% opacity
      color: #818cf8; // Lighter indigo for dark mode
    }
    
    &:hover:not(.is-active) {
      background: var(--color-bg-tertiary);
    }
  }
  
  .navbar-burger span {
    background-color: var(--color-text-primary);
  }
}
```

### Mobile Navigation

Ensure mobile burger menu works in both themes:

```scss
.navbar-burger {
  span {
    background-color: var(--color-text-primary);
    transition: background-color var(--transition-fast);
  }
}

.navbar-menu {
  background: var(--color-bg-secondary);
  
  @media screen and (max-width: 1023px) {
    border-top: 1px solid var(--color-border);
    box-shadow: var(--shadow-lg);
  }
}
```

## Test Strategy

1. Start web server and verify navbar loads correctly
2. Navigate between sections - verify active state underline appears
3. Hover over non-active nav items - verify subtle background change
4. Click theme toggle - verify navbar transitions smoothly
5. Test in dark mode - verify colors are readable
6. Test mobile menu (resize browser < 1024px):
   - Verify burger icon is visible
   - Click burger - verify menu opens
   - Verify menu items are visible in both themes
7. Verify brand text "Ruby ADK" is readable in both themes

## Agent Notes

Files to modify:
- `lib/adk/web/public/styles/main.scss`
- `lib/adk/web/views/layout.slim` (if theme toggle not added in task 31)

