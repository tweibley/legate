## 0.6.6 / 2025-12-09

* Features
  * **Authentication System:**
    * Implemented comprehensive Authentication Manager supporting multiple schemes (API Key, Bearer, OAuth2, OIDC, Service Account).
    * Added Token Lifecycle Management (acquisition, storage, expiration, refresh).
    * Added Web UI for managing authentication schemes, credentials, and URL mappings.
    * Added Authentication Testing Dashboard for credential verification and flow simulation.
  * **Web UI Enhancements:**
    * Redesigned Dashboard with improved layout and live metrics.
    * Integrated "AI Builder" for automated Agent and Tool generation.
    * Improved "Execute" tab with vertical layout and terminal-style output.
    * Enhanced Chat UI with better formatting, timestamps, and history visualization.
    * Added "Last Run" timestamp tracking for agents.
    * Implemented auto-loading for custom tools and agents on startup.
  * **Documentation:**
    * Major overhaul of `AGENTS.md` to serve as a comprehensive Agent Orientation Guide.
    * Added Distributed Deployment Guide for multi-VM scenarios.
    * Expanded Authentication documentation including migration guides and API references.
  * **Core:**
    * Updated default Gemini models to latest versions.
    * Implemented persistence for Authentication Manager state.

* Bugfixes
  * Fixed agent status persistence across server restarts.
  * Fixed chat message styling and border consistency.
  * Fixed terminal output overflow in Web UI.
  * Resolved inconsistencies in `AGENTS.md`.

* Refactor
  * Refactored CLI chat interface for improved user experience.
  * Standardized authentication scheme naming (HTTPBearer) across codebase.
  * Improved project documentation structure.

## 0.6.3 / 2024-05-19

* Features
  * Implemented comprehensive callback system for agents:
    * Agent lifecycle callbacks (before_agent_callback, after_agent_callback)
    * Model interaction callbacks (before_model_callback, after_model_callback)
    * Tool execution callbacks (before_tool_callback, after_tool_callback)
  * Added Multi-Agent Systems (MAS) support:
    * Agent hierarchy with parent-child relationships
    * Agent delegation capabilities
    * Support for specialized workflow agents
  * Enhanced Web UI:
    * Added agent hierarchy display and editing
    * Improved agent type selection and configuration
    * HTMX-based dynamic UI updates for smoother user experience
    * Support for workflow-specific agent configurations

* Bugfixes
  * Fixed agent hierarchy UI to prevent self-reference in sub-agent selection
  * Fixed agent type edit form to correctly default to current agent type
  * Fixed sub-agent clearing when switching agent types
  * Corrected backward compatibility in Redis store for agent hierarchies
  * Fixed agent hierarchy update route errors

* Refactor
  * Modularized callback implementation
  * Improved agent hierarchy navigation with methods like find_sub_agent and root_agent
  * Enhanced agent definition store to support sub_agent_names field

* Test
  * Added comprehensive tests for callback functionality
  * Added tests for agent hierarchy methods
  * Improved test isolation and reliability

## 0.5.9 / 2024-05-05

* Features
  * Enhanced web UI with improved agent visualization and interaction
  * Added support for more configurable agent parameters
  * Improved session management and persistence

* Bugfixes
  * Fixed UI rendering issues
  * Addressed edge cases in tool execution
  * Fixed session handling errors

## 0.5.8 / 2024-05-05

* Features
  * Expanded tool registry capabilities
  * Improved error handling in agent execution
  * Enhanced documentation

* Bugfixes
  * Fixed tool parameter validation
  * Corrected session persistence issues

## 0.5.7 / 2024-05-04

* Features
  * Added improved agent definition management
  * Enhanced CLI functionality
  * Better support for external tool integration

* Bugfixes
  * Fixed agent initialization edge cases
  * Corrected tool registry issues

## 0.5.6 / 2024-05-02

* Features
  * Added Redis session persistence improvements
  * Enhanced tool execution logging
  * Improved error reporting

## 0.5.4 / 2024-04-30

* Features
  * Added better support for model configuration
  * Improved tool discovery and registration
  * Enhanced web UI responsiveness

* Bugfixes
  * Fixed session state management issues
  * Corrected tool execution edge cases

## 0.5.0 / 2024-04-29

* Features
  * Added MCP client/server adapters for external tool/agent interoperability
  * Improved agent fallback logic
  * Enhanced session management and event tracking

* Bugfixes
  * Fixed tool registry issues
  * Addressed agent execution and session service bugs

* Refactor
  * Improved agent/tool initialization and error handling

## 0.3.0 / 2024-04-29

* Features
  * Added improved tool registry with better metadata
  * Enhanced web UI with more interactive features
  * Added better session management

* Bugfixes
  * Fixed agent execution flow issues
  * Corrected tool parameter handling

## 0.1.0 / 2024-04-16

* Initial release
  * Core agent, tool, and session management
  * Basic CLI and web UI
  * Tool registration and execution
  * LLM-powered planning and multi-step execution
  * Redis and in-memory session support
  * Basic test suite and documentation 