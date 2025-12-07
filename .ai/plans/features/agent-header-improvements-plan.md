# PRD: Agent Header Improvements

## 1. Product overview

### 1.1 Document title and version

- PRD: Agent Header Improvements
- Version: 1.0

### 1.2 Product summary

Building on the Agent Details UI Polish work (Tasks 57-61), this plan focuses on further refinements to the agent header area. The goal is to create a more streamlined, information-rich header that gives developers immediate insight into agent status while providing quick access to common actions.

Key improvements include consolidating the header layout for better space efficiency, adding meaningful metrics, introducing a quick actions menu, and enhancing the visual identity of agents.

## 2. Goals

### 2.1 Business goals

- Further improve the professional appearance of the ADK web interface
- Reduce cognitive load when managing agents
- Enable faster agent operations through streamlined controls

### 2.2 User goals

- Quickly understand agent state and recent activity at a glance
- Access common actions (edit, duplicate, delete) without hunting
- See meaningful metrics beyond just "Running/Stopped"
- Navigate to related resources (tools, config) directly from header

### 2.3 Non-goals

- Adding new agent functionality (focus is on UI/UX)
- Real-time metrics requiring backend changes (use available data)
- Agent comparison or multi-agent views

## 3. Functional requirements

### 3.1 Streamlined Header Layout (Priority: High)

- Consolidate status badge and action button onto the same row
- Reduce vertical space consumption
- Maintain clear visual hierarchy: name > status/action > metadata

### 3.2 Enhanced Stats Bar (Priority: High)

- Replace minimal stats with a horizontal bar containing:
  - Tool count (clickable, navigates to Tools tab)
  - Last run time (relative timestamp)
  - Run status indicator (Active/Idle with visual feedback)
- Stats should be visually distinct but not overwhelming

### 3.3 Quick Actions Menu (Priority: Medium)

- Add "..." overflow menu button near status controls
- Menu contains: Edit Agent, Duplicate, Export Config, Delete
- Confirmation dialog for destructive actions

### 3.4 Integrated Description (Priority: Medium)

- Move description into the main header card
- Make edit button more discoverable
- Support inline editing (click to edit, auto-save)

### 3.5 Eliminate Redundancy (Priority: Low)

- Remove duplicate type information (currently in badges AND collapsible)
- Consider removing collapsible "Agent Details" if info is elsewhere
- Consolidate hierarchy info into a tooltip or modal

## 4. User experience

### 4.1 Header Layout Mockup

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  cat facts only                          [● Running]  [■ Stop Agent] ⋮ │
│  gemini-2.0-flash · LLM                                                │
│                                                                         │
│  "Tells you a cat fact."                                         ✏️    │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  🔧 1 Tool        │      ⏱️ Last run: 2m ago      │      ✅ Active     │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Quick Actions Menu

```
┌──────────────────┐
│ ✏️  Edit Agent   │
│ 📋  Duplicate    │
│ 📤  Export JSON  │
│ ──────────────── │
│ 🗑️  Delete       │
└──────────────────┘
```

### 4.3 UI/UX Highlights

- Single-row status/action for compact header
- Stats bar provides at-a-glance metrics
- Overflow menu keeps interface clean while providing access to actions
- Description integrated rather than floating below

## 5. Technical considerations

### 5.1 Integration points

- `_display_agent_name.slim` - Agent identity section
- `_agent_status_controls.slim` - Status and action buttons
- `agent.slim` - Main layout and description
- `main.scss` - Header styling
- HTMX for inline editing and action confirmations

### 5.2 CSS Classes to Add/Modify

- `.agent-header-hero` - Simplified layout
- `.agent-header-row` - Horizontal status/action row
- `.agent-stats-bar` - New stats bar component
- `.agent-quick-actions` - Dropdown menu styling

### 5.3 Data Requirements

- Tool count (already available)
- Last run timestamp (may need backend support or use "N/A")
- Agent type and model (already available)

## 6. Milestones & sequencing

### 6.1 Project estimate

- Small-Medium: 2-3 days

### 6.2 Suggested phases

- **Phase 1: Layout Consolidation** (Task 62)
  - Streamline header to single-row status/action
  - Integrate description into header box
  
- **Phase 2: Stats Bar** (Task 63)
  - Add horizontal stats bar below description
  - Make tool count clickable
  
- **Phase 3: Quick Actions Menu** (Task 64)
  - Add overflow menu with common actions
  - Implement duplicate and export functionality

- **Phase 4: Polish & Cleanup** (Task 65)
  - Remove redundant information
  - Simplify or remove collapsible section
  - Final styling adjustments

## 7. User stories

### 7.1 Streamlined Header Controls

- **ID**: US-AH-001
- **Description**: As a developer, I want the status badge and action button on the same row so the header is more compact.
- **Acceptance Criteria**:
  - Status badge and Start/Stop button on same horizontal line
  - Header takes less vertical space than current design
  - Works in both light and dark modes

### 7.2 Meaningful Stats Bar

- **ID**: US-AH-002
- **Description**: As a developer, I want to see useful metrics at a glance so I can quickly understand agent activity.
- **Acceptance Criteria**:
  - Stats bar shows tool count, last run time, and status
  - Tool count is clickable and navigates to Tools tab
  - Stats bar is visually distinct but not overwhelming

### 7.3 Quick Actions Access

- **ID**: US-AH-003
- **Description**: As a developer, I want quick access to edit, duplicate, and delete actions without navigating away.
- **Acceptance Criteria**:
  - "..." menu button visible in header
  - Menu contains Edit, Duplicate, Export, Delete options
  - Delete shows confirmation before executing

### 7.4 Integrated Description

- **ID**: US-AH-004
- **Description**: As a developer, I want the description to be part of the main header so it's not visually disconnected.
- **Acceptance Criteria**:
  - Description displayed within the header card
  - Edit icon is clearly visible
  - Description can be edited inline


