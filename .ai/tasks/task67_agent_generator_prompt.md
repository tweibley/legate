---
id: 67
title: 'Agent Generator System Prompt Engineering'
status: pending
priority: critical
feature: AI Code Generator
dependencies:
  - 66
assigned_agent: null
created_at: "2025-12-08T17:37:28Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Design and implement the comprehensive system prompt for the agent generator that teaches Gemini the full ADK AgentDefinition DSL and produces high-quality, consistent Ruby code output for any type of agent.

## Details

- Create a detailed system prompt that includes:
  
  **ADK AgentDefinition DSL Reference:**
  - `AgentDefinition.new.define do |a| ... end` structure
  - All builder methods:
    - `a.name(:symbol)` - required, unique identifier
    - `a.description('string')` - required, what the agent does
    - `a.instruction('system prompt')` - required, guides agent behavior
    - `a.use_tool :tool_name` - for each tool
    - `a.model_name 'gemini-2.0-flash'` - optional, LLM model
    - `a.temperature 0.7` - optional, creativity setting
    - `a.fallback_mode :error/:echo` - optional
    - `a.output_key :result` - optional, state storage key
  
  **Agent Types:**
  - `a.agent_type :llm` - default, uses LLM for planning
  - `a.agent_type :sequential` with `a.sequential_sub_agent_names [:a1, :a2]`
  - `a.agent_type :parallel` with `a.parallel_sub_agent_names [:a1, :a2]`
  - `a.agent_type :loop` with loop configuration options
  - `a.delegation_targets [:other_agent]` - for LLM agents delegating
  
  **Loop Agent Configuration:**
  - `a.loop_max_iterations 10`
  - `a.loop_condition_state_key :key_name`
  - `a.loop_condition_expected_value 'value'`
  
  **Webhook Configuration:**
  - `a.webhook_enabled true`
  - `a.webhook_validator :hmac_sha256` or custom Proc
  - `a.webhook_secret ENV['SECRET_NAME']`
  - `a.webhook_transformer ->(payload) { ... }` with examples
  - `a.webhook_session_extractor ->(payload) { ... }` with examples
  
  **Callbacks:**
  - `a.before_agent_callback { |ctx| ... }`
  - `a.after_agent_callback { |ctx, response| ... }`
  - `a.before_tool_callback { |tool, args, ctx| ... }`
  - `a.after_tool_callback { |tool, args, ctx, result| ... }`
  
  **Output Format Requirements:**
  - Clean Ruby code only, no markdown fences in output
  - Include `require 'adk'` at top
  - Include clear comments explaining each section
  - Use ENV variables for any secrets
  - Register with `ADK::GlobalDefinitionRegistry.register(definition)` at end
  
  **Examples in Prompt:**
  - Basic LLM agent with tools
  - Sequential workflow agent
  - Loop agent with exit condition
  - Webhook-enabled agent

- Dynamically inject available tools list into prompt
- Handle prompt length constraints (truncate tool list if too long)

## Test Strategy

- Generate agents for various use cases:
  - Simple Q&A agent
  - Multi-tool agent
  - Sequential workflow
  - Parallel workflow
  - Loop with condition
  - Webhook receiver
- Ensure generated code is syntactically valid
- Verify consistent output format across multiple generations
