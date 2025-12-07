# Task 54: Form Field Visual Grouping

## Status: Pending

## Priority: Medium

## Description

Group related fields in the "Create New Agent" form with visual containers and section headers for better organization and scannability.

## Acceptance Criteria

- [ ] Form fields grouped into logical sections (Basic Info, Configuration, Tools, etc.)
- [ ] Each section has a clear header/label
- [ ] Visual containers (cards or bordered sections) separate groups
- [ ] Collapsible sections for advanced options (optional)
- [ ] Works in both light and dark modes
- [ ] Maintains existing form functionality

## Implementation Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/adk/web/views/agents.slim` | Restructure form with field groups |
| `lib/adk/web/public/styles/main.scss` | Form group styling |

### Proposed Field Groups

1. **Basic Information**
   - Name
   - Description
   - Agent Type

2. **Model Configuration**
   - Language Model
   - Planning Fallback

3. **Instructions**
   - System Prompt / Instructions

4. **Tools & Integrations**
   - Tool Selection
   - MCP Server Configuration

5. **Workflow Configuration** (conditional, for workflow agents)
   - Sub-Agent Selection

### Slim Template Structure

```slim
form#create-agent-form(...)
  / Basic Information Section
  .form-section
    .form-section-header
      span.icon
        i.fas.fa-info-circle
      span Basic Information
    .form-section-content
      .columns
        .column.is-half
          / Name field
        .column.is-half
          / Agent Type field
      / Description field

  / Model Configuration Section
  .form-section
    .form-section-header
      span.icon
        i.fas.fa-brain
      span Model Configuration
    .form-section-content
      .columns
        .column.is-half
          / Language Model field
        .column.is-half
          / Fallback Mode field

  / ... more sections
```

### CSS Styling

```scss
/* Form Section Grouping */
.form-section {
  background: var(--color-bg-secondary);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  margin-bottom: 1.5rem;
  overflow: hidden;
}

.form-section-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.75rem 1rem;
  background: var(--color-bg-tertiary);
  border-bottom: 1px solid var(--color-border);
  font-weight: 600;
  font-size: 0.9rem;
  color: var(--color-text-secondary);
  
  .icon {
    color: var(--color-primary);
  }
}

.form-section-content {
  padding: 1.25rem;
}

/* Collapsible sections (optional) */
.form-section.is-collapsible {
  .form-section-header {
    cursor: pointer;
    
    &::after {
      content: '';
      margin-left: auto;
      border: solid var(--color-text-muted);
      border-width: 0 2px 2px 0;
      padding: 3px;
      transform: rotate(45deg);
      transition: transform var(--transition-fast);
    }
  }
  
  &.is-collapsed {
    .form-section-header::after {
      transform: rotate(-45deg);
    }
    
    .form-section-content {
      display: none;
    }
  }
}
```

## Related

- Plan: [Web UI Phase 3 - UX Polish](../plans/features/web-ui-phase3-ux-polish-plan.md)

