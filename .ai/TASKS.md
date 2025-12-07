# Project Tasks

- [x] **ID 1: Core Authentication Infrastructure** (Priority: critical)
> Create the foundational classes and utilities for the authentication system, including abstract base classes, error handling, and security utilities.

- [x] **ID 2: Authentication Credential Management** (Priority: high)
> Dependencies: 1
> Implement the credential management system with environment variable resolution and secure storage.

- [x] **ID 3: Session Security Enhancement** (Priority: critical)
> Dependencies: 1
> Enhance the SessionService::Redis to securely store sensitive credentials with encryption.

- [x] **ID 4: Non-Interactive Authentication Flows** (Priority: high)
> Dependencies: 1, 2, 3
> Implement API Key and HTTP Bearer authentication schemes for non-interactive authentication.

- [x] **ID 5: OAuth2 Authentication Implementation** (Priority: high)
> Dependencies: 1, 2, 3
> Implement the OAuth2 authentication scheme and flows, focusing on the interactive authorization code flow.

- [x] **ID 6: OpenID Connect Authentication Support** (Priority: medium)
> Dependencies: 5
> Add support for OpenID Connect authentication, extending the OAuth2 implementation.

- [x] **ID 7: Service Account Authentication** (Priority: medium)
> Dependencies: 1, 2, 3
> Implement service account authentication flow with automatic token exchange and refresh.

- [x] **ID 8: Token Lifecycle Management** (Priority: high)
> Dependencies: 3, 4, 5
> Create token lifecycle management for handling token expiration, refresh, and invalidation.

- [x] **ID 9: Fiber-based Authentication Flow** (Priority: critical)
> Dependencies: 1, 2, 5
> Implement the Fiber-based control flow for interactive authentication in the ADK Runner.

- [x] **ID 10: Integration with Tool Context** (Priority: high)
> Dependencies: 1, 9
> Enhance the ToolContext with authentication methods for tool-side handling.

- [x] **ID 11: Excon Middleware for Authentication** (Priority: medium)
> Dependencies: 4, 5, 7
> Create Excon middleware for automatically injecting authentication headers.

- [x] **ID 12: Authentication System Testing** (Priority: high)
> Dependencies: 4, 5, 6, 7, 9
> Implement comprehensive tests for the authentication system, including mock OAuth providers.

- [x] **ID 13: Authentication System Documentation** (Priority: high)
> Dependencies: 4, 5, 6, 7, 8, 9, 10, 11, 12
> Create comprehensive documentation for the authentication system, explaining concepts, workflows, and security considerations.

- [x] **ID 14: Authentication Examples Implementation** (Priority: high)
> Dependencies: 4, 5, 6, 7, 8, 9, 10, 11, 12
> Create comprehensive examples demonstrating each authentication scheme and common usage patterns.
> 
> Progress:
> - [x] API Key authentication example
> - [x] HTTP Bearer authentication example
> - [x] OAuth2 authentication example
> - [x] OpenID Connect (OIDC) authentication example
> - [x] Service Account authentication example (existing example reviewed)
> - [x] Google Service Account authentication example (included in service_account.rb)
> - [x] Example showing token lifecycle management
> - [x] Example showing integration with Excon middleware (existing example reviewed)
> - [x] Example showing custom authentication flows

- [x] **ID 15: Authentication Web UI Integration** (Priority: high)
> Dependencies: 5, 6, 7, 9, 10
> Integrate the ADK Authentication system into the Web UI to provide developers with tools for configuring, testing, and debugging authentication schemes that agents use when making requests to external services. (Expanded into sub-tasks 15.1-15.6 - ALL COMPLETE)

- [x] **ID 15.1: Authentication Routes Infrastructure** (Priority: high)
> Dependencies: 5, 6, 7, 9, 10
> Create the core authentication routes module and basic integration with the existing web UI architecture.

- [x] **ID 15.2: Authentication Scheme Management UI** (Priority: high)
> Dependencies: 15.1
> Build UI for viewing and managing authentication schemes available in the authentication manager.

- [x] **ID 15.3: Credential Management Interface** (Priority: high)
> Dependencies: 15.1
> Create secure interface for adding, editing, and managing authentication credentials.

- [x] **ID 15.4: URL Mapping Management Interface** (Priority: medium)
> Dependencies: 15.2, 15.3
> Build interface for configuring URL to authentication scheme/credential mappings.

- [x] **ID 15.5: Authentication Testing Tools** (Priority: high)
> Dependencies: 15.2, 15.3
> Create testing and validation interfaces for verifying authentication configurations work correctly.

- [x] **ID 15.6: Agent Authentication Integration** (Priority: medium)
> Dependencies: 15.4, 15.5
> Integrate authentication management with agent configuration and provide agent-specific authentication features.

- [x] **ID 16: Fix Orphaned OIDC Scheme Integration** (Priority: critical)
> Dependencies: 4, 5, 6
> Integrate the orphaned OIDC authentication scheme into the main schemes loader and ensure all references work consistently.

- [x] **ID 17: Resolve Bearer Token Implementation Duplication** (Priority: high)
> Dependencies: 4
> Choose a canonical Bearer token implementation, remove duplicates, and ensure consistent interfaces across the authentication system.

- [x] **ID 18: Fix Service Account Scheme Loading** (Priority: high)
> Dependencies: 7
> Properly integrate both ServiceAccount and GoogleServiceAccount schemes into the main schemes loader to make them available through the standard factory.

- [x] **ID 19: Standardize HTTPBearer Naming** (Priority: medium)
> Dependencies: 17
> Standardize all references to use consistent class names (HTTPBearer vs HttpBearer) across the codebase.

- [x] **ID 20: Ensure Credential Type Consistency** (Priority: high)
> Dependencies: 16, 17, 18
> Align credential auth_types with actually available schemes and fix any mismatches between credential types and scheme availability.

- [x] **ID 21: Complete Test Coverage for All Schemes** (Priority: high)
> Dependencies: 16, 17, 18
> Add comprehensive tests for all authentication schemes that should be available and remove tests for deprecated schemes.

- [x] **ID 22: Update Documentation and Examples** (Priority: medium)
> Dependencies: 16, 17, 18, 19, 20
> Update all documentation and examples to reference only canonical, working authentication schemes with consistent naming.

- [x] **ID 23: Validate Authentication Manager Integration** (Priority: medium)
> Dependencies: 16, 17, 18, 20
> Ensure the authentication manager properly registers and provides access to all supported schemes without referencing orphaned implementations.

- [x] **ID 24: Boats-for-Sale Example Agent with Puppeteer MCP** (Priority: medium)
> Create a comprehensive example agent that demonstrates web scraping capabilities using the Puppeteer MCP server to extract boat listing information from The Hull Truth forum.

- [x] **ID 25: Agent Authentication Runtime Integration** (Priority: critical)
> Complete the missing runtime integration between the Authentication system and Agent/AgentDefinition. Add DSL methods (`use_credential`, `auth_mapping`) to AgentDefinition, propagate auth config from Agent to ToolContext, and enable agent-aware authentication lookups. This closes the gap where Web UI auth assignments are stored but not used at runtime.

*Tasks 26-28 (Web UI Bug Fixes) completed and archived on 2025-12-05.*

---

## Web UI Visual Enhancement Tasks

- [x] **ID 29: CSS Variable System Foundation** (Priority: critical)
> Establish the CSS variable system in main.scss for comprehensive theming support. Define color palette, shadows, radii, and transitions as CSS custom properties.

- [x] **ID 30: Typography & Font Integration** (Priority: high)
> Dependencies: 29
> Add Google Fonts (Inter, JetBrains Mono) to layout.slim and update main.scss to apply fonts throughout the UI with proper fallbacks.

- [x] **ID 31: Dark Mode Implementation** (Priority: high)
> Dependencies: 29, 30
> Implement dark mode with theme toggle in navbar, localStorage persistence, and complete dark mode CSS variable palette.

- [x] **ID 32: Card & Component Refinement** (Priority: medium)
> Dependencies: 29
> Add hover lift animations, improved shadows, and accent borders to cards. Refine buttons, inputs, and table styling.

- [x] **ID 33: Navigation Enhancement** (Priority: medium)
> Dependencies: 29, 31
> Improve navbar active state indicators, add subtle refinements, and ensure navigation works in both themes.

- [x] **ID 34: CodeMirror Theme Integration** (Priority: medium)
> Dependencies: 31
> Apply a dark theme to CodeMirror editors for better code visibility and developer experience.

- [x] **ID 35: Dashboard Homepage Refresh** (Priority: low)
> Dependencies: 29, 32
> Update index.slim dashboard cards with accent borders and enhanced visual hierarchy.

---

## Dark Mode Stabilization Tasks

- [x] **ID 36: Chat Interface Dark Mode Fix** (Priority: high)
> Dependencies: 31
> Remove inline hardcoded colors from chat.slim (lines 70, 84, 151) and replace with CSS variables. Fix `#f5f5f5` backgrounds and `#dbdbdb` borders.

- [x] **ID 37: Chat Message Dark Mode Variants** (Priority: high)
> Dependencies: 31, 36
> Add dark mode variants for chat messages (user messages, agent messages with success/warning/danger/light states). Update pastel backgrounds to darker colors with appropriate text contrast.

- [x] **ID 38: Tags & Badges Dark Mode Styling** (Priority: medium)
> Dependencies: 31
> Add dark mode styling for Bulma tags (like "Running", "gemini-2.0-flash", "cat_facts") so they don't appear jarringly bright against dark backgrounds.

---

## Web UI Phase 2 Refinement Tasks

- [x] **ID 39: Typography Differentiation** (Priority: high)
> Replace the generic Inter font with a distinctive typeface (DM Sans, Geist, or Satoshi) to differentiate Ruby ADK from generic admin dashboards.

- [x] **ID 40: Dark Mode Contrast Fix** (Priority: high)
> Fix muted text contrast in dark mode (#6b7280 → #9ca3af) for WCAG AA accessibility compliance.

- [x] **ID 41: Dashboard Live Metrics** (Priority: high)
> Transform static dashboard cards into live status displays showing counts ("3 Agents Running") for at-a-glance system status.

- [x] **ID 42: Navbar Brand Logo** (Priority: medium)
> Add a Ruby gem icon next to "Ruby ADK" in the navbar to strengthen brand identity.

- [x] **ID 43: Ruby-Inspired Color Palette** (Priority: medium)
> Dependencies: 39, 40
> Shift primary color from generic indigo to ruby red to align with "Ruby ADK" brand identity.

- [x] **ID 44: Empty State Designs** (Priority: low)
> Add friendly empty state designs with icons and CTA buttons to list pages when no items exist.

- [x] **ID 45: Table Row Hover Accent** (Priority: low)
> Dependencies: 43
> Add a subtle left-border accent on table row hover for clear visual feedback in list tables.
