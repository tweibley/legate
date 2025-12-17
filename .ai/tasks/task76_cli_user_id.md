# Task 76: CLI User ID Option

Add `--user-id` option to CLI commands that create/use sessions, enabling consistent user identity across CLI and web.

## Priority: High

## Dependencies: None (session system already complete)

## Problem Statement

Currently the CLI hardcodes user IDs:
- `session execute`: `user_id: 'cli_user'`
- `agent execute`: `user_id: 'cli_user'`
- `agent chat`: `user_id: random each time!

This prevents users from:
- Resuming previous chat sessions  
- Sharing sessions between CLI and web
- Filtering sessions by their identity

## Subtasks

### Phase 1: Session Commands
- [x] Add `--user-id` option to `adk session execute`
- [x] Update session creation to use `options[:user_id]`
- [ ] Add tests for default and custom user_id

### Phase 2: Agent Commands
- [x] Add `--user-id` option to `adk agent execute`
- [x] Add `--user-id` option to `adk agent chat`
- [x] Update session creation in both commands
- [ ] Add tests for user_id handling

### Phase 3: Tool Commands
- [x] Add `--user-id` option to `adk tool execute`
- [x] Update ToolContext creation
- [ ] Add tests

### Phase 4: Documentation
- [ ] Update CLI help text
- [ ] Update `public/docs/cli/adk_cli_usage.md`
- [ ] Ensure tests pass with 100% coverage

## Acceptance Criteria

1. All affected commands accept `--user-id` option
2. Default is `cli_user` for backward compatibility
3. Sessions created with custom user_id can be resumed
4. `adk session list --user-id=X` shows matching sessions
5. Tests pass with 100% line coverage

## Files to Modify

| Action | File |
|--------|------|
| MODIFY | `lib/adk/cli/session_commands.rb` |
| MODIFY | `lib/adk/cli/agent_commands.rb` |
| MODIFY | `lib/adk/cli/tool_commands.rb` |
| MODIFY | `spec/adk/cli/session_commands_spec.rb` |
| MODIFY | `spec/adk/cli/agent_commands_spec.rb` |
| MODIFY | `spec/adk/cli/tool_commands_spec.rb` |
| MODIFY | `public/docs/cli/adk_cli_usage.md` |

## Reference

- Plan: [cli_user_id.md](file:///Users/tweibley/adk-ruby/.ai/plans/features/cli_user_id.md)
- Session service: `lib/adk/session_service/redis.rb`
- Existing CLI patterns: `lib/adk/cli/session_commands.rb`
