---
id: 41
title: 'Dashboard Live Metrics'
status: completed
priority: high
feature: Web UI Phase 2 Refinement
dependencies: []
assigned_agent: null
created_at: "2025-12-07T05:31:20Z"
started_at: "2025-12-07T05:35:00Z"
completed_at: "2025-12-07T05:38:10Z"
error_log: null
---

## Description

Transform the static dashboard cards from passive navigation ("View Agents") into active status displays showing live counts ("3 Agents Running") to provide at-a-glance system status.

## Details

- Modify the index route in `app.rb` to compute and pass metrics to the template:
  - Total agent count from DefinitionStore
  - Running agent count (agents with running status)
  - Total tool count from tool manager
  - Authentication schemes count (if available)
  
- Update `index.slim` dashboard cards to display:
  - Agents card: "X Running" or "X Agents Defined"
  - Tools card: "X Tools Available"
  - Authentication card: "X Schemes Configured"
  - Documentation card: Can remain static or show doc count

- Style the metrics display:
  - Large number prominently displayed
  - Smaller label text below
  - Consider using accent color for counts

### Files to modify:

- `lib/adk/web/app.rb` - Index route to compute metrics
- `lib/adk/web/views/index.slim` - Dashboard card content

### Example card structure:

```slim
.card.dashboard-card.agents-card
  .card-content.has-text-centered
    span.icon.is-large
      i.fas.fa-robot
    h3.title.is-4 Agents
    p.is-size-2.has-text-primary.has-text-weight-bold= @running_count
    p.subtitle.is-6 Running
    .buttons.is-centered.mt-4
      a.button.is-link href="/agents" View All (#{@agent_count})
```

## Test Strategy

1. Start the application with at least one agent defined
2. Navigate to the homepage dashboard
3. Verify agent count displays correctly
4. Start/stop an agent and refresh to confirm running count updates
5. Check tools count matches the number in the Tools page
6. Test with zero agents to ensure graceful display ("0 Running")

