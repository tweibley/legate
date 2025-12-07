# PRD: Web UI Phase 3 - UX Polish & Interaction Design

## 1. Product overview

### 1.1 Document title and version

- PRD: Web UI Phase 3 - UX Polish & Interaction Design
- Version: 1.0
- Created: 2025-12-07

### 1.2 Product summary

This plan addresses the third phase of Web UI improvements for Ruby ADK, building upon the completed Phase 1 (dark mode foundation) and Phase 2 (brand identity, live metrics). Phase 3 focuses on **interaction design** and **user experience polish** — transforming the UI from a well-styled tool into a delightful, efficient interface.

This phase synthesizes recommendations from two independent design reviews, prioritizing:
1. **Navigation Improvements**: Breadcrumbs, active states, keyboard shortcuts
2. **Dashboard Evolution**: Hero section, quick actions, activity stream
3. **Micro-interactions**: Loading states, animations, feedback
4. **Accessibility & Responsiveness**: Mobile refinement, touch targets

## 2. Goals

### 2.1 Business goals

- Reduce friction in common workflows (fewer clicks to accomplish tasks)
- Create a "command center" feel that keeps users engaged in the dashboard
- Build trust through professional micro-interactions and polish

### 2.2 User goals

- Understand location within the app at all times (breadcrumbs)
- Quickly access common actions without navigating (quick actions)
- Receive clear feedback for all interactions (loading states, animations)
- Know what the system is doing (activity stream)

### 2.3 Non-goals

- Real-time WebSocket updates (too complex for this phase)
- Mobile-first redesign (refinement only, not restructure)
- Adding new features beyond UX improvements

## 3. Functional requirements

### 3.1 Navigation & Orientation (Priority: High)

| Feature | Description |
|---------|-------------|
| **Breadcrumb Navigation** | Add breadcrumb trail on detail pages (e.g., "Agents > cat facts only") |
| **Navbar Active State** | Visible indicator (underline/highlight) for current page in navbar |
| **Keyboard Search** | Cmd/Ctrl+K to focus search box globally |

### 3.2 Dashboard Enhancement (Priority: High)

| Feature | Description |
|---------|-------------|
| **Hero Welcome Section** | Gradient banner with primary CTA button ("Create New Agent") |
| **Quick Actions** | Add small "+" buttons in dashboard card footers |
| **Recent Activity Stream** | Display last 5-10 system events on dashboard |

### 3.3 Feedback & Micro-interactions (Priority: Medium)

| Feature | Description |
|---------|-------------|
| **Loading Skeletons** | Replace "Loading..." text with skeleton UI components |
| **Status Badge Animation** | Subtle pulse for "Running" state, static for "Stopped" |
| **Collapsible Animation** | Smooth rotate animation for disclosure triangles |
| **Toast Notification Polish** | Ensure success/error toasts are visually polished |

### 3.4 Component Refinements (Priority: Medium)

| Feature | Description |
|---------|-------------|
| **Form Field Grouping** | Visual containers for related form fields in agent creation |
| **Actions Dropdown Visibility** | More visible actions button in table rows |
| **Start/Stop Button Logic** | Hide irrelevant action button based on state |

### 3.5 Responsive Design (Priority: Low)

| Feature | Description |
|---------|-------------|
| **Mobile Touch Targets** | Ensure buttons/links are ≥44px for touch devices |
| **Table Responsiveness** | Horizontal scroll or card view on narrow screens |

## 4. User experience

### 4.1 Entry points & first-time user flow

1. User arrives at dashboard → sees Hero section with "Create New Agent" CTA
2. Hero provides immediate context and primary action
3. Dashboard cards show live counts with quick action buttons
4. Activity stream shows recent events, building confidence that system is working

### 4.2 Core experience

- **Dashboard**: Hero + Live Metrics + Quick Actions + Activity Stream = Command Center
- **Navigation**: Breadcrumbs show location, active state confirms selection
- **Interactions**: Skeleton loaders during fetches, animations on state changes
- **Search**: Cmd+K anywhere to search agents, tools, docs

### 4.3 UI/UX highlights

- Hero section transforms static header into engagement point
- Activity stream provides "heartbeat" visibility into system
- Breadcrumbs reduce "where am I?" confusion on detail pages
- Skeleton loaders feel faster than spinners

## 5. Narrative

A developer returns to Ruby ADK after setting up some agents. They land on the dashboard and immediately see the hero section welcoming them with a prominent "Create New Agent" button. Below, the cards show "3 Agents Running" with small "+" icons for quick agent creation. An activity stream shows "Agent 'assistant' started 5m ago" and "Task completed successfully 12m ago" — the system feels alive. They click into an agent and see breadcrumbs "Agents > assistant" at the top, knowing exactly where they are. When they switch tabs, a brief skeleton loader appears before content — no jarring "Loading..." text. The small details add up to an interface that feels thoughtfully crafted.

## 6. Technical considerations

### 6.1 Integration points

| File | Changes |
|------|---------|
| `layout.slim` | Breadcrumb component, keyboard shortcut listener |
| `index.slim` | Hero section, quick actions, activity stream |
| `main.scss` | Animations, skeleton styles, responsive utilities |
| `app.rb` | Activity log endpoint, keyboard shortcut metadata |
| Various views | Loading skeletons, form grouping |

### 6.2 Activity Stream Backend

- Simple in-memory or Redis list of last N events
- Events: agent_started, agent_stopped, task_completed, agent_created
- No complex EventLog model needed — just a circular buffer

### 6.3 Performance

- Skeleton CSS adds ~2KB
- Activity stream fetch on page load (not real-time)
- Keyboard listener is lightweight

## 7. Milestones & sequencing

### 7.1 Project estimate

- Medium: 6-10 hours total

### 7.2 Suggested phases

- **Phase A**: Navigation (2-3 hours)
  - Breadcrumbs, navbar active state, keyboard search
- **Phase B**: Dashboard Evolution (2-3 hours)
  - Hero section, quick actions, activity stream
- **Phase C**: Micro-interactions (2-3 hours)
  - Skeleton loaders, animations, component refinements
- **Phase D**: Responsive Polish (1-2 hours)
  - Mobile touch targets, table responsiveness

## 8. Task breakdown

| ID | Task | Priority | Est. Hours |
|----|------|----------|------------|
| 46 | Breadcrumb Navigation Component | High | 1 |
| 47 | Navbar Active State Indicator | High | 0.5 |
| 48 | Keyboard Search Shortcut (Cmd+K) | High | 1 |
| 49 | Dashboard Hero Welcome Section | High | 1 |
| 50 | Dashboard Quick Action Buttons | High | 0.5 |
| 51 | Activity Stream Backend & UI | High | 2 |
| 52 | Skeleton Loading Components | Medium | 1.5 |
| 53 | Status Badge Pulse Animation | Medium | 0.5 |
| 54 | Form Field Visual Grouping | Medium | 1 |
| 55 | Actions Dropdown Visibility | Medium | 0.5 |
| 56 | Mobile Touch Target Audit | Low | 1 |

## 9. User stories

### 9.1 Breadcrumb Navigation

- **ID**: US-P3-001
- **Description**: As a user on a detail page, I want to see breadcrumbs so I know where I am and can navigate back easily.
- **Acceptance Criteria**:
  - Breadcrumb trail visible on agent detail, tool detail pages
  - Format: "Agents > agent-name" with clickable parent links
  - Styled consistently with Ruby ADK theme

### 9.2 Dashboard Hero Section

- **ID**: US-P3-002
- **Description**: As a new user, I want a prominent welcome section so I know the primary action to take.
- **Acceptance Criteria**:
  - Gradient banner at top of dashboard
  - "Create New Agent" CTA button prominently displayed
  - Works in both light and dark mode

### 9.3 Activity Stream

- **ID**: US-P3-003
- **Description**: As a user, I want to see recent system activity so I know the system is working.
- **Acceptance Criteria**:
  - Last 5-10 events displayed on dashboard
  - Events include: agent started/stopped, task completed
  - Timestamps shown (e.g., "5 minutes ago")
  - Empty state when no recent activity

### 9.4 Keyboard Search

- **ID**: US-P3-004
- **Description**: As a power user, I want to press Cmd+K to search so I can find things quickly.
- **Acceptance Criteria**:
  - Cmd+K (Mac) / Ctrl+K (Windows) focuses search input
  - Works from any page
  - Visual hint shown near search box

### 9.5 Skeleton Loaders

- **ID**: US-P3-005
- **Description**: As a user, I want to see skeleton placeholders during loading so the interface feels responsive.
- **Acceptance Criteria**:
  - Skeleton components for tables, cards, content areas
  - Animated shimmer effect
  - Replaces "Loading..." text in key areas

## 10. Dependencies

- Phase 2 completion (Tasks 39-45) ✅
- Redis available for activity stream storage (optional, can use in-memory)

## 11. Success metrics

- Time to first action reduced (hero CTA)
- Navigation errors reduced (breadcrumbs)
- Perceived performance improved (skeleton loaders)
- Power user efficiency (keyboard shortcuts)


