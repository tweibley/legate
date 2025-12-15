# CLI Authentication Commands

Bring authentication management capabilities to the CLI, matching the web UI functionality.

## User Review Required

> [!IMPORTANT]
> This adds a new `adk auth` command group. The commands will interact with the same `ADK::Auth::Manager` singleton used by the web UI.

## Background

Currently, all authentication configuration (schemes, credentials, URL mappings) is only accessible through the web UI. This creates a gap for headless/CI environments and users who prefer CLI workflows.

The web UI exposes these auth features via `/auth/*` routes in [authentication_routes.rb](file:///Users/tweibley/adk-ruby/lib/adk/web/routes/authentication_routes.rb). We'll mirror this functionality in the CLI.

---

## Proposed Changes

### CLI Commands Module

#### [NEW] [auth_commands.rb](file:///Users/tweibley/adk-ruby/lib/adk/cli/auth_commands.rb)

New Thor subcommand class for authentication management:

```ruby
module ADK
  module CLI
    class AuthCommands < Thor
      namespace :auth
      
      # Schemes subcommand group
      desc "schemes SUBCOMMAND", "Manage authentication schemes"
      subcommand "schemes", AuthSchemeCommands
      
      # Credentials subcommand group  
      desc "credentials SUBCOMMAND", "Manage authentication credentials"
      subcommand "credentials", AuthCredentialCommands
      
      # Mappings subcommand group
      desc "mappings SUBCOMMAND", "Manage URL-to-auth mappings"
      subcommand "mappings", AuthMappingCommands
    end
  end
end
```

**Commands to implement:**

| Command | Description |
|---------|-------------|
| `adk auth schemes list` | List registered auth schemes |
| `adk auth schemes show <name>` | Show scheme details |
| `adk auth schemes create <name> --type=<type>` | Create new scheme |
| `adk auth schemes delete <name>` | Delete a scheme |
| `adk auth credentials list` | List credentials (masked) |
| `adk auth credentials show <name>` | Show credential details |
| `adk auth credentials create <name> --type=<type>` | Create credential |
| `adk auth credentials update <name>` | Update credential |
| `adk auth credentials delete <name>` | Delete credential |
| `adk auth credentials test <name>` | Test credential validity |
| `adk auth mappings list` | List URL mappings |
| `adk auth mappings create` | Create new mapping |
| `adk auth mappings delete <index>` | Delete mapping by index |

---

#### [MODIFY] [cli.rb](file:///Users/tweibley/adk-ruby/lib/adk/cli.rb)

Register the new `auth` subcommand:

```diff
+require_relative 'cli/auth_commands'

 module ADK
   module CLI
     class Main < Thor
       # existing subcommand registrations...
+      desc "auth SUBCOMMAND", "Manage authentication schemes and credentials"
+      subcommand "auth", AuthCommands
     end
   end
 end
```

---

### Supporting Files

#### [NEW] [auth_scheme_commands.rb](file:///Users/tweibley/adk-ruby/lib/adk/cli/auth_scheme_commands.rb)

Implements scheme management commands (`list`, `show`, `create`, `delete`).

#### [NEW] [auth_credential_commands.rb](file:///Users/tweibley/adk-ruby/lib/adk/cli/auth_credential_commands.rb)

Implements credential management commands (`list`, `show`, `create`, `update`, `delete`, `test`).

#### [NEW] [auth_mapping_commands.rb](file:///Users/tweibley/adk-ruby/lib/adk/cli/auth_mapping_commands.rb)

Implements URL mapping commands (`list`, `create`, `delete`).

---

## Implementation Details

### Auth Manager Access

The CLI will use the same `ADK::Auth::Manager.instance` singleton. To ensure persistence works, we'll need to:

1. Ensure Redis store is configured (via `ADK.configure` or env vars)
2. Call `auth_manager.load_from_store` before operations
3. Use `persist: true` when registering/unregistering items

### Credential Masking

Sensitive values (api_key, client_secret, bearer_token, etc.) will be masked in output:
- Show first 4 chars + `********` + last 4 chars
- For environment variable references (`ENV:VAR_NAME`), show as-is (not resolved)

### CLI UI Styling

Follow existing patterns from [agent_commands.rb](file:///Users/tweibley/adk-ruby/lib/adk/cli/agent_commands.rb):
- Use `CLI::UI` for styled output
- Purple color scheme (per `AGENTS.md` color guidelines)
- Table formatting for list commands

---

## Verification Plan

### Automated Tests

#### [NEW] [spec/adk/cli/auth_commands_spec.rb](file:///Users/tweibley/adk-ruby/spec/adk/cli/auth_commands_spec.rb)

Unit tests covering:
- Schemes: list, show, create, delete
- Credentials: list, show, create, update, delete, test
- Mappings: list, create, delete
- Error handling: missing items, validation failures
- Output formatting: masked credentials, table display

Run with:
```bash
bundle exec rspec spec/adk/cli/auth_commands_spec.rb
```

### Manual Verification

1. **Schemes workflow:**
```bash
bundle exec adk auth schemes list
bundle exec adk auth schemes create my_api_key --type=api_key
bundle exec adk auth schemes show my_api_key
bundle exec adk auth schemes delete my_api_key
```

2. **Credentials workflow:**
```bash
bundle exec adk auth credentials list
bundle exec adk auth credentials create test_key --type=api_key --api-key="ENV:MY_API_KEY"
bundle exec adk auth credentials show test_key
bundle exec adk auth credentials test test_key
bundle exec adk auth credentials delete test_key
```

3. **Mappings workflow:**
```bash
bundle exec adk auth mappings list
bundle exec adk auth mappings create --pattern="https://api.example.com/*" --scheme=my_api_key --credential=test_key
bundle exec adk auth mappings delete 0
```

4. **Full test suite:**
```bash
bundle exec rspec
```

Ensure 100% line coverage is maintained.
