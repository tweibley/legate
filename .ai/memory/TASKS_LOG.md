# Tasks Log

This document maintains a log of all tasks that have been completed or abandoned.

## Completed Tasks

### 2023-07-12
- **ID 1: Core Authentication Infrastructure** - Created foundational authentication classes and utilities.

### 2023-07-15
- **ID 2: Authentication Credential Management** - Implemented credential management system with secure storage.

### 2023-07-20
- **ID 3: Session Security Enhancement** - Enhanced SessionService::Redis with encryption for credentials.

### 2023-07-25
- **ID 4: Non-Interactive Authentication Flows** - Implemented API Key and Bearer token authentication.

### 2023-08-01
- **ID 5: OAuth2 Authentication Implementation** - Added OAuth2 authentication support with authorization code flow.

### 2023-08-10
- **ID 6: OpenID Connect Authentication Support** - Extended OAuth2 with OpenID Connect functionality.

### 2023-08-25
- **ID 8: Token Lifecycle Management** - Created TokenManager for handling token acquisition, refresh, and invalidation.

### 2023-08-30
- **ID 9: Fiber-based Authentication Flow** - Implemented fiber-based authentication system for interactive flows.

### 2025-12-05
- **ID 15: Authentication Web UI Integration** - Integrated ADK Authentication system into the Web UI with routes infrastructure, scheme management, credential management, URL mapping, testing tools, and agent integration (sub-tasks 15.1-15.6 all completed).
- **ID 24: Boats-for-Sale Example Agent with Puppeteer MCP** - Created comprehensive example agent demonstrating web scraping with Playwright MCP server for extracting boat listings from The Hull Truth forum, including Cloudflare challenge handling.
- **ID 25: Agent Authentication Runtime Integration** - Completed the missing runtime integration between Auth system and Agent/AgentDefinition. Added DSL methods (`use_credential`, `auth_mapping`, `auth_scheme`, `auth_credential`) to AgentDefinition, propagated auth config from Agent to ToolContext, and enabled agent-aware authentication lookups in handle_request_auth. 16 new tests added.
- **ID 26: Fix Duplicate Tool Registration Bug** - Fixed the bug where tools were registered twice with different names (e.g., `random_number_tool` AND `random_number`). Removed auto-registration from `Tool.inherited` hook since it runs before class body executes. Tools are now only registered explicitly in `lib/adk.rb`.
- **ID 27: Fix Documentation Encoding Error** - Fixed "invalid byte sequence in US-ASCII" error in documentation_routes.rb by adding `encoding: 'UTF-8'` to all `File.read` calls. Documentation now loads all 10 categories instead of just 2.
- **ID 28: Web UI Navigation and Polish Fixes** - Verified all navigation links work correctly. The "Agent Execution Flow" modal in DOM is the Mermaid diagram modal (intentionally hidden until triggered). No code changes needed.

## Abandoned Tasks

None so far.
