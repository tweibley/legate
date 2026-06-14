# Test-only helper: exposes Agent's private transfer_to / execute_step as
# public wrappers so specs can drive delegation directly. Not shipped in the gem.
require 'legate'

module Legate
  # Reopen the Agent class for backward compatibility
  class Agent
    # Delegate to the now-public transfer_to method for backward compatibility
    def public_transfer_to(target_agent_name, task, session_id, session_service)
      transfer_to(target_agent_name, task, session_id, session_service)
    end

    # Override execute_step to be public for testing
    # Also handles special agent_transfer_to_ tools for testing
    def public_execute_step(step, session, session_service)
      # Handle special agent_transfer tool directly
      if step[:tool].to_s.start_with?('agent_transfer_to_')
        target_agent_name = step[:tool].to_s.sub('agent_transfer_to_', '').to_sym
        task = step[:params][:task]

        # Validate task parameter
        unless task
          return {
            status: :error,
            error_class: 'DelegationError',
            error_message: "Missing 'task' parameter for delegation to '#{target_agent_name}'"
          }
        end

        # Call transfer_to with the extracted target and task
        return transfer_to(target_agent_name, task, session.id, session_service)
      end

      # For non-agent-transfer steps, use the standard execute_step
      send(:execute_step, step, session, session_service)
    end
  end
end
