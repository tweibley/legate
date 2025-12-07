# Ruby ADK Project Plan

## Overview

The Ruby Agent Development Kit (ADK) is a comprehensive Ruby framework for building and managing AI agents. This document serves as the central index to all feature plans and tracks the overall project vision.

## Core Goals

- Provide a robust, developer-friendly framework for AI agent development in Ruby
- Offer a polished Web UI for managing agents, tools, and authentication
- Support multiple authentication schemes for external service integration
- Enable flexible agent architectures including sequential, parallel, and hierarchical patterns

## Feature Plans

### Completed

- **[Authentication System](features/add-authentication-plan-revised.md)** - Comprehensive authentication infrastructure including OAuth2, OIDC, API keys, and service accounts
- **[Authentication Scheme Cleanup](features/authentication-scheme-cleanup-plan.md)** - Standardization and cleanup of authentication implementations
- **[Web UI Enhancement Phase 1](features/web-ui-enhancement-plan.md)** - Dark mode, typography, theming foundation (Tasks 29-38)
- **[Web UI Phase 2 Refinement](features/web-ui-phase2-refinement-plan.md)** - Typography differentiation, live dashboard metrics, brand alignment, accessibility fixes (Tasks 39-45)

### Planned

- **[Agent Hierarchy Improvements](features/agent-hierarchy-improvements-plan.md)** - Enhanced agent-to-agent communication and delegation patterns

## Task Overview

See `.ai/TASKS.md` for the current task checklist and status.

## Architecture

The Ruby ADK consists of several key components:

- **Agent Framework** - Core classes for defining and running AI agents
- **Tool System** - Extensible tool definitions and execution
- **Authentication** - Multi-scheme auth with credential management
- **Web UI** - Sinatra-based management interface
- **Session Management** - Redis-backed session and state storage

