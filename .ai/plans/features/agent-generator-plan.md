# PRD: AI-Powered Code Generator

## 1. Product overview

### 1.1 Document title and version

- PRD: AI-Powered Code Generator
- Version: 1.1

### 1.2 Product summary

The AI-Powered Code Generator is a new feature for the ADK Web UI that enables users to create complete Ruby code from natural language descriptions. The feature has two components:

1. **Agent Generator** (on Agents page): Generate complete `AgentDefinition` code including any type of agent (LLM, sequential, parallel, loop), with full support for webhooks, callbacks, delegation, and all DSL options.

2. **Tool Generator** (on Tools page): Generate complete `Tool` class code including parameter definitions, HTTP client integration, async job support, and custom execution logic.

By leveraging Gemini AI, users can describe their desired functionality in plain English and receive production-ready Ruby code that they can download, copy, and integrate into their projects. This accelerates development and serves as a learning tool for the ADK DSL.

## 2. Goals

### 2.1 Business goals

- Lower the barrier to entry for creating ADK agents and tools
- Enable developers to quickly scaffold production-ready code
- Provide a modern, AI-assisted development experience
- Increase adoption of advanced ADK features
- Reduce time spent reading documentation for DSL syntax

### 2.2 User goals

- Quickly scaffold agent and tool definitions without memorizing DSL syntax
- Generate any type of agent configuration from natural language
- Generate custom tools with proper parameter handling and HTTP clients
- Learn ADK patterns through AI-generated examples
- Save time on boilerplate code creation

### 2.3 Non-goals

- Auto-executing generated code (users must run it themselves)
- Replacing the manual agent/tool creation forms
- Generating entire applications or complex multi-file systems
- Real-time code editing/collaboration features
- Directly registering generated code in the running application

## 3. User personas

### 3.1 Key user types

- Ruby developers building AI agent applications
- Developers new to ADK learning the framework
- Backend engineers creating custom tools and integrations

### 3.2 Basic persona details

- **Experienced Ruby Developer**: Wants to quickly scaffold agents/tools without looking up DSL docs
- **ADK Newcomer**: Learning the framework, benefits from seeing properly structured examples
- **Integration Engineer**: Needs to build tools that connect to external APIs

### 3.3 Role-based access

- **All Web UI Users**: Full access to both generator features

## 4. Functional requirements

### Agent Generator (Agents Page)

- **Generate Agent Button** (Priority: High)
  - Add prominent "Generate with AI" button on the Agents list page
  - Opens a modal dialog for input

- **Natural Language Input** (Priority: High)
  - Large text area for describing desired agent
  - Clear placeholder text with examples
  - Support for any agent type description

- **AI Code Generation** (Priority: Critical)
  - Send description to Gemini API with comprehensive prompt
  - Include full ADK AgentDefinition DSL documentation
  - Include list of available tools
  - Return clean, runnable Ruby code

- **Code Preview & Export** (Priority: High)
  - Display generated code with syntax highlighting
  - Copy to clipboard button
  - Download as .rb file button

### Tool Generator (Tools Page)

- **Generate Tool Button** (Priority: High)
  - Add "Generate with AI" button on the Tools list page
  - Opens a modal dialog for input

- **Natural Language Input** (Priority: High)
  - Large text area for describing desired tool
  - Placeholder examples covering various tool types
  - Support for simple, HTTP, and async tool descriptions

- **AI Code Generation** (Priority: Critical)
  - Send description to Gemini API with tool-specific prompt
  - Include ADK Tool DSL documentation
  - Include HttpClient mixin patterns
  - Include BaseAsyncJobTool patterns for async tools
  - Return clean, runnable Ruby code

- **Code Preview & Export** (Priority: High)
  - Display generated code with syntax highlighting
  - Copy to clipboard button
  - Download as .rb file button

### Shared Requirements

- **Error Handling** (Priority: Medium)
  - Clear error messages if API fails
  - Validation of input (non-empty description)
  - Loading state during generation

## 5. User experience

### 5.1 Entry points & first-time user flow

- Agent Generator: "Generate with AI" button on `/agents` page
- Tool Generator: "Generate with AI" button on `/tools` page
- Both buttons positioned prominently near existing create actions
- First-time users see helpful placeholder text explaining the feature

### 5.2 Core experience

- **Step 1**: User clicks "Generate with AI" button (on either page)
  - Modal opens with clean, focused interface
- **Step 2**: User enters natural language description
  - Large text area with relevant placeholder examples
  - For agents: "Create an agent that analyzes customer feedback..."
  - For tools: "Create a tool that fetches weather data from OpenWeather API..."
- **Step 3**: User clicks "Generate" button
  - Loading spinner shows progress
  - Gemini processes request (2-5 seconds typical)
- **Step 4**: Generated code appears in preview
  - Syntax-highlighted Ruby code
  - User can review and understand the structure
- **Step 5**: User exports the code
  - Copy to clipboard or download as file
  - Success feedback (toast notification)

### 5.3 Advanced features & edge cases

- Regenerate with modified description
- Handle very long descriptions gracefully
- Handle API rate limits or errors
- Handle malformed AI output

### 5.4 UI/UX highlights

- Modal design consistent with existing UI patterns
- Syntax highlighting matches CodeMirror theme
- Clear visual separation between input and output sections
- Responsive design for various screen sizes

## 6. Narrative

A developer is building an application that needs to integrate with multiple external APIs. Instead of spending hours reading documentation, they use the AI generators to quickly scaffold their code:

First, they go to the Tools page and click "Generate with AI". They describe: "Create a tool that fetches stock prices from the Alpha Vantage API. It should accept a stock symbol as a required parameter and return the current price, daily high, and daily low." In seconds, they have a complete Tool class with proper HTTP client setup, parameter definitions, and error handling.

Next, they go to the Agents page and describe: "Create a financial advisor agent that can look up stock prices and provide investment recommendations. It should use a friendly, professional tone." The generator produces an agent with the right tools configured, clear instructions, and proper structure.

Within minutes, they have the foundation of their application ready to customize and deploy.

## 7. Success metrics

### 7.1 User-centric metrics

- Time to create first agent/tool (should decrease significantly)
- User satisfaction with generated code quality
- Number of successful code generations per session

### 7.2 Business metrics

- Adoption rate of the generator features
- Increase in custom tools created
- Reduction in documentation support requests

### 7.3 Technical metrics

- API response time for generation
- Error rate from Gemini API
- Code validity rate (generated code is syntactically correct)

## 8. Technical considerations

### 8.1 Integration points

- Gemini AI API (existing pattern in codebase)
- GlobalToolManager (for available tools list in agent generator)
- AVAILABLE_MODELS constant (for model options)
- Existing CodeMirror integration
- Tools page routes for tool generator

### 8.2 Data storage & privacy

- No generated code is stored server-side
- User descriptions are sent to Gemini API (standard AI privacy terms)
- Generated code contains ENV var references for secrets (never hardcoded)

### 8.3 Scalability & performance

- Single API call per generation request
- Client-side caching of last generated result
- No database writes required

### 8.4 Potential challenges

- Prompt engineering for consistent output format
- Handling edge cases in AI output (malformed code)
- Rate limiting from Gemini API
- Teaching AI about all ADK DSL options for both agents and tools
- Keeping prompts updated as ADK evolves

## 9. Milestones & sequencing

### 9.1 Project estimate

- Medium: 2-3 days

### 9.2 Team size & composition

- 1 developer (full-stack Ruby/JavaScript)

### 9.3 Suggested phases

- **Phase 1**: Agent Generator (4-6 hours)
  - Backend route and Gemini integration
  - Agent-specific system prompt
  - Modal UI on Agents page
- **Phase 2**: Tool Generator (4-6 hours)
  - Backend route for tool generation
  - Tool-specific system prompt (simple, HTTP, async patterns)
  - Modal UI on Tools page
- **Phase 3**: Polish & Testing (2-4 hours)
  - Error handling refinements
  - UI polish
  - Testing various generation scenarios

## 10. User stories

### 10.1 Generate Basic LLM Agent

- **ID**: US-001
- **Description**: As a developer, I want to describe a basic agent in natural language so that I can quickly get started with ADK.
- **Acceptance Criteria**:
  - Can enter description like "Create an agent that answers questions about cats"
  - Receive valid Ruby code with AgentDefinition DSL
  - Code includes name, description, instruction, and tools

### 10.2 Generate Workflow Agent

- **ID**: US-002
- **Description**: As a developer, I want to generate sequential/parallel/loop workflow agents so that I can orchestrate multiple agents.
- **Acceptance Criteria**:
  - Can describe workflow requirements
  - Generated code uses correct agent_type (:sequential, :parallel, :loop)
  - Sub-agent references and loop conditions are properly structured

### 10.3 Generate Webhook-Enabled Agent

- **ID**: US-003
- **Description**: As a developer, I want to generate a webhook agent so that I can receive events from external systems.
- **Acceptance Criteria**:
  - Can describe webhook requirements in plain English
  - Generated code includes webhook_enabled, webhook_transformer, webhook_session_extractor
  - Transformer and extractor are proper Ruby Procs
  - Secrets use ENV variable references

### 10.4 Generate Simple Tool

- **ID**: US-004
- **Description**: As a developer, I want to generate a simple tool that performs a calculation or transformation.
- **Acceptance Criteria**:
  - Can describe tool like "Create a tool that converts temperatures between Celsius and Fahrenheit"
  - Generated code includes Tool class with proper DSL
  - Parameters are correctly defined with types and descriptions
  - perform_execution method has working logic

### 10.5 Generate HTTP API Tool

- **ID**: US-005
- **Description**: As a developer, I want to generate a tool that calls an external HTTP API.
- **Acceptance Criteria**:
  - Can describe API integration requirements
  - Generated code includes HttpClient mixin
  - Proper HTTP method calls (GET, POST, etc.)
  - Error handling for HTTP failures
  - API keys use ENV variable references

### 10.6 Generate Async Tool

- **ID**: US-006
- **Description**: As a developer, I want to generate a tool that runs long operations asynchronously via Sidekiq.
- **Acceptance Criteria**:
  - Can describe async requirements like "Create a tool that processes large files in the background"
  - Generated code inherits from BaseAsyncJobTool
  - Includes corresponding Sidekiq worker class
  - Proper job status handling patterns

### 10.7 Copy Generated Code

- **ID**: US-007
- **Description**: As a user, I want to copy generated code to my clipboard so that I can paste it into my project.
- **Acceptance Criteria**:
  - Copy button is visible and accessible
  - Clicking copies full code to clipboard
  - Visual feedback confirms copy success

### 10.8 Download Generated Code

- **ID**: US-008
- **Description**: As a user, I want to download generated code as a .rb file so that I can save it directly to my project.
- **Acceptance Criteria**:
  - Download button triggers file download
  - File is named appropriately (e.g., my_agent.rb or my_tool.rb)
  - File contains complete, runnable Ruby code
