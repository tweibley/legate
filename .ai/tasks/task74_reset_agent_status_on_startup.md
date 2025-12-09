---
id: 74
title: 'Reset Agent Persistent Status on Server Startup'
status: completed
priority: high
feature: Agent Status Persistence Fix
dependencies:
  - 73
assigned_agent: null
created_at: "2025-12-09T02:54:59Z"
started_at: "2025-12-09T02:57:14Z"
completed_at: "2025-12-09T02:57:46Z"
error_log: null
---

## Description

Modify `synchronize_persistent_agents` to reset all stale `persistent_status` values to 'stopped' on startup, ensuring the UI accurately reflects that no agents are running immediately after server start.

## Details

- Locate the `synchronize_persistent_agents` method in `lib/adk/web/app.rb`
- Modify the method to reset statuses instead of trying to restart agents:
  ```ruby
  def synchronize_persistent_agents
    return unless @definition_store&.check_connection

    @logger.info('Synchronizing persistent agent statuses on startup...')
    begin
      definitions = @definition_store.list_definitions
      
      # Reset all 'running' statuses to 'stopped' since we just started
      # (nothing is actually running in memory yet)
      definitions.each do |definition|
        if definition[:persistent_status] == 'running'
          agent_name = definition[:name]
          @logger.info("Resetting stale 'running' status for agent '#{agent_name}' to 'stopped'")
          @definition_store.update_definition(agent_name, { persistent_status: 'stopped' })
        end
      end
      
      @logger.info('Finished synchronizing persistent agent statuses.')
    rescue ADK::DefinitionStore::StoreError => e
      @logger.error("Store error during persistent agent synchronization: #{e.message}")
    rescue => e
      @logger.error("Unexpected error during persistent agent synchronization: #{e.class} - #{e.message}")
      @logger.error(e.backtrace.first(5).join("\n"))
    end
  end
  ```

- Key changes:
  - Remove the logic that tries to restart agents based on `persistent_status == 'running'`
  - Instead, reset any stale 'running' status to 'stopped'
  - This is the correct approach because at server startup, nothing is actually running
  - Users can manually start agents they need after the server is running

- Rationale:
  - The previous approach tried to auto-restart agents, but this was problematic:
    - It could fail silently due to the `halt` issue
    - It added complexity and potential startup delays
    - Auto-restart behavior might not be desired in all scenarios
  - The new approach simply ensures the UI is accurate
  - Users have full control over which agents to start

## Test Strategy

1. Manual testing scenario:
   - Start the web server
   - Create an agent via the UI
   - Start the agent - verify "Running" status
   - Stop the web server (Ctrl+C)
   - Restart the web server
   - Verify the agent shows "Stopped" status (not "Running")
   - Verify logs show the status reset message
   - Start the agent again - verify it works correctly

2. Multiple agents scenario:
   - Start 3 agents
   - Stop server, restart server
   - All 3 should show "Stopped"

3. Verify Redis state:
   - After restart, check Redis directly to confirm `persistent_status` is 'stopped'
   - Command: `redis-cli hget adk:agent:<agent_name> persistent_status`

