# PRD: Web UI Visual Enhancement

## 1. Product overview

### 1.1 Document title and version

- PRD: Web UI Visual Enhancement
- Version: 1.0

### 1.2 Product summary

This plan addresses the visual enhancement of the Ruby ADK Web UI to create a more modern, polished, and developer-friendly aesthetic. The current UI uses Bulma CSS with default styling, generic system fonts, and a flat design that lacks personality and visual engagement.

The enhancement focuses on establishing a proper theming system with CSS variables, implementing dark mode support, modernizing typography, refining the color palette to reflect the Ruby ADK brand identity, and adding subtle animations and micro-interactions to improve user experience.

This is primarily a CSS/styling overhaul with minimal template changes, ensuring backward compatibility while significantly improving the visual appeal.

## 2. Goals

### 2.1 Business goals

- Create a professional, polished developer tool appearance
- Establish a consistent visual brand identity for Ruby ADK
- Differentiate the product from generic admin dashboards

### 2.2 User goals

- Work in a comfortable environment with dark mode support
- Easily distinguish between different UI elements and states
- Enjoy a modern, visually appealing interface that reflects quality

### 2.3 Non-goals

- Complete UI redesign or restructuring
- Adding new features or functionality
- Changing the Bulma CSS framework
- JavaScript-heavy animations or interactions

## 3. User personas

### 3.1 Key user types

- Ruby developers building AI agents
- System administrators configuring agents and tools
- Technical users reviewing agent definitions and documentation

### 3.2 Basic persona details

- **Developer**: Spends significant time in the UI configuring agents, prefers dark mode, values clean code display
- **Administrator**: Quickly reviews system status, needs clear visual hierarchy to identify issues

### 3.3 Role-based access

- **All Users**: Full access to all visual features including theme toggle

## 4. Functional requirements

- **CSS Variable System** (Priority: Critical)
  - Define comprehensive color palette using CSS variables
  - Enable easy theming and maintenance
  - Support semantic color names (primary, success, danger, etc.)

- **Dark Mode Support** (Priority: High)
  - Implement theme toggle in navbar
  - Persist theme preference in localStorage
  - Define complete dark mode color palette
  - Ensure all components work in both themes

- **Typography Enhancement** (Priority: High)
  - Add Inter font for UI text
  - Add JetBrains Mono for code/monospace
  - Improve heading hierarchy and weights

- **Card & Component Refinement** (Priority: Medium)
  - Add hover lift animations to cards
  - Improve shadow depth and consistency
  - Add subtle accent borders to dashboard cards

- **Navigation Enhancement** (Priority: Medium)
  - Improve active state indicators
  - Add subtle glass effect
  - Consider environment status bar

- **Code Editor Theme** (Priority: Medium)
  - Apply darker theme to CodeMirror
  - Improve contrast for code readability

- **Toast/Notification Refinement** (Priority: Low)
  - Modern snackbar-style positioning
  - Subtle animations for appearance

## 5. User experience

### 5.1 Entry points & first-time user flow

- Users access the Web UI at configured port (default: 4567)
- Theme defaults to light mode on first visit
- Theme toggle visible in navbar for easy access

### 5.2 Core experience

- **Theme Toggle**: Click moon/sun icon in navbar to switch themes
- **Dashboard**: Cards with colored accent borders indicate sections
- **Navigation**: Active section clearly highlighted with underline
- **Code Editing**: Dark-themed code editor for better focus

### 5.3 Advanced features & edge cases

- Theme preference persists across sessions via localStorage
- Smooth transitions between themes (no flash)
- Print styles respect light mode for readability

### 5.4 UI/UX highlights

- Indigo primary color with Ruby red accent for brand identity
- Softer shadows and rounded corners for modern feel
- Subtle hover animations for interactive feedback
- JetBrains Mono font for developer-friendly code display

## 6. Narrative

A developer opens the Ruby ADK Web UI after a long day of coding in their dark-themed IDE. They immediately notice the moon icon in the navbar and click it to switch to dark mode, which matches their preferred coding environment. The interface feels polished and professional, with the agent cards featuring subtle Ruby-red accent lines that align with the ADK brand. When they hover over a card to navigate to the Agents section, it lifts slightly, providing satisfying feedback. The code editor shows their agent configuration in a dark theme with excellent syntax highlighting, making it easy to review and edit JSON configurations without eye strain.

## 7. Success metrics

### 7.1 User-centric metrics

- Theme toggle usage rate (dark vs light preference)
- User time spent in UI (engagement)

### 7.2 Business metrics

- Reduced complaints about UI appearance
- Positive feedback on professional appearance

### 7.3 Technical metrics

- CSS file size remains reasonable (<50KB)
- No layout shifts during theme toggle
- All Lighthouse accessibility scores maintained

## 8. Technical considerations

### 8.1 Integration points

- `lib/adk/web/views/layout.slim` - Font loading, theme toggle
- `lib/adk/web/public/styles/main.scss` - CSS variable system
- `lib/adk/web/public/css/main.css` - Compiled CSS output
- `lib/adk/web/views/index.slim` - Dashboard card enhancements

### 8.2 Data storage & privacy

- Theme preference stored in browser localStorage only
- No server-side storage required

### 8.3 Scalability & performance

- CSS variables enable efficient theming without JavaScript
- Minimal performance impact from animations (GPU-accelerated transforms)
- Font loading optimized with display=swap

### 8.4 Potential challenges

- Ensuring all Bulma components work with CSS variable overrides
- Testing all existing views in both themes
- CodeMirror theme integration may require additional CSS

## 9. Milestones & sequencing

### 9.1 Project estimate

- Small-Medium: 4-8 hours

### 9.2 Team size & composition

- Small Team: 1 Developer

### 9.3 Suggested phases

- **Phase 1**: Foundation (1-2 hours) ✅ COMPLETED
  - Key deliverables: CSS variables system, Google Fonts integration, base typography
- **Phase 2**: Dark Mode (1-2 hours) ✅ COMPLETED
  - Key deliverables: Theme toggle, dark mode variables, localStorage persistence
- **Phase 3**: Component Refinement (1-2 hours) ✅ COMPLETED
  - Key deliverables: Card hover effects, navigation enhancement, button polish
- **Phase 4**: Specialized Components (1-2 hours) ✅ COMPLETED
  - Key deliverables: CodeMirror theme, toast refinement, dashboard cards
- **Phase 5**: Dark Mode Stabilization (1-2 hours)
  - Key deliverables: Fix inline styles in chat.slim, chat message dark mode colors, tag/notification styling

## 10. User stories

### 10.1 Theme Toggle

- **ID**: US-001
- **Description**: As a developer, I want to toggle between light and dark themes so that I can work comfortably in different lighting conditions.
- **Acceptance Criteria**:
  - Theme toggle button visible in navbar
  - Clicking toggle switches theme immediately
  - Theme preference persists across browser sessions
  - No flash of wrong theme on page load

### 10.2 Modern Typography

- **ID**: US-002
- **Description**: As a user, I want the UI to use professional, readable fonts so that the interface feels polished and is easy to read.
- **Acceptance Criteria**:
  - Inter font loaded and applied to UI text
  - JetBrains Mono used for code/monospace elements
  - Heading hierarchy clear with appropriate weights
  - Fonts load efficiently with no layout shift

### 10.3 Interactive Cards

- **ID**: US-003
- **Description**: As a user, I want dashboard cards to respond to my interactions so that I know they are clickable.
- **Acceptance Criteria**:
  - Cards lift slightly on hover (translateY)
  - Shadow increases on hover
  - Transition is smooth (not jarring)
  - Works in both light and dark themes

### 10.4 Code Editor Theming

- **ID**: US-004
- **Description**: As a developer, I want the code editor to use a dark theme so that it's easier on my eyes and distinguishable from regular UI.
- **Acceptance Criteria**:
  - CodeMirror uses dark theme (Catppuccin-inspired)
  - Syntax highlighting is clear and readable
  - Theme works in both light and dark UI modes
  - Cursor and selection visible

### 10.5 Brand Identity

- **ID**: US-005
- **Description**: As a user, I want the UI to reflect the Ruby ADK brand so that it feels cohesive and professional.
- **Acceptance Criteria**:
  - Primary color is Indigo (professional)
  - Ruby red accent used for brand touches
  - Dashboard cards have colored accent borders
  - Overall aesthetic is consistent across pages

### 10.6 Dark Mode Consistency

- **ID**: US-006
- **Description**: As a developer using dark mode, I want all UI elements to have proper dark mode styling so that there are no jarring bright elements.
- **Acceptance Criteria**:
  - Chat interface uses dark mode colors (no inline hardcoded colors)
  - Chat messages (success, warning, danger) have dark mode variants
  - Tags and badges adapt to dark mode
  - All containers and backgrounds respect theme variables

## 11. Implementation details

### 11.1 CSS Variable Structure

```scss
:root {
  // Brand colors
  --color-primary: hsl(230, 70%, 55%);      // Indigo
  --color-accent: hsl(354, 80%, 50%);       // Ruby red
  
  // Semantic colors
  --color-success: hsl(152, 68%, 40%);
  --color-warning: hsl(38, 92%, 50%);
  --color-danger: hsl(0, 72%, 51%);
  --color-info: hsl(201, 96%, 46%);
  
  // Neutrals (light mode)
  --color-bg-primary: #f4f6f8;
  --color-bg-secondary: #ffffff;
  --color-text-primary: #1a202c;
  --color-border: #e2e8f0;
  
  // Shadows
  --shadow-md: 0 4px 12px rgba(0, 0, 0, 0.08);
}

[data-theme="dark"] {
  --color-bg-primary: #0f1419;
  --color-bg-secondary: #1a1f26;
  --color-text-primary: #e7e9ea;
  --color-border: #2f3943;
}
```

### 11.2 Theme Toggle JavaScript

```javascript
// Check for saved theme or system preference
const savedTheme = localStorage.getItem('theme');
const systemPrefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
const theme = savedTheme || (systemPrefersDark ? 'dark' : 'light');
document.documentElement.setAttribute('data-theme', theme);

// Toggle function
function toggleTheme() {
  const current = document.documentElement.getAttribute('data-theme');
  const next = current === 'dark' ? 'light' : 'dark';
  document.documentElement.setAttribute('data-theme', next);
  localStorage.setItem('theme', next);
}
```

### 11.3 Files to Modify

| File | Changes |
|------|---------|
| `layout.slim` | Add Google Fonts, theme toggle button, theme initialization script |
| `main.scss` | Add CSS variables, dark mode variables, component refinements |
| `index.slim` | Add dashboard card accent classes |
| `main.css` | Compiled output (auto-generated from SCSS) |

