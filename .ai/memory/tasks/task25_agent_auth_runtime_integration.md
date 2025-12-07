---
id: 25
title: 'Agent Authentication Runtime Integration'
status: completed
priority: critical
feature: Authentication System
dependencies: []
assigned_agent: claude
created_at: "2025-12-05T12:00:00Z"
started_at: "2025-12-05T12:00:00Z"
completed_at: "2025-12-05T13:00:00Z"
error_log: null
---

## Description

Complete the missing runtime integration between the Authentication system and Agent/AgentDefinition. Currently, authentication can be configured via the Web UI and stored in RedisStore, but agents do not read or use this configuration at runtime. Tools fall back to global `Auth::Manager` lookups instead of using agent-specific credentials.

## Problem Statement

The authentication integration has a critical gap:

1. **Web UI → RedisStore**: ✅ Works - can assign auth to agents via UI
2. **AgentDefinition DSL → Agent**: ❌ Missing - no programmatic auth configuration
3. **Agent → ToolContext**: ❌ Missing - auth config not propagated to tools
4. **ToolContext → Auth lookup**: ❌ Partial - only uses global Auth::Manager, ignores agent-specific config

## Requirements

### 1. AgentDefinition DSL Enhancement

Add authentication configuration methods to `DefinitionProxy`:

```ruby
agent_def = ADK::AgentDefinition.new.define do |a|
  a.name :my_api_agent
  a.instruction "Call external APIs"
  a.use_tool :http_request
  
  # NEW: Authentication DSL
  a.use_credential :google_maps_api  # Reference a registered credential
  a.auth_mapping 'https://maps.googleapis.com/*', scheme: :api_key, credential: :google_maps_api
  a.auth_mapping /api\.openai\.com/, scheme: :http_bearer, credential: :openai_key
end
```

### 2. AgentDefinition Attributes

Add to `ADK::AgentDefinition`:

- `@auth_credential_names` - Set of credential names this agent can use
- `@auth_url_mappings` - Array of URL pattern → scheme/credential mappings
- `@auth_scheme_assignments` - Hash of service → scheme assignments
- `@auth_credential_assignments` - Hash of service → credential assignments

### 3. DefinitionProxy DSL Methods

```ruby
class DefinitionProxy
  # Associate a credential with this agent
  # @param credential_name [Symbol] Name of a registered credential
  def use_credential(credential_name)
    @definition.instance_variable_get(:@auth_credential_names) << credential_name.to_sym
  end
  
  # Map a URL pattern to authentication
  # @param url_pattern [String, Regexp] URL pattern to match
  # @param scheme [Symbol] Scheme type or name
  # @param credential [Symbol] Credential name
  def auth_mapping(url_pattern, scheme:, credential:)
    @definition.instance_variable_get(:@auth_url_mappings) << {
      pattern: url_pattern,
      scheme_name: scheme.to_sym,
      credential_name: credential.to_sym
    }
  end
  
  # Assign a scheme for a service
  # @param service [Symbol] Service identifier
  # @param scheme [Symbol] Scheme name
  def auth_scheme(service, scheme)
    @definition.instance_variable_get(:@auth_scheme_assignments)[service.to_sym] = scheme.to_sym
  end
  
  # Assign a credential for a service
  # @param service [Symbol] Service identifier  
  # @param credential [Symbol] Credential name
  def auth_credential(service, credential)
    @definition.instance_variable_get(:@auth_credential_assignments)[service.to_sym] = credential.to_sym
  end
end
```

### 4. Agent Runtime Integration

Modify `ADK::Agent`:

- In `#initialize`: Read auth config from definition
- Store auth config in instance variables
- In `#run_task` or `#execute_step`: Pass auth config to ToolContext

```ruby
class Agent
  attr_reader :auth_credential_names, :auth_url_mappings, 
              :auth_scheme_assignments, :auth_credential_assignments
  
  def initialize(definition:, **options)
    # ... existing code ...
    
    # Load auth config from definition
    @auth_credential_names = definition.auth_credential_names || Set.new
    @auth_url_mappings = definition.auth_url_mappings || []
    @auth_scheme_assignments = definition.auth_scheme_assignments || {}
    @auth_credential_assignments = definition.auth_credential_assignments || {}
  end
end
```

### 5. ToolContext Enhancement

Add agent-aware authentication to `ADK::ToolContext`:

```ruby
class ToolContext
  attr_reader :agent_auth_config
  
  def initialize(..., agent_auth_config: nil)
    # ... existing code ...
    @agent_auth_config = agent_auth_config
  end
  
  def handle_request_auth(request, options = {})
    return request unless requires_authentication?(request)
    
    # First, check agent-specific mappings
    if @agent_auth_config
      scheme, credential = find_agent_auth_for_url(request[:url])
      if scheme && credential
        return authenticate_request(request, scheme, credential)
      end
    end
    
    # Fall back to global Auth::Manager
    # ... existing code ...
  end
  
  private
  
  def find_agent_auth_for_url(url)
    return nil unless @agent_auth_config && @agent_auth_config[:url_mappings]
    
    @agent_auth_config[:url_mappings].each do |mapping|
      if url_matches?(url, mapping[:pattern])
        scheme = ADK::Auth::Manager.instance.get_scheme(mapping[:scheme_name])
        credential = ADK::Auth::Manager.instance.get_credential(mapping[:credential_name])
        return [scheme, credential] if scheme && credential
      end
    end
    
    nil
  end
end
```

### 6. RedisStore Synchronization

Ensure `AgentDefinition#to_h` and `AgentDefinition.from_hash` properly serialize/deserialize auth attributes for persistence:

```ruby
def to_h
  {
    # ... existing fields ...
    auth_credential_names: @auth_credential_names.to_a.map(&:to_s),
    auth_url_mappings: @auth_url_mappings.map { |m| m.transform_keys(&:to_s) },
    auth_scheme_assignments: @auth_scheme_assignments.transform_keys(&:to_s).transform_values(&:to_s),
    auth_credential_assignments: @auth_credential_assignments.transform_keys(&:to_s).transform_values(&:to_s)
  }
end
```

### 7. Web UI Compatibility

Ensure changes are backward compatible with existing Web UI auth assignment routes. The Web UI already stores `auth_scheme_assignments`, `auth_credential_assignments`, and `auth_url_mappings` - these should now be read at runtime.

## Files to Modify

1. `lib/adk/agent.rb`
   - Add auth attributes to `AgentDefinition`
   - Add DSL methods to `DefinitionProxy`
   - Update `AgentDefinition#initialize`, `#to_h`, `.from_hash`
   - Update `Agent#initialize` to load auth config
   - Update `Agent#run_task` / `#execute_step` to pass auth to ToolContext

2. `lib/adk/tool_context.rb`
   - Add `agent_auth_config` parameter
   - Update `handle_request_auth` to check agent-specific config first

3. `lib/adk/definition_store/redis_store.rb`
   - Verify auth fields are already handled (they are)

4. `spec/adk/agent_spec.rb`
   - Add tests for auth DSL
   - Add tests for auth config loading

5. `spec/adk/tool_context_spec.rb` or new `spec/adk/tool_context_auth_spec.rb`
   - Add tests for agent-aware auth lookup

## Test Strategy

1. **Unit Tests**
   - Test auth DSL methods in AgentDefinition
   - Test auth attribute serialization/deserialization
   - Test ToolContext agent-auth lookup priority

2. **Integration Tests**
   - Test end-to-end: Define agent with auth → Run task → Tool uses agent's credentials
   - Test fallback to global Auth::Manager when agent has no specific mapping
   - Test Web UI assigned auth is used at runtime

3. **Backward Compatibility Tests**
   - Agents without auth config still work
   - Existing global Auth::Manager registrations still work

## Acceptance Criteria

- [x] `AgentDefinition` has DSL methods: `use_credential`, `auth_mapping`, `auth_scheme`, `auth_credential`
- [x] `AgentDefinition` stores auth attributes and serializes them correctly
- [x] `Agent` reads auth config from definition at initialization
- [x] `Agent` passes auth config to `ToolContext` when executing tools
- [x] `ToolContext#handle_request_auth` checks agent-specific config before global
- [x] Web UI-assigned auth configurations are used at runtime (via from_hash loading)
- [x] Backward compatible with agents that have no auth config
- [x] All new functionality has comprehensive tests (16 tests passing)
- [ ] Examples updated to demonstrate programmatic auth configuration (future enhancement)

## Definition of Done

- Code implemented and tested
- All tests passing
- Documentation updated with auth DSL examples
- Existing auth examples still work
- Web UI auth assignment works end-to-end

