# Task 56: Mobile Touch Target Audit

## Status: Pending

## Priority: Low

## Description

Audit and fix touch targets across the UI to ensure all interactive elements are at least 44px for mobile usability, following Apple's Human Interface Guidelines.

## Acceptance Criteria

- [ ] All buttons have minimum 44px touch target
- [ ] All links in navigation have adequate touch area
- [ ] Table action buttons are touch-friendly
- [ ] Form inputs have adequate touch targets
- [ ] Dropdown triggers are easy to tap
- [ ] No touch targets overlap or are too close together
- [ ] Tested on actual mobile device or emulator

## Implementation Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/adk/web/public/styles/main.scss` | Touch target CSS utilities and fixes |
| Various view files | Add touch-target classes where needed |

### Areas to Audit

1. **Navigation**
   - Navbar links
   - Hamburger menu button
   - Theme toggle button

2. **Tables**
   - Row action dropdowns
   - Tool/Agent name links
   - Status badges (if clickable)

3. **Forms**
   - Input fields
   - Checkboxes
   - Select dropdowns
   - Submit buttons

4. **Cards**
   - Card action buttons
   - Quick action buttons

5. **Modals/Dropdowns**
   - Close buttons
   - Dropdown items

### CSS Utilities

```scss
/* Touch Target Utilities */
.touch-target {
  position: relative;
  
  // Expand touch area without changing visual size
  &::before {
    content: '';
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    width: max(100%, 44px);
    height: max(100%, 44px);
  }
}

/* Mobile-specific touch target adjustments */
@media (max-width: 768px) {
  // Navbar
  .navbar-item,
  .navbar-link {
    min-height: 44px;
    padding: 0.75rem 1rem;
  }
  
  // Buttons
  .button.is-small {
    min-height: 44px;
    min-width: 44px;
    padding: 0.5rem 1rem;
  }
  
  // Table actions
  .dropdown-trigger .button {
    min-height: 44px;
    min-width: 44px;
  }
  
  // Dropdown items
  .dropdown-item {
    padding: 0.75rem 1rem;
    min-height: 44px;
  }
  
  // Form inputs
  .input,
  .textarea,
  .select select {
    min-height: 44px;
  }
  
  // Checkboxes - expand touch area
  .checkbox,
  .radio {
    padding: 0.5rem;
    margin: -0.5rem;
  }
  
  // Panel blocks (tool selection)
  .panel-block {
    min-height: 48px;
    padding: 0.75rem 1rem;
  }
}

/* Ensure adequate spacing between touch targets */
@media (max-width: 768px) {
  .buttons .button + .button {
    margin-left: 0.5rem;
  }
  
  .field.is-grouped .control + .control {
    margin-left: 0.5rem;
  }
}
```

### Testing Checklist

- [ ] Test on iOS Safari
- [ ] Test on Android Chrome
- [ ] Use Chrome DevTools device emulation
- [ ] Verify no accidental taps on adjacent elements
- [ ] Test with "Show touch areas" debug overlay

### Tools for Auditing

1. Chrome DevTools > Device Mode
2. Safari Web Inspector > Responsive Design Mode
3. Firefox Responsive Design Mode
4. BrowserStack for real device testing

## Related

- Plan: [Web UI Phase 3 - UX Polish](../plans/features/web-ui-phase3-ux-polish-plan.md)
- Reference: [Apple HIG - Touch Targets](https://developer.apple.com/design/human-interface-guidelines/accessibility#Touch-targets)

