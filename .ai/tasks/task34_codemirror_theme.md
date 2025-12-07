---
id: 34
title: 'CodeMirror Theme Integration'
status: pending
priority: medium
feature: Web UI Visual Enhancement
dependencies:
  - 31
assigned_agent: null
created_at: "2025-12-07T04:44:19Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Apply a dark theme to CodeMirror editors for better code visibility and developer experience.

## Details

### Rationale

Even in light mode, code editors benefit from a dark theme because:
1. It visually separates "code/config" from "UI/Controls"
2. Developers are accustomed to dark-themed IDEs
3. Reduces eye strain when editing JSON configurations

### CodeMirror Theme Styling

Apply a Catppuccin-inspired dark theme:

```scss
// CodeMirror Dark Theme (always dark, even in light UI mode)
.CodeMirror {
  background: #1e1e2e !important;
  color: #cdd6f4 !important;
  border: 1px solid #313244;
  border-radius: var(--radius-md);
  font-size: 0.9rem;
  
  .CodeMirror-gutters {
    background: #181825;
    border-right: 1px solid #313244;
  }
  
  .CodeMirror-linenumber {
    color: #6c7086;
  }
  
  .CodeMirror-cursor {
    border-left: 2px solid #f5e0dc;
  }
  
  .CodeMirror-selected {
    background: #45475a !important;
  }
  
  .CodeMirror-focused .CodeMirror-selected {
    background: #45475a !important;
  }
  
  .CodeMirror-line::selection,
  .CodeMirror-line > span::selection,
  .CodeMirror-line > span > span::selection {
    background: #45475a;
  }
}

// Syntax highlighting colors
.cm-s-default {
  .cm-keyword { color: #cba6f7; }      // Purple - keywords
  .cm-atom { color: #fab387; }          // Peach - atoms/constants
  .cm-number { color: #fab387; }        // Peach - numbers
  .cm-def { color: #89b4fa; }           // Blue - definitions
  .cm-variable { color: #cdd6f4; }      // Text - variables
  .cm-variable-2 { color: #f38ba8; }    // Red - variable-2
  .cm-variable-3 { color: #f9e2af; }    // Yellow - variable-3/type
  .cm-property { color: #89dceb; }      // Sky - properties
  .cm-operator { color: #94e2d5; }      // Teal - operators
  .cm-comment { color: #6c7086; font-style: italic; }
  .cm-string { color: #a6e3a1; }        // Green - strings
  .cm-string-2 { color: #a6e3a1; }      // Green - string-2
  .cm-meta { color: #f9e2af; }          // Yellow - meta
  .cm-qualifier { color: #f9e2af; }     // Yellow
  .cm-builtin { color: #f38ba8; }       // Red - builtins
  .cm-bracket { color: #cdd6f4; }       // Text - brackets
  .cm-tag { color: #f38ba8; }           // Red - tags
  .cm-attribute { color: #fab387; }     // Peach - attributes
  .cm-error { color: #f38ba8; background: #45475a; }
}

// Match CodeMirror to dark mode when UI is dark
// (It's already dark, but ensure borders match)
[data-theme="dark"] .CodeMirror {
  border-color: var(--color-border);
}
```

### Read-Only CodeMirror

For display-only code views:

```scss
.CodeMirror-readonly {
  .CodeMirror-cursor {
    display: none !important;
  }
  
  background: #11111b !important; // Slightly darker for read-only
}
```

### Lint Markers

```scss
.CodeMirror-lint-markers {
  background: #181825;
}

.CodeMirror-lint-marker-error {
  color: #f38ba8;
}

.CodeMirror-lint-marker-warning {
  color: #f9e2af;
}
```

## Test Strategy

1. Start web server and navigate to Agents page
2. Click on an agent to view details
3. Find a CodeMirror editor (e.g., MCP configuration, instructions)
4. Verify editor has dark background (#1e1e2e)
5. Verify syntax highlighting is visible and colors are distinct
6. Type in an editable editor - verify cursor is visible
7. Select text - verify selection is visible
8. Test in both light and dark UI modes
9. Verify read-only displays (like JSON output) are slightly darker
10. If lint markers are present, verify they're visible

## Agent Notes

Files to modify:
- `lib/adk/web/public/styles/main.scss`

Note: The existing CodeMirror initialization in layout.slim uses default theme.
We're overriding with CSS rather than changing the JS initialization.

