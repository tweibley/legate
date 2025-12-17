# CLI User ID Feature

Add `--user-id` option to CLI commands that create or use sessions, enabling consistent user identity across CLI and web.

## User Review Required

> [!IMPORTANT]
> This changes how CLI sessions are created. Previously, sessions had hardcoded user IDs (`cli_user` or random UUIDs). After this change, users can specify their own `--user-id` to resume sessions or share identity with web sessions.

## Background

Currently the CLI hardcodes user IDs in several places:
- `session execute`: `user_id: 'cli_user'`
- `agent execute`: `user_id: 'cli_user'`
- `agent chat`: `user_id: "cli_chat_user_#{SecureRandom.hex(3)}"` (random each time!)

This means:
1. CLI users can't resume previous chat sessions
2. Sessions created in web (with `web_user_id`) are separate from CLI sessions
3. Each `adk agent chat` starts fresh with no history

---

## Proposed Changes

### CLI Commands Module

#### [MODIFY] [session_commands.rb](file:///Users/tweibley/adk-ruby/lib/adk/cli/session_commands.rb)

Add `--user-id` option to `execute` command:

```diff
 desc 'execute AGENT_NAME TASK --session-id=SESSION_ID',
      'Execute a task using an agent with a specific Redis session'
 method_option :session_id, type: :string, desc: 'ID of an existing Redis session to use'
+method_option :user_id, type: :string, default: 'cli_user', desc: 'User ID for the session'
 def execute(agent_name, task)
   # ...
-  adk_session = session_service.create_session(app_name: agent_name, user_id: 'cli_user')
+  adk_session = session_service.create_session(app_name: agent_name, user_id: options[:user_id])
```

---

#### [MODIFY] [agent_commands.rb](file:///Users/tweibley/adk-ruby/lib/adk/cli/agent_commands.rb)

Add `--user-id` option to `execute` and `chat` commands:

**For `execute` command (~line 838):**
```diff
 method_option :session_id, type: :string, desc: 'Optional session ID'
+method_option :user_id, type: :string, default: 'cli_user', desc: 'User ID for the session'
 def execute(name, task)
   # ...
-  adk_session = session_service_instance.create_session(app_name: name, user_id: 'cli_user')
+  adk_session = session_service_instance.create_session(app_name: name, user_id: options[:user_id])
```

**For `chat` command (~line 973):**
```diff
 method_option :model, type: :string, desc: 'Override model'
+method_option :user_id, type: :string, default: 'cli_user', desc: 'User ID for the session'
 def chat(agent_name)
   # ...
-  adk_session = session_service_instance.create_session(app_name: agent_name_str, user_id: "cli_chat_user_#{SecureRandom.hex(3)}")
+  adk_session = session_service_instance.create_session(app_name: agent_name_str, user_id: options[:user_id])
```

---

#### [MODIFY] [tool_commands.rb](file:///Users/tweibley/adk-ruby/lib/adk/cli/tool_commands.rb)

Add `--user-id` option to `execute` command (~line 115):

```diff
+method_option :user_id, type: :string, default: 'cli_user', desc: 'User ID for the tool context'
 def execute(tool_name, *args)
   # ...
-  dummy_context = ADK::ToolContext.new(session_id: "cli_direct_#{SecureRandom.hex(4)}", user_id: 'cli_user',
+  dummy_context = ADK::ToolContext.new(session_id: "cli_direct_#{SecureRandom.hex(4)}", user_id: options[:user_id],
```

---

## Implementation Details

### Default User ID

The default is `cli_user` for backward compatibility. Users who want to resume sessions should explicitly set `--user-id`.

### Session Resume Behavior

With this change, users can:
1. Start a chat: `adk agent chat my_agent --user-id=taylor`
2. Exit and resume later with same history: `adk agent chat my_agent --user-id=taylor`
3. Use their web user ID to access web-created sessions

### Future Enhancement (Not in scope)

A persistent user ID stored in `~/.adk/config.yml` could be added later so users don't need to specify `--user-id` each time.

---

## Verification Plan

### Automated Tests

#### [MODIFY] [spec/adk/cli/session_commands_spec.rb](file:///Users/tweibley/adk-ruby/spec/adk/cli/session_commands_spec.rb)

Add tests for `--user-id` option:
- Verify default `cli_user` is used when not specified
- Verify custom user_id is passed to session creation

#### [MODIFY] [spec/adk/cli/agent_commands_spec.rb](file:///Users/tweibley/adk-ruby/spec/adk/cli/agent_commands_spec.rb)

Add tests for `--user-id` option on `execute` and `chat` commands.

#### [MODIFY] [spec/adk/cli/tool_commands_spec.rb](file:///Users/tweibley/adk-ruby/spec/adk/cli/tool_commands_spec.rb)

Add tests for `--user-id` option on `execute` command.

### Manual Verification

```bash
# 1. Create session with custom user_id
bundle exec adk agent chat hello_world --user-id=my_user
# Send a message, then exit

# 2. Verify session was created with correct user_id
bundle exec adk session list --user-id=my_user

# 3. Resume session with same user_id
bundle exec adk agent chat hello_world --user-id=my_user
# Should see previous chat history

# 4. Full test suite
bundle exec rspec
```

Ensure 100% line coverage is maintained.
