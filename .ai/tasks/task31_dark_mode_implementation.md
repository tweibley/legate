---
id: 31
title: 'Dark Mode Implementation'
status: pending
priority: high
feature: Web UI Visual Enhancement
dependencies:
  - 29
  - 30
assigned_agent: null
created_at: "2025-12-07T04:44:19Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Implement dark mode with theme toggle in navbar, localStorage persistence, and complete dark mode CSS variable palette.

## Details

### CSS Variables for Dark Mode

Add to main.scss after `:root` block:

```scss
[data-theme="dark"] {
  --color-bg-primary: #0f1419;
  --color-bg-secondary: #1a1f26;
  --color-bg-tertiary: #242b33;
  --color-text-primary: #e7e9ea;
  --color-text-secondary: #9ca3af;
  --color-text-muted: #6b7280;
  --color-border: #2f3943;
  
  --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.3);
  --shadow-md: 0 4px 12px rgba(0, 0, 0, 0.4);
  --shadow-lg: 0 8px 24px rgba(0, 0, 0, 0.5);
}
```

### Theme Toggle Button

Add to layout.slim navbar:
- Icon button using Font Awesome (moon/sun icons)
- Position in navbar-end section
- Toggle `data-theme` attribute on `<html>` element

### JavaScript Implementation

Add to layout.slim before closing body tag:

```javascript
// Initialize theme from localStorage or system preference
(function() {
  const savedTheme = localStorage.getItem('adk-theme');
  const systemPrefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  const theme = savedTheme || (systemPrefersDark ? 'dark' : 'light');
  document.documentElement.setAttribute('data-theme', theme);
})();

function toggleTheme() {
  const current = document.documentElement.getAttribute('data-theme');
  const next = current === 'dark' ? 'light' : 'dark';
  document.documentElement.setAttribute('data-theme', next);
  localStorage.setItem('adk-theme', next);
  // Update icon
  const icon = document.querySelector('.theme-toggle i');
  if (icon) {
    icon.className = next === 'dark' ? 'fas fa-sun' : 'fas fa-moon';
  }
}
```

### Component Updates

Update these components to use CSS variables:
- body background and text color
- .navbar background
- .card, .box background and border
- .table background
- .button colors (where not using Bulma semantic colors)
- #chat-log-container
- .message variants
- .footer

### Transition for Theme Switch

Add smooth transition:
```scss
body, .card, .box, .navbar, .table, .button {
  transition: background-color var(--transition-normal), 
              color var(--transition-normal),
              border-color var(--transition-normal);
}
```

## Test Strategy

1. Start web server and open UI
2. Click theme toggle - verify theme switches immediately
3. Verify all major components change colors appropriately:
   - Navbar background
   - Page background
   - Cards and boxes
   - Tables
   - Text colors
   - Borders
4. Refresh page - verify theme persists (check localStorage)
5. Clear localStorage and refresh - verify system preference is detected
6. Test on multiple pages (Agents, Tools, Auth, Documentation)
7. Verify no flicker/flash when loading page with saved dark theme
8. Check chat interface works in both themes
9. Verify CodeMirror editor is visible in both themes (will be enhanced in task 34)

## Agent Notes

Files to modify:
- `lib/adk/web/views/layout.slim`
- `lib/adk/web/public/styles/main.scss`

