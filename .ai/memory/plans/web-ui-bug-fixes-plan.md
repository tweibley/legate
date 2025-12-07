# PRD: Web UI Bug Fixes and Improvements

## 1. Product overview

### 1.1 Document title and version

- PRD: Web UI Bug Fixes and Improvements
- Version: 1.0

### 1.2 Product summary

This plan addresses critical bugs and polish issues discovered during a comprehensive review of the ADK Web UI. The primary issues include duplicate tools appearing in the tools list and agent creation form, a documentation encoding error, and various UI polish issues.

The most critical bug is the duplicate tool registration issue, where tools are registered twice under different names (e.g., both `random_number_tool` and `random_number` for the same tool class). This creates confusion for users and potential issues when assigning tools to agents.

## 2. Goals

### 2.1 Business goals

- Improve the reliability and usability of the ADK Web UI
- Eliminate confusing duplicate entries that could mislead users
- Ensure documentation is accessible without errors

### 2.2 User goals

- See a clean, deduplicated list of available tools
- Access documentation without encountering encoding errors
- Navigate the UI smoothly using navbar links

### 2.3 Non-goals

- Adding new features to the Web UI (this is bug fixes only)
- Redesigning the UI aesthetics
- Adding agent execution capabilities (separate future task)

## 3. User personas

### 3.1 Key user types

- ADK Developers building AI agents through the Web UI
- System administrators configuring agents and tools

### 3.2 Basic persona details

- **Developer**: Uses the Web UI to create and configure agent definitions, assign tools, and view documentation
- **Administrator**: Manages authentication schemes and monitors the system

### 3.3 Role-based access

- **All Users**: Full access to all Web UI features (no role-based restrictions currently)

## 4. Functional requirements

- **Fix Duplicate Tool Registration** (Priority: Critical)
  - Tools should only appear once in the global tool registry
  - The tool name should be the `explicit_tool_name` if set, otherwise the inferred name
  - Tools list should not show duplicates

- **Fix Documentation Encoding Error** (Priority: High)
  - Documentation scanner should handle non-ASCII characters gracefully
  - No errors should appear in logs when scanning documentation

- **Fix Navigation Links** (Priority: Medium)
  - Navbar links should navigate correctly when clicked
  - Remove any orphaned UI elements (Agent Execution Flow modal)

## 5. User experience

### 5.1 Entry points & first-time user flow

- Users access the Web UI at http://localhost:4567
- They navigate using the navbar links or homepage cards

### 5.2 Core experience

- **Tools Page**: Shows a deduplicated list of available tools with their descriptions and parameters
- **Documentation Page**: Displays all documentation without encoding errors
- **Navigation**: All navbar links work correctly

### 5.3 Advanced features & edge cases

- Tools with explicit names should use those names, not inferred class names
- Documentation files with special characters should be handled gracefully

### 5.4 UI/UX highlights

- Clean, professional tool listing without duplicates
- Smooth navigation between sections

## 6. Narrative

A developer opens the ADK Web UI to create a new agent. They navigate to the Agents page using the navbar link, which responds correctly. When selecting tools for their agent, they see a clean list of available tools without confusing duplicates. They can easily identify the tools they need and assign them. Later, they visit the Documentation page to learn about callbacks, and the page loads without errors.

## 7. Success metrics

### 7.1 User-centric metrics

- Zero duplicate tools displayed in UI
- All navbar links navigate correctly
- Documentation loads without errors

### 7.2 Business metrics

- Reduced user confusion and support requests

### 7.3 Technical metrics

- No encoding errors in server logs
- Tool registry contains only unique tool entries

## 8. Technical considerations

### 8.1 Integration points

- `lib/adk/tool.rb` - Tool inheritance hook
- `lib/adk/global_tool_manager.rb` - Global tool registration
- `lib/adk.rb` - Explicit tool registration
- `lib/adk/web/routes/documentation_routes.rb` - Documentation scanning

### 8.2 Data storage & privacy

- No data storage changes required

### 8.3 Scalability & performance

- No performance impact expected from these fixes

### 8.4 Potential challenges

- The tool registration timing issue requires careful handling to avoid breaking existing functionality
- Need to ensure backward compatibility with tools using old `define_metadata` API

## 9. Milestones & sequencing

### 9.1 Project estimate

- Small: 2-4 hours

### 9.2 Team size & composition

- Small Team: 1 person (1 Developer)

### 9.3 Suggested phases

- **Phase 1**: Fix duplicate tool registration (1-2 hours)
  - Key deliverables: Deduplicated tool registry, updated registration logic
- **Phase 2**: Fix documentation encoding (30 min)
  - Key deliverables: Graceful handling of encoding issues
- **Phase 3**: UI polish (30 min)
  - Key deliverables: Working navigation links

## 10. User stories

### 10.1 Deduplicated Tool List

- **ID**: US-001
- **Description**: As a developer, I want to see each tool listed only once so that I can clearly understand what tools are available without confusion.
- **Acceptance Criteria**:
  - Tools page shows no duplicate entries
  - Agent creation form tool checkboxes show no duplicates
  - Each tool appears with its correct name (explicit or inferred)

### 10.2 Error-Free Documentation

- **ID**: US-002
- **Description**: As a developer, I want the documentation page to load without errors so that I can access all available documentation.
- **Acceptance Criteria**:
  - Documentation page loads without server errors
  - No encoding errors in server logs
  - All documentation categories display correctly

### 10.3 Working Navigation

- **ID**: US-003
- **Description**: As a user, I want all navigation links to work correctly so that I can move between sections of the Web UI easily.
- **Acceptance Criteria**:
  - All navbar links navigate to the correct pages
  - No orphaned modals or UI elements interfere with navigation
  - Homepage card links work correctly

## 11. Root Cause Analysis

### 11.1 Duplicate Tool Registration Bug

**Problem**: Tools appear twice in the UI with different names (e.g., `random_number_tool` AND `random_number`).

**Root Cause**: The `Tool.inherited` hook in `lib/adk/tool.rb` is called when a tool class is **defined**, but this happens BEFORE the class body executes. This means:
1. When `RandomNumberTool` class definition starts, `inherited` is called
2. At this point, `explicit_tool_name` is still `nil`
3. Tool is registered under the inferred name: `random_number_tool`
4. Class body executes, sets `explicit_tool_name = :random_number`
5. Later in `lib/adk.rb`, explicit registration adds the tool again with name: `random_number`

**Evidence from logs**:
```
DEBUG: Tool subclass ADK::Tools::RandomNumberTool inherited. Attempting registration.
DEBUG: GlobalToolManager: Registered tool 'random_number_tool' with class ADK::Tools::RandomNumberTool.
...
DEBUG: GlobalToolManager: Registered tool 'random_number' with class ADK::Tools::RandomNumberTool.
```

**Solution Options**:
1. **Remove explicit registration from `lib/adk.rb`** and fix the `inherited` hook to defer registration
2. **Defer registration** until the tool class is first accessed/instantiated
3. **Use a post-class-load hook** like `TracePoint` to register after class body completes

### 11.2 Documentation Encoding Error

**Problem**: Error in logs: `invalid byte sequence in US-ASCII`

**Root Cause**: Documentation files contain non-ASCII characters (likely UTF-8), but the regex matching is done with US-ASCII encoding assumption.

**Solution**: Force UTF-8 encoding when reading/matching documentation files.

