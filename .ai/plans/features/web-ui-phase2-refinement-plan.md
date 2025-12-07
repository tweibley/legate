# PRD: Web UI Phase 2 Refinement

## 1. Product overview

### 1.1 Document title and version

- PRD: Web UI Phase 2 Refinement
- Version: 1.0

### 1.2 Product summary

This plan addresses the second phase of Web UI improvements for the Ruby ADK, building upon the completed Phase 1 dark mode and theming foundation (Tasks 29-38). The focus is on elevating the UI from "functional developer tool" to "polished product" through typography differentiation, dashboard interactivity, accessibility fixes, and brand alignment.

This phase consolidates recommendations from two independent design reviews, prioritizing pragmatic UX improvements (live metrics, activity streams, accessibility) alongside brand differentiation (typography, color palette, logo).

The changes are primarily CSS/SCSS and template modifications, with some light JavaScript for dynamic dashboard content.

## 2. Goals

### 2.1 Business goals

- Differentiate Ruby ADK from generic "AI slop" admin dashboards
- Establish a distinctive visual identity tied to the Ruby gem brand
- Improve perceived quality and professionalism of the product

### 2.2 User goals

- Quickly understand system status at a glance from the dashboard
- Work comfortably in dark mode without contrast or visibility issues
- Experience a distinctive, memorable interface that feels crafted

### 2.3 Non-goals

- Adding new features or functionality beyond visual/UX improvements
- Complete redesign of page layouts or information architecture
- Heavy JavaScript animations or complex micro-interactions
- Over-engineered visual effects (noise textures, ripple effects, etc.)

## 3. User personas

### 3.1 Key user types

- Ruby developers building AI agents
- System administrators monitoring agent status
- Technical users configuring tools and authentication

### 3.2 Basic persona details

- **Developer**: Values distinctive design, spends time in IDE so appreciates professional tools that don't look generic
- **Administrator**: Needs at-a-glance system status, values clear visual hierarchy

### 3.3 Role-based access

- **All Users**: Full access to all visual features

## 4. Functional requirements

- **Typography Differentiation** (Priority: High)
  - Replace Inter with a distinctive font (Geist, DM Sans, or Satoshi)
  - Maintain JetBrains Mono for code/monospace
  - Update font-stack in CSS variables

- **Dashboard Live Metrics** (Priority: High)
  - Transform static "View Agents" cards into live widgets showing counts
  - Display "X Agents Running" instead of just "View Agents"
  - Show recent activity summary on homepage

- **Dark Mode Accessibility Fix** (Priority: High)
  - Fix muted text contrast in dark mode (#6b7280 → #9ca3af)
  - Ensure WCAG AA compliance for text contrast

- **Brand Logo Integration** (Priority: Medium)
  - Add Ruby gem icon next to "Ruby ADK" in navbar
  - Use SVG or Font Awesome ruby icon

- **Ruby-Inspired Color Palette** (Priority: Medium)
  - Shift primary color from generic indigo to ruby red
  - Add warm gold accent color for complements
  - Update CSS variables throughout

- **Card Hover Enhancement** (Priority: Low)
  - Standardize hover lift effect (translateY -5px)
  - Increase shadow on hover for tactile feedback

- **Table Row Hover Accent** (Priority: Low)
  - Add left-border accent on table row hover
  - Visual indication of active row selection

- **Empty State Designs** (Priority: Low)
  - Add friendly icons and CTA buttons to empty lists
  - Guide new users with "Create your first Agent" prompts

## 5. User experience

### 5.1 Entry points & first-time user flow

- User arrives at dashboard and immediately sees live agent count
- Empty state prompts guide new users to create first agent
- Distinctive typography signals this is a crafted product

### 5.2 Core experience

- **Dashboard**: Live metrics show "3 Running Agents" instead of static labels
- **Navigation**: Ruby gem icon reinforces brand identity
- **Tables**: Row hover accent provides clear selection feedback
- **Empty States**: Friendly prompts with CTAs reduce confusion

### 5.3 Advanced features & edge cases

- Dashboard metrics update on page load (not real-time SSE)
- Empty states gracefully handle zero items in all list views
- Font fallbacks ensure readability if web fonts fail to load

### 5.4 UI/UX highlights

- Distinctive font creates immediate visual differentiation
- Ruby red primary color aligns with product naming
- Live metrics transform passive dashboard into active monitoring tool
- Improved contrast ensures accessibility in dark mode

## 6. Narrative

A developer discovers Ruby ADK and navigates to the web interface. Instead of seeing another generic admin dashboard with the same Inter font and purple gradients they've seen dozens of times, they're greeted by a distinctive, ruby-red themed interface that immediately feels crafted and intentional. The dashboard shows "2 Agents Running" and "Last activity: 3 minutes ago," giving them instant context without clicking through. The small ruby gem icon in the navbar reinforces this isn't just another tool—it's the Ruby ADK. When they switch to dark mode for their evening coding session, the text remains crisp and readable, with proper contrast throughout. The interface feels like it was designed by developers who care about the details.

## 7. Success metrics

### 7.1 User-centric metrics

- Time to first meaningful action reduced (dashboard provides context)
- Reduced confusion for new users (empty states with guidance)
- Accessibility compliance maintained (WCAG AA contrast)

### 7.2 Business metrics

- Positive feedback on distinctive appearance
- Brand recognition improved (ruby theme associations)

### 7.3 Technical metrics

- CSS file size increase <10KB
- Lighthouse accessibility score ≥90
- No layout shifts from font loading

## 8. Technical considerations

### 8.1 Integration points

- `lib/adk/web/views/layout.slim` - Font loading, navbar logo
- `lib/adk/web/public/styles/main.scss` - CSS variable updates
- `lib/adk/web/views/index.slim` - Dashboard live metrics
- `lib/adk/web/app.rb` - Backend data for dashboard metrics
- Various list views - Empty state templates

### 8.2 Data storage & privacy

- No additional data storage required
- Dashboard metrics derived from existing DefinitionStore

### 8.3 Scalability & performance

- Dashboard metrics computed server-side on page load
- Font loading optimized with font-display: swap
- CSS changes have minimal performance impact

### 8.4 Potential challenges

- Selecting a font that's distinctive but still readable
- Balancing ruby-red primary color with existing semantic colors
- Ensuring dashboard metrics are accurate without adding complexity

## 9. Milestones & sequencing

### 9.1 Project estimate

- Small: 3-5 hours

### 9.2 Team size & composition

- Small Team: 1 Developer

### 9.3 Suggested phases

- **Phase 1**: Foundation (1 hour) ✅ COMPLETED
  - Key deliverables: Typography change, dark mode contrast fix
- **Phase 2**: Dashboard Enhancement (1-2 hours) ✅ COMPLETED
  - Key deliverables: Live metrics, activity summary, empty states
- **Phase 3**: Brand Polish (1 hour) ✅ COMPLETED
  - Key deliverables: Logo integration, color palette shift, hover refinements

**All phases completed on 2025-12-07.**

## 10. User stories

### 10.1 Distinctive Typography

- **ID**: US-P2-001
- **Description**: As a user, I want the UI to use a distinctive font so that Ruby ADK feels unique and not like another generic dashboard.
- **Acceptance Criteria**:
  - Primary font changed from Inter to Geist, DM Sans, or Satoshi
  - Font loads efficiently with no layout shift
  - Fallback stack ensures readability if font fails
  - JetBrains Mono retained for code elements

### 10.2 Live Dashboard Metrics

- **ID**: US-P2-002
- **Description**: As a user, I want the dashboard to show live agent counts so that I understand system status at a glance.
- **Acceptance Criteria**:
  - Dashboard cards show "X Agents Running" with actual count
  - Tools count displayed on tools card
  - Authentication schemes count displayed
  - Metrics update on page refresh

### 10.3 Dark Mode Contrast Fix

- **ID**: US-P2-003
- **Description**: As a developer using dark mode, I want muted text to be readable so that I don't strain my eyes.
- **Acceptance Criteria**:
  - `--color-text-muted` in dark mode changed from #6b7280 to #9ca3af
  - All muted text passes WCAG AA contrast ratio (4.5:1)
  - No visibility issues with secondary content

### 10.4 Brand Logo

- **ID**: US-P2-004
- **Description**: As a user, I want a visual logo in the navbar so that the brand identity is clear and memorable.
- **Acceptance Criteria**:
  - Ruby gem icon displayed next to "Ruby ADK" text
  - Icon visible in both light and dark modes
  - Icon sized appropriately for navbar

### 10.5 Ruby Color Palette

- **ID**: US-P2-005
- **Description**: As a user, I want the UI colors to reflect the "Ruby" brand so that the visual identity is cohesive.
- **Acceptance Criteria**:
  - Primary color shifted to ruby red (hsl ~348)
  - Accent color updated to warm gold
  - Existing semantic colors (success, warning, danger) preserved
  - Both light and dark mode palettes updated

### 10.6 Empty State Guidance

- **ID**: US-P2-006
- **Description**: As a new user, I want helpful prompts when lists are empty so that I know what to do next.
- **Acceptance Criteria**:
  - Agents list shows "Create your first Agent" when empty
  - Includes icon and CTA button
  - Works in both light and dark modes

### 10.7 Enhanced Card Hover

- **ID**: US-P2-007
- **Description**: As a user, I want cards to respond to hover so that I know they are interactive.
- **Acceptance Criteria**:
  - Dashboard cards lift 5px on hover (translateY)
  - Shadow increases on hover
  - Transition is smooth (250ms ease)

### 10.8 Table Row Hover Accent

- **ID**: US-P2-008
- **Description**: As a user, I want a visual indicator when hovering table rows so that I can track my selection.
- **Acceptance Criteria**:
  - Table rows show left-border accent (3px) on hover
  - Accent uses primary color
  - Works in Agents, Tools, and other list tables

## 11. Implementation details

### 11.1 Font Change

```scss
// In main.scss :root
--font-sans: 'DM Sans', -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;

// In layout.slim
link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap"
```

### 11.2 Dark Mode Contrast Fix

```scss
[data-theme="dark"] {
  --color-text-muted: #9ca3af;  // Upgraded from #6b7280
}
```

### 11.3 Ruby Color Palette

```scss
:root {
  --color-primary: hsl(348, 83%, 47%);        // Ruby red
  --color-primary-dark: hsl(348, 83%, 40%);
  --color-primary-light: hsl(348, 83%, 95%);
  --color-accent: hsl(38, 92%, 50%);          // Warm gold
}
```

### 11.4 Dashboard Metrics (in app.rb)

```ruby
# In index route
@agent_count = Adk.definition_store.definitions.count
@running_count = Adk.definition_store.definitions.count { |d| d.running? }
@tool_count = Adk.tool_manager.tools.count
```

### 11.5 Files to Modify

| File | Changes |
|------|---------|
| `layout.slim` | Font loading (DM Sans), navbar logo icon |
| `main.scss` | Font variable, contrast fix, color palette, table hover |
| `index.slim` | Dashboard metrics display, card hover classes |
| `app.rb` | Dashboard metrics computation |
| Agent/Tool list views | Empty state templates |

