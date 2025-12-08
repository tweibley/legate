---
id: 71
title: 'Tool Generator System Prompt Engineering'
status: pending
priority: critical
feature: AI Code Generator
dependencies:
  - 70
assigned_agent: null
created_at: "2025-12-08T17:48:07Z"
started_at: null
completed_at: null
error_log: null
---

## Description

Design and implement the comprehensive system prompt for the tool generator that teaches Gemini the full ADK Tool DSL and produces high-quality Ruby code for simple tools, HTTP API tools, and async job tools.

## Details

- Create a detailed system prompt that includes:
  
  **ADK Tool Base Class:**
  ```ruby
  class MyTool < ADK::Tool
    tool_description 'What this tool does'
    
    parameter :param_name,
      type: :string,  # :string, :integer, :number, :boolean, :array, :object
      description: 'What this parameter is for',
      required: true  # or false
    
    private
    
    def perform_execution(params, context)
      # params - Hash with symbol keys
      # context - ADK::ToolContext
      
      { status: :success, result: "..." }
      # or { status: :error, error_message: "..." }
    end
  end
  ```
  
  **HTTP Client Tools (for API integrations):**
  ```ruby
  class MyApiTool < ADK::Tool
    include ADK::Tools::Base::HttpClient
    
    def initialize(**options)
      super
      setup_http_client(
        base_url: 'https://api.example.com/',
        headers: { 'Accept' => 'application/json' }
      )
    end
    
    def perform_execution(params, context)
      response = http_get("endpoint", query: { key: params[:key] })
      data = JSON.parse(response.body)
      { status: :success, result: data }
    rescue ADK::ToolHttpError => e
      { status: :error, error_message: "API error: #{e.message}" }
    end
  end
  ```
  
  **Async Job Tools (for long-running operations):**
  ```ruby
  class MyAsyncTool < ADK::Tools::BaseAsyncJobTool
    tool_description 'Starts a background job'
    
    parameter :data, type: :string, required: true
    
    def sidekiq_worker_class
      MyWorker
    end
    
    def prepare_job_arguments(params, context)
      [context.session_id, params[:data]]
    end
  end
  
  class MyWorker
    include Sidekiq::Worker
    
    def perform(session_id, data)
      jid = self.jid
      ADK::Tools::BaseAsyncJobTool.store_job_pending(jid)
      
      # Do work...
      result = process(data)
      
      ADK::Tools::BaseAsyncJobTool.store_job_result(jid, result)
    rescue => e
      ADK::Tools::BaseAsyncJobTool.store_job_error(jid, e.message, e.class.name)
      raise
    end
  end
  ```
  
  **Context Methods Available:**
  - `context.state_get(:key)` - read session state
  - `context.state_set(:key, value)` - write to session state
  - `context.session_id`, `context.user_id`, `context.app_name`
  
  **Output Format Requirements:**
  - Clean Ruby code only, no markdown fences
  - Include necessary requires at top
  - Include clear comments
  - Use ENV variables for API keys/secrets
  - Include `ADK::GlobalToolManager.register_tool(ToolClass)` at end
  
  **AI Should Determine Tool Type Based On:**
  - Mentions "API", "HTTP", "fetch", "external service" → HTTP tool
  - Mentions "background", "async", "long-running", "queue" → Async tool
  - Otherwise → Simple tool

## Test Strategy

- Generate tools for various use cases:
  - Calculator/conversion tool
  - Weather API tool
  - Database lookup tool
  - File processing async tool
- Ensure generated code is syntactically valid
- Verify correct tool type is chosen based on description
- Test that HTTP tools include proper error handling
- Test that async tools include worker class

