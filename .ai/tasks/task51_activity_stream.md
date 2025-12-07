# Task 51: Activity Stream Backend & UI

## Status: Pending

## Priority: High

## Description

Implement a recent activity stream on the dashboard showing the last 5-10 system events (agent started, task completed, etc.) with relative timestamps to give users visibility into what the system is doing.

## Acceptance Criteria

- [ ] Activity stream displays on dashboard below cards
- [ ] Shows last 5-10 events in chronological order (newest first)
- [ ] Events include: agent_started, agent_stopped, task_completed, agent_created, agent_deleted
- [ ] Each event shows icon, description, and relative timestamp ("5 minutes ago")
- [ ] Empty state when no recent activity
- [ ] Events stored in Redis (or in-memory fallback)
- [ ] Events auto-expire after 24 hours
- [ ] Works in both light and dark modes

## Implementation Details

### Files to Create/Modify

| File | Changes |
|------|---------|
| `lib/adk/activity_log.rb` | New: Activity logging module |
| `lib/adk/web/app.rb` | Log events on agent actions |
| `lib/adk/web/routes/core_routes.rb` | Fetch recent activity for dashboard |
| `lib/adk/web/views/index.slim` | Activity stream UI component |
| `lib/adk/web/public/styles/main.scss` | Activity stream styling |

### Activity Log Module

```ruby
# lib/adk/activity_log.rb
module ADK
  class ActivityLog
    EVENTS_KEY = 'adk:activity:events'
    MAX_EVENTS = 50
    TTL_SECONDS = 86400 # 24 hours
    
    def initialize(redis_client: nil)
      @redis = redis_client
      @in_memory = [] unless @redis
    end
    
    def log(event_type, details = {})
      event = {
        type: event_type,
        details: details,
        timestamp: Time.now.utc.iso8601
      }
      
      if @redis
        @redis.lpush(EVENTS_KEY, event.to_json)
        @redis.ltrim(EVENTS_KEY, 0, MAX_EVENTS - 1)
        @redis.expire(EVENTS_KEY, TTL_SECONDS)
      else
        @in_memory.unshift(event)
        @in_memory = @in_memory.first(MAX_EVENTS)
      end
    end
    
    def recent(limit = 10)
      if @redis
        @redis.lrange(EVENTS_KEY, 0, limit - 1).map { |e| JSON.parse(e, symbolize_names: true) }
      else
        @in_memory.first(limit)
      end
    end
  end
end
```

### Event Types & Icons

| Event Type | Icon | Message Template |
|------------|------|------------------|
| agent_started | fa-play-circle | Agent '{name}' started |
| agent_stopped | fa-stop-circle | Agent '{name}' stopped |
| agent_created | fa-plus-circle | Agent '{name}' created |
| agent_deleted | fa-trash | Agent '{name}' deleted |
| task_completed | fa-check-circle | Task completed on '{agent}' |

### UI Component

```slim
/ Activity Stream Section
.box.mt-5#activity-stream
  h3.title.is-5
    span.icon.mr-2
      i.fas.fa-stream
    | Recent Activity
  
  - if @recent_activity && @recent_activity.any?
    .activity-list
      - @recent_activity.each do |event|
        .activity-item
          span.activity-icon
            i.fas(class=event_icon(event[:type]))
          span.activity-text= event_message(event)
          span.activity-time= time_ago(event[:timestamp])
  - else
    .has-text-centered.has-text-grey.py-4
      span.icon.is-large
        i.fas.fa-clock.fa-2x
      p.mt-2 No recent activity
```

### CSS Styling

```scss
/* Activity Stream */
.activity-list {
  .activity-item {
    display: flex;
    align-items: center;
    padding: 0.75rem 0;
    border-bottom: 1px solid var(--color-border-light);
    
    &:last-child {
      border-bottom: none;
    }
  }
  
  .activity-icon {
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--color-bg-tertiary);
    border-radius: 50%;
    margin-right: 0.75rem;
    color: var(--color-text-muted);
    
    .fa-play-circle { color: var(--color-success); }
    .fa-stop-circle { color: var(--color-danger); }
    .fa-plus-circle { color: var(--color-info); }
    .fa-check-circle { color: var(--color-success); }
  }
  
  .activity-text {
    flex: 1;
    color: var(--color-text-primary);
  }
  
  .activity-time {
    font-size: 0.8rem;
    color: var(--color-text-muted);
  }
}
```

## Related

- Plan: [Web UI Phase 3 - UX Polish](../plans/features/web-ui-phase3-ux-polish-plan.md)
- User Story: US-P3-003
- Designer Feedback: "Adding a feed of the last 5-10 actions would make it a true command center"

