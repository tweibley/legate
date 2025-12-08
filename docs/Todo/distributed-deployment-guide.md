# Distributed Deployment Guide for ADK-Ruby

> **Status:** Analysis & Recommendations  
> **Last Updated:** December 2024  
> **Scenario:** Running ADK-Ruby agents across multiple VMs behind a load balancer

## Overview

This document analyzes the requirements and challenges for deploying ADK-Ruby in a distributed environment where multiple application instances (VMs) receive requests via a load balancer. It identifies which components are already distributed-ready, which require changes, and provides recommendations for production deployment.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current Architecture](#current-architecture)
3. [Distributed-Ready Components](#distributed-ready-components)
4. [Problematic Components](#problematic-components)
5. [Required Changes](#required-changes)
6. [Configuration Assumptions](#configuration-assumptions)
7. [Recommended Architecture](#recommended-architecture)
8. [Quick Wins](#quick-wins)
9. [Implementation Roadmap](#implementation-roadmap)

---

## Executive Summary

The ADK-Ruby framework has **partial support** for distributed deployment:

| Aspect | Status | Notes |
|--------|--------|-------|
| Session Storage | ⚠️ Configurable | Default is in-memory; Redis option exists |
| Agent Definitions | ✅ Ready | Stored in Redis |
| Running Agent Instances | ❌ Not Ready | In-memory `@agents` hash per process |
| MCP Connections | ❌ Not Ready | Per-process, stateful connections |
| Tool Registry | ⚠️ Partial | Requires consistent deployment |
| Webhook Processing | ✅ Ready | Uses Sidekiq/Redis |
| Background Jobs | ✅ Ready | Uses Sidekiq/Redis |

**Bottom Line:** Webhooks work well in distributed mode (via Sidekiq). Interactive agent usage requires additional work or architectural decisions (sticky sessions, dedicated workers, etc.).

---

## Current Architecture

```
Single Process Model (Current Default)
┌─────────────────────────────────────────────────────────────────┐
│                        Web Process (Sinatra)                     │
├─────────────────────────────────────────────────────────────────┤
│  @agents = {}           # In-memory agent instances              │
│  @session_service       # Default: InMemory                      │
│  @definition_store      # Redis-backed                           │
│  GlobalToolManager      # Process-scoped class variable          │
│  GlobalDefinitionRegistry # Process-scoped (holds Procs)         │
├─────────────────────────────────────────────────────────────────┤
│  Agent Instance                                                  │
│    └── MCP Client Connections (stateful, per-agent)             │
│    └── Tool Registry (tools loaded for this agent)              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                           Redis                                  │
│  - Agent definitions (adk:agent:*)                              │
│  - Sessions (if using Redis session service)                    │
│  - Sidekiq queues                                               │
│  - Job results                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Distributed-Ready Components

### 1. Session Storage (Redis Option)

**Location:** `lib/adk/session_service/redis.rb`

The Redis session service is well-designed for distributed use:

- Uses **WATCH/MULTI/EXEC** pattern for optimistic locking
- Properly handles concurrent state modifications
- Supports encrypted credential storage
- Has retry logic for lock conflicts

```ruby
# Example: Enable Redis sessions
ADK.configure do |config|
  config.session_service = ADK::SessionService::Redis.new(
    redis_client: Redis.new(url: ENV['REDIS_URL']),
    session_ttl: 604_800  # 7 days
  )
end
```

### 2. Agent Definition Storage (Redis)

**Location:** `lib/adk/definition_store/redis_store.rb`

Agent definitions are already stored in Redis:

- Definitions stored as Redis Hashes (`adk:agent:{name}`)
- Agent names tracked in a Set (`adk:agents:all_names`)
- Includes `persistent_status` field for tracking intended state
- Uses atomic transactions for saves/updates

### 3. Webhook Processing via Sidekiq

**Location:** `lib/adk/web/webhook_listener.rb`, `lib/adk/webhook_job_worker.rb`

Webhook processing correctly uses distributed job processing:

1. Webhook received → validates request
2. Transforms payload using agent's transformer Proc
3. Extracts session ID
4. Enqueues job to Sidekiq (`adk_webhooks` queue)
5. Any Sidekiq worker can process the job

```ruby
# Jobs are enqueued with all necessary context
job_payload = {
  'agent_definition_name' => agent_name_sym.to_s,
  'session_id' => session_id,
  'transformed_user_input' => transformed_user_input,
  'session_service_config' => string_key_config
}
Sidekiq::Client.push(
  'queue' => 'adk_webhooks',
  'class' => 'ADK::WebhookJobWorker',
  'args' => [job_payload]
)
```

### 4. Async Tool Job Results

**Location:** `lib/adk/tools/base_async_job_tool.rb`

Background job results are stored in Redis for cross-process retrieval:

- Job status tracked in Redis
- Results accessible via `check_job_status` tool
- Any process can query job status

---

## Problematic Components

### 1. In-Memory Agent Instances (`@agents` hash)

**Location:** `lib/adk/web/app.rb:142`

**The Problem:**

```ruby
def initialize
  super
  @agents = {}  # Each VM has its own hash!
  @session_service = ADK::SessionService::InMemory.new  # Also per-VM
  # ...
end
```

Each VM maintains its own `@agents` hash:
- VM1 starts agent "sales_bot" → exists in VM1's memory
- VM2 receives request for "sales_bot" → agent doesn't exist in VM2's memory
- Request fails or requires re-instantiation

**Current Mitigation (Incomplete):**

The `synchronize_persistent_agents` method runs at startup:

```ruby
def synchronize_persistent_agents
  definitions.each do |definition|
    if definition[:persistent_status] == 'running'
      started_agent = _start_agent(agent_name)  # Start locally
    end
  end
end
```

**Limitation:** This only runs at process startup, not when requests arrive.

### 2. MCP Client Connections

**Location:** `lib/adk/mcp/client.rb`

**The Problem:**

MCP connections are stateful, long-lived connections to external tool servers:

```ruby
def initialize(connection_params)
  @connection = nil
  @server_capabilities = nil
  @connected = false
  @pending_requests = {}
  @lock = Mutex.new
end
```

- Connections are established when `agent.start` is called
- Each agent instance maintains its own connections
- Connections cannot be shared across processes/VMs
- Re-establishing connections per-request would be slow

### 3. GlobalToolManager (Process-Scoped)

**Location:** `lib/adk/global_tool_manager.rb`

**The Problem:**

```ruby
module GlobalToolManager
  @@defined_tools = {}  # Class variable = per-process
  
  def self.register_tool(tool_class)
    @@defined_tools[tool_name] = tool_class
  end
end
```

- Tool classes are registered when files are loaded
- Built-in tools load consistently (via `lib/adk.rb`)
- Custom tools must be deployed and loaded identically on all VMs

### 4. GlobalDefinitionRegistry (In-Memory Procs)

**Location:** `lib/adk/global_definition_registry.rb`

**The Problem:**

```ruby
module GlobalDefinitionRegistry
  @registry = {}  # Stores AgentDefinition objects with Procs
  
  def self.register(definition)
    @registry[definition.name] = definition
  end
end
```

This registry stores `AgentDefinition` objects that contain:
- `webhook_transformer` (Proc)
- `webhook_session_extractor` (Proc)
- `webhook_validator` (Proc or Symbol)
- `before_agent_callback` (Proc)
- `after_agent_callback` (Proc)
- Other callback Procs

**Procs cannot be serialized to Redis.** Each VM must load the same definition files.

The webhook listener explicitly requires in-memory definitions:

```ruby
in_memory_definition = ADK::GlobalDefinitionRegistry.find(agent_name_sym)
unless in_memory_definition
  halt 500, json({ status: :error, 
    error_message: 'Agent definition not loaded.' })
end
```

### 5. Default Session Service is In-Memory

**Location:** `lib/adk/configuration.rb:31`

```ruby
def initialize
  @session_service = ADK::SessionService::InMemory.new  # Not distributed!
end
```

---

## Required Changes

### 1. Centralized Agent Runtime Management

**Option A: Lazy Agent Instantiation Per-Request**

```ruby
# Modified approach for stateless web servers
def get_or_create_agent_for_request(name)
  definition = @definition_store.get_definition(name)
  return nil unless definition && definition[:persistent_status] == 'running'
  
  # Create fresh agent instance
  definition_obj = ADK::AgentDefinition.from_hash(definition)
  agent = ADK::Agent.new(definition: definition_obj)
  
  # Start (establishes MCP connections)
  agent.start
  
  # Return for single use (don't cache)
  agent
ensure
  # Could pool or cache with TTL
end
```

**Trade-offs:**
- ✅ No state synchronization needed
- ❌ MCP connection overhead per request
- ❌ Slower response times

**Option B: Dedicated Agent Worker Pool**

```ruby
# Web servers only enqueue, workers run agents
class AgentTaskWorker
  include Sidekiq::Worker
  
  # Each worker maintains running agents
  @@local_agents = {}
  
  def perform(agent_name, session_id, user_input)
    agent = get_or_start_agent(agent_name)
    result = agent.run_task(
      session_id: session_id,
      user_input: user_input,
      session_service: redis_session_service
    )
    store_result_for_polling(session_id, result)
  end
end
```

**Trade-offs:**
- ✅ Agents stay running in worker processes
- ✅ MCP connections persist
- ❌ Need result polling or push mechanism
- ❌ More complex architecture

**Option C: Sticky Sessions (Load Balancer)**

Configure load balancer for session affinity based on agent name or session ID:

```nginx
# Nginx example
upstream adk_backend {
  hash $arg_agent consistent;
  server vm1:4567;
  server vm2:4567;
  server vm3:4567;
  server vm4:4567;
  server vm5:4567;
}
```

**Trade-offs:**
- ✅ Simple to implement
- ❌ Uneven load distribution
- ❌ Single point of failure per agent
- ❌ Session moves if VM restarts

### 2. Ensure Consistent Proc Loading

All VMs must load the same agent definition files:

```ruby
# In config.ru or initializer
# Load all agent definitions with their Procs
Dir[File.join(__dir__, 'agents/**/*.rb')].sort.each do |file|
  require file
end
```

Deployment checklist:
- [ ] Same codebase deployed to all VMs
- [ ] Agent definition files in version control
- [ ] Same Ruby version and gems
- [ ] Same environment variables

### 3. Configure Redis Session Service

```ruby
# config/initializers/adk.rb
ADK.configure do |config|
  config.session_service = ADK::SessionService::Redis.new(
    redis_client: Redis.new(
      url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
      ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }  # For Redis TLS
    ),
    session_ttl: 7 * 24 * 60 * 60,  # 7 days
    enable_encryption: true
  )
end
```

### 4. MCP Connection Strategy

For agents with MCP servers, implement reconnection logic:

```ruby
class Agent
  def ensure_mcp_connected
    @mcp_clients.each do |name, client|
      unless client&.connected?
        ADK.logger.info("Reconnecting MCP client: #{name}")
        client.connect
      end
    end
  end
  
  def run_task(...)
    ensure_mcp_connected
    # ... existing logic
  end
end
```

### 5. Distributed Locking for Agent Start/Stop

Prevent race conditions when multiple VMs try to start/stop agents:

```ruby
require 'redlock'

class DistributedAgentManager
  def initialize(redis_url)
    @lock_manager = Redlock::Client.new([redis_url])
  end
  
  def start_agent(name, &block)
    lock_key = "adk:agent:lock:#{name}"
    
    @lock_manager.lock(lock_key, 10_000) do |locked|
      if locked
        # Check current state first
        current = definition_store.get_definition(name)
        if current[:persistent_status] == 'running'
          ADK.logger.info("Agent #{name} already marked as running")
          return
        end
        
        yield  # Execute the actual start
      else
        ADK.logger.warn("Could not acquire lock for agent #{name}")
      end
    end
  end
end
```

---

## Configuration Assumptions

| Component | Current Default | Distributed Requirement | Action |
|-----------|-----------------|------------------------|--------|
| `session_service` | `InMemory` | `Redis` | Configure explicitly |
| `definition_store` | `RedisStore` | `RedisStore` | ✅ Already correct |
| Agent instances | `@agents` hash | Shared orchestration | Architectural change |
| MCP connections | Per-process | Per-process (accept latency) | Reconnection logic |
| Tool classes | Process-loaded | Consistent deployment | DevOps process |
| Agent Procs | Process-loaded | Consistent deployment | DevOps process |
| Sidekiq | Redis-backed | Redis-backed | ✅ Already correct |
| Encryption key | `ADK_ENCRYPTION_KEY` env | Same on all VMs | Environment config |

---

## Recommended Architecture

```
                    ┌─────────────────────────────────────────────────┐
                    │              Load Balancer                       │
                    │  (Consider sticky sessions by agent_name)        │
                    └─────────────────┬───────────────────────────────┘
                                      │
        ┌──────────────┬──────────────┼──────────────┬──────────────┐
        │              │              │              │              │
   ┌────▼────┐   ┌────▼────┐   ┌────▼────┐   ┌────▼────┐   ┌────▼────┐
   │  VM 1   │   │  VM 2   │   │  VM 3   │   │  VM 4   │   │  VM 5   │
   │ Web App │   │ Web App │   │ Web App │   │ Web App │   │ Web App │
   │ Sinatra │   │ Sinatra │   │ Sinatra │   │ Sinatra │   │ Sinatra │
   └────┬────┘   └────┬────┘   └────┬────┘   └────┬────┘   └────┬────┘
        │              │              │              │              │
        └──────────────┴──────────────┼──────────────┴──────────────┘
                                      │
                    ┌─────────────────▼───────────────────────────────┐
                    │                    Redis                         │
                    │  ┌─────────────────────────────────────────┐    │
                    │  │ Sessions      (adk:session:*)           │    │
                    │  │ Definitions   (adk:agent:*)             │    │
                    │  │ Sidekiq       (queue:adk_webhooks)      │    │
                    │  │ Job Results   (adk:job_result:*)        │    │
                    │  │ Locks         (adk:agent:lock:*)        │    │
                    │  └─────────────────────────────────────────┘    │
                    └─────────────────────────────────────────────────┘
                                      │
        ┌─────────────────────────────┴─────────────────────────────┐
        │                                                           │
   ┌────▼────────────────┐                         ┌────▼────────────────┐
   │  Sidekiq Worker 1   │                         │  Sidekiq Worker 2   │
   │  - adk_webhooks     │                         │  - adk_webhooks     │
   │  - Maintains agents │                         │  - Maintains agents │
   └─────────────────────┘                         └─────────────────────┘
```

### Component Responsibilities

| Component | Responsibilities |
|-----------|------------------|
| **Load Balancer** | Route requests; optionally sticky sessions |
| **Web Apps** | Serve UI, receive webhooks, enqueue jobs |
| **Redis** | Shared state, queues, locks, sessions |
| **Sidekiq Workers** | Process agent tasks, maintain MCP connections |

---

## Quick Wins

For minimal effort distributed support:

### 1. Switch to Redis Sessions (Required)

```ruby
# In your initialization code
ADK.configure do |config|
  config.session_service = ADK::SessionService::Redis.new(
    redis_client: Redis.new(url: ENV['REDIS_URL'])
  )
end
```

### 2. Deploy Identical Code to All VMs

Ensure all agent definition files (with Procs) are:
- In version control
- Deployed via CI/CD to all VMs
- Loaded at application startup

### 3. Run Sidekiq Workers Separately

```bash
# On dedicated worker machines or containers
bundle exec sidekiq -q adk_webhooks -c 5
```

### 4. For Webhooks: Already Works!

The current webhook → Sidekiq → worker flow is distributed-ready.

### 5. For Interactive Chat: Use Sticky Sessions

Configure your load balancer:
- HAProxy: `balance source` or `stick-table`
- Nginx: `ip_hash` or `hash $cookie_session_id`
- AWS ALB: Enable sticky sessions

---

## Implementation Roadmap

### Phase 1: Essential (Week 1)
- [ ] Configure Redis session service
- [ ] Verify agent definition files deployed to all VMs
- [ ] Set up Sidekiq workers for webhook processing
- [ ] Configure load balancer with sticky sessions

### Phase 2: Improvements (Week 2-3)
- [ ] Add MCP reconnection logic
- [ ] Implement distributed locking for agent start/stop
- [ ] Add health check endpoints
- [ ] Set up monitoring for agent status across VMs

### Phase 3: Advanced (Month 2+)
- [ ] Consider dedicated agent worker architecture
- [ ] Implement agent instance pooling
- [ ] Add request tracing across VMs
- [ ] Performance testing under load

---

## Testing Distributed Setup

### Checklist

```bash
# 1. Verify Redis connectivity from all VMs
redis-cli -h your-redis-host ping

# 2. Verify Sidekiq workers are processing
bundle exec sidekiq -q adk_webhooks &
# Send test webhook, verify processing

# 3. Test session persistence across VMs
# Create session on VM1, verify accessible from VM2

# 4. Test agent definition consistency
# Start agent on VM1, verify definition loaded on VM2

# 5. Load test with distributed traffic
# Use tool like wrk or locust to generate load
```

### Common Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| Session not found | "Session not found" errors | Switch to Redis sessions |
| Agent not running | "Agent not started" on some VMs | Use sticky sessions or sync at startup |
| Missing Procs | "Transformer not found" errors | Ensure code deployed to all VMs |
| MCP timeout | Slow tool responses | Implement connection pooling |

---

## References

- `lib/adk/session_service/redis.rb` - Redis session implementation
- `lib/adk/definition_store/redis_store.rb` - Agent definition storage
- `lib/adk/web/webhook_listener.rb` - Webhook processing
- `lib/adk/webhook_job_worker.rb` - Sidekiq worker for webhooks
- `lib/adk/web/app.rb` - Main web application
- `lib/adk/global_definition_registry.rb` - In-memory Proc storage
- `lib/adk/mcp/client.rb` - MCP connection handling

