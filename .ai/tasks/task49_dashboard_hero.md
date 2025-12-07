# Task 49: Dashboard Hero Welcome Section

## Status: Pending

## Priority: High

## Description

Create a styled gradient hero banner at the top of the dashboard with a welcome message and prominent "Create New Agent" CTA button to orient users and provide a primary action point.

## Acceptance Criteria

- [ ] Hero section displays at top of dashboard (index page)
- [ ] Contains "Welcome to Ruby ADK" heading
- [ ] Subtitle explaining the product purpose
- [ ] Prominent "Create New Agent" CTA button
- [ ] Gradient background using Ruby ADK brand colors
- [ ] Works beautifully in both light and dark modes
- [ ] Responsive design for mobile

## Implementation Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/adk/web/views/index.slim` | Add hero section HTML |
| `lib/adk/web/public/styles/main.scss` | Hero section styling |

### Slim Template

```slim
/ Hero Section
section.hero-welcome.mb-6
  .hero-content
    h1.hero-title Welcome to Ruby ADK
    p.hero-subtitle Ruby Agent Development Kit - Build and manage AI agents with ease
    .hero-actions
      a.button.is-primary.is-medium(href="/agents")
        span.icon
          i.fas.fa-plus
        span Create New Agent
      a.button.is-light.is-medium.ml-3(href="/docs")
        span.icon
          i.fas.fa-book
        span Read Docs
```

### CSS Styling

```scss
/* Hero Welcome Section */
.hero-welcome {
  position: relative;
  padding: 3rem 2rem;
  border-radius: var(--radius-lg);
  background: linear-gradient(135deg, 
    var(--color-primary) 0%, 
    hsl(348, 83%, 35%) 50%,
    hsl(348, 70%, 25%) 100%
  );
  color: white;
  text-align: center;
  overflow: hidden;
  
  // Subtle pattern overlay
  &::before {
    content: '';
    position: absolute;
    inset: 0;
    background: url("data:image/svg+xml,...") repeat;
    opacity: 0.05;
  }
  
  .hero-content {
    position: relative;
    z-index: 1;
  }
  
  .hero-title {
    font-size: 2.5rem;
    font-weight: 700;
    margin-bottom: 0.5rem;
    text-shadow: 0 2px 4px rgba(0,0,0,0.2);
  }
  
  .hero-subtitle {
    font-size: 1.1rem;
    opacity: 0.9;
    margin-bottom: 1.5rem;
    max-width: 600px;
    margin-left: auto;
    margin-right: auto;
  }
  
  .hero-actions {
    display: flex;
    justify-content: center;
    gap: 1rem;
    flex-wrap: wrap;
  }
  
  .button.is-primary {
    background: white;
    color: var(--color-primary);
    
    &:hover {
      background: var(--color-bg-tertiary);
    }
  }
  
  .button.is-light {
    background: rgba(255,255,255,0.2);
    color: white;
    border: 1px solid rgba(255,255,255,0.3);
    
    &:hover {
      background: rgba(255,255,255,0.3);
    }
  }
}

/* Dark mode adjustments */
[data-theme="dark"] .hero-welcome {
  background: linear-gradient(135deg,
    hsl(348, 70%, 30%) 0%,
    hsl(348, 60%, 20%) 100%
  );
}
```

## Related

- Plan: [Web UI Phase 3 - UX Polish](../plans/features/web-ui-phase3-ux-polish-plan.md)
- User Story: US-P3-002
- Designer Feedback: "A styled Hero section would welcome users and provide a primary action point"

