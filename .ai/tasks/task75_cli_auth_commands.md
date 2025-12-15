# Task 75: CLI Authentication Commands

Add authentication management commands to the CLI, mirroring web UI capabilities.

## Priority: High

## Dependencies: None (auth system already complete)

## Subtasks

### Phase 1: Core Infrastructure
- [ ] Create `lib/adk/cli/auth_commands.rb` with Thor subcommand structure
- [ ] Register `auth` subcommand in `lib/adk/cli.rb`
- [ ] Add helper methods for credential masking and table formatting

### Phase 2: Scheme Commands
- [ ] Implement `adk auth schemes list`
- [ ] Implement `adk auth schemes show <name>`
- [ ] Implement `adk auth schemes create <name> --type=<type>` with type-specific options
- [ ] Implement `adk auth schemes delete <name>` with dependency check

### Phase 3: Credential Commands
- [ ] Implement `adk auth credentials list` with masked output
- [ ] Implement `adk auth credentials show <name>`
- [ ] Implement `adk auth credentials create <name> --type=<type>`
- [ ] Implement `adk auth credentials update <name>`
- [ ] Implement `adk auth credentials delete <name>` with dependency check
- [ ] Implement `adk auth credentials test <name>` with optional `--url` flag

### Phase 4: URL Mapping Commands
- [ ] Implement `adk auth mappings list`
- [ ] Implement `adk auth mappings create --pattern=<pattern> --scheme=<name> --credential=<name>`
- [ ] Implement `adk auth mappings delete <index>`

### Phase 5: Testing & Documentation
- [ ] Write unit tests in `spec/adk/cli/auth_commands_spec.rb`
- [ ] Ensure 100% line coverage is maintained
- [ ] Update CLI help text with examples
- [ ] Update AGENTS.md if needed

## Acceptance Criteria

1. All commands execute successfully and produce formatted output
2. Credentials are properly masked in list/show output
3. Dependency checks prevent deleting schemes/credentials in use
4. Tests pass with 100% line coverage
5. Commands work with both in-memory and Redis persistence

## Files to Create/Modify

| Action | File |
|--------|------|
| NEW | `lib/adk/cli/auth_commands.rb` |
| NEW | `lib/adk/cli/auth_scheme_commands.rb` |
| NEW | `lib/adk/cli/auth_credential_commands.rb` |
| NEW | `lib/adk/cli/auth_mapping_commands.rb` |
| MODIFY | `lib/adk/cli.rb` |
| NEW | `spec/adk/cli/auth_commands_spec.rb` |

## Reference

- Web UI implementation: `lib/adk/web/routes/authentication_routes.rb`
- Auth Manager API: `lib/adk/auth/manager.rb`
- Existing CLI patterns: `lib/adk/cli/agent_commands.rb`
