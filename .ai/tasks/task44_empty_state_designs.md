---
id: 44
title: 'Empty State Designs'
status: completed
priority: low
feature: Web UI Phase 2 Refinement
dependencies: []
assigned_agent: null
created_at: "2025-12-07T05:31:20Z"
started_at: "2025-12-07T05:35:00Z"
completed_at: "2025-12-07T05:38:10Z"
error_log: null
---

## Description

Add friendly empty state designs with icons and CTA buttons to list pages when no items exist, guiding new users on what to do next.

## Details

- Create reusable empty state component/partial
- Add empty state to Agents list when no agents defined
- Add empty state to Tools list when no tools available
- Add empty state to Authentication schemes list
- Include appropriate icon, message, and action button

### Empty state structure:

```slim
- if @items.empty?
  .has-text-centered.py-6
    span.icon.is-large.has-text-grey-lighter
      i.fas.fa-robot.fa-3x
    p.title.is-5.mt-4.has-text-grey No agents defined yet
    p.subtitle.is-6.has-text-grey-light Get started by creating your first agent
    .buttons.is-centered.mt-4
      a.button.is-primary.is-outlined href="#create-agent"
        span.icon
          i.fas.fa-plus
        span Create Agent
- else
  / ... normal list rendering
```

### Icons per section:

- Agents: `fa-robot` or `fa-user-robot`
- Tools: `fa-wrench` or `fa-toolbox`
- Authentication: `fa-key` or `fa-shield-halved`
- Documentation: `fa-book-open`
- Chat sessions: `fa-comments`

### Files to modify:

- `lib/adk/web/views/agents/_list.slim` or agents index
- `lib/adk/web/views/tools/index.slim`
- `lib/adk/web/views/auth/index.slim`
- Optionally create `lib/adk/web/views/_empty_state.slim` partial

### CSS (if needed):

```scss
.empty-state {
  padding: 3rem 1.5rem;
  text-align: center;
  
  .icon.is-large {
    font-size: 4rem;
    color: var(--color-text-muted);
    opacity: 0.5;
  }
}
```

## Test Strategy

1. Remove all agents and navigate to Agents page - verify empty state shows
2. Check empty state displays appropriate icon and message
3. Click CTA button and verify it triggers appropriate action
4. Test in both light and dark modes for proper styling
5. Add an agent and verify empty state is replaced with list

