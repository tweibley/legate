# CLI vs Web UI Feature Comparison

This document analyzes the capabilities exposed via the **CLI** (`bin/adk`) and the **Web UI** (`adk web start`) to identify feature mismatches.

---

## Summary of Mismatches

| Feature | CLI | Web UI | Gap |
|:--------|:---:|:------:|:----|
| **Agent Generation (AI-powered)** | ❌ | ✅ | Web can generate agents via AI prompt |
| **Tool Generation (AI-powered)** | ❌ | ✅ | Web can generate tools via AI prompt |
| **Sidekiq Job Management** | ✅ | ❌ | CLI has `sidekiq start/stop/status/list_jobs` |
| **Deployment Asset Generation** | ✅ | ❌ | CLI has `deployment generate` for cloud platforms |
| **Project Scaffolding** | ✅ | ❌ | CLI has `skaffold generate` to create new projects |
| **Session Management UI** | Partial | ✅ | Web has session switching, delete in chat context |
| **Tool Download/Export** | ❌ | ✅ | Web can download tool code as `.rb` file |
| **Agent Download/Export** | ✅ | ✅ | Both can export agent definitions |
| **Agent Duplication** | ❌ | ✅ | Web can duplicate agents |
| **Authentication Management** | ✅ | ✅ | Both have full auth scheme/credential/mapping management |
| **Agent Auth Assignment** | ❌ | ✅ | Web can assign auth to agents |
| **Documentation Browser** | ❌ | ✅ | Web has `/docs` route for viewing docs |
| **Dashboard/Metrics** | ❌ | ✅ | Web has dashboard with activity, stats |
| **Health Check Endpoint** | ❌ | ✅ | Web exposes `/healthz` |
| **Interactive Chat** | ✅ | ✅ | Both have interactive agent chat |
| **Tool Execution** | ✅ | ❌ | CLI can execute tools directly; Web lacks this |
| **Tool Info/Details** | ✅ | ✅ | Both can show tool details |

---

## Detailed Analysis

### 1. Agent Management

| Capability | CLI Command | Web Route |
|:-----------|:------------|:----------|
| List agents | `adk agent list` | `GET /agents`, `GET /api/agents` |
| View agent details | — | `GET /agents/:name` |
| Create agent | `adk agent save <name>` | `POST /agents` |
| Delete agent | `adk agent delete <name>` | `DELETE /agents/:name` |
| Generate agent boilerplate | `adk agent generate <name>` | — |
| AI-generate agent | ❌ | `POST /agents/generate` |
| Duplicate agent | ❌ | `POST /agents/:name/duplicate` |
| Edit agent fields | ❌ | `PUT /agents/:name/update/:field` |
| Export agent (JSON) | `adk agent export <name>` | `GET /agents/:name/export` |
| Download agent (.rb) | `adk agent export <name>` | `GET /agents/:name/download` |
| Start agent | `adk agent start <name>` | `POST /agents/:name/start` |
| Stop agent | `adk agent stop <name>` | `POST /agents/:name/stop` |
| Execute task | `adk agent execute <name> <task>` | `POST /agents/:name/execute` |
| Interactive chat | `adk agent chat <name>` | `GET/POST /agents/:name/chat` |

**Gaps:**
- CLI lacks: AI generation, duplication, field editing
- Web lacks: `generate` for creating file boilerplate (though AI generation is more powerful)

---

### 2. Tool Management

| Capability | CLI Command | Web Route |
|:-----------|:------------|:----------|
| List tools | `adk tool list` | `GET /tools`, `GET /api/tools` |
| View tool info | `adk tool info <name>` | `GET /tools/:name` |
| Execute tool | `adk tool execute <name> [args]` | ❌ |
| AI-generate tool | ❌ | `POST /tools/generate` |
| Download tool (.rb) | ❌ | `GET /tools/:name/download` |

**Gaps:**
- CLI has direct tool execution; Web does not
- Web has AI generation and download; CLI does not

---

### 3. Session Management

| Capability | CLI Command | Web Route |
|:-----------|:------------|:----------|
| List sessions | `adk session list` | Embedded in chat UI |
| Show session details | `adk session show <id>` | Embedded in chat UI |
| Delete session | `adk session delete <id>` | `DELETE /agents/:name/chat/session/:id` |
| Create new session | — | `POST /agents/:name/chat/session/new` |
| Switch session | — | `POST /agents/:name/chat/session/switch` |
| Execute in session | `adk session execute <agent> <task>` | In chat interaction |

**Gaps:**
- CLI has explicit list/show commands; Web embeds in chat context
- Web has session switching/creation in UI; CLI requires `--session-id` flag

---

### 4. Sidekiq/Background Jobs

| Capability | CLI Command | Web Route |
|:-----------|:------------|:----------|
| Start Sidekiq worker | `adk sidekiq start` | ❌ |
| Stop Sidekiq workers | `adk sidekiq stop` | ❌ |
| Check Sidekiq status | `adk sidekiq status` | ❌ |
| List pending jobs | `adk sidekiq list_jobs` | ❌ |

**Gap:** Web UI has **no Sidekiq management**. This is a significant CLI-only feature.

---

### 5. Authentication

| Capability | CLI Command | Web Route |
|:-----------|:------------|:----------|
| List auth schemes | `adk auth:schemes list` | `GET /auth/schemes` |
| Show auth scheme | `adk auth:schemes show <name>` | — |
| Create auth scheme | `adk auth:schemes create <name>` | `POST /auth/schemes` |
| Delete auth scheme | `adk auth:schemes delete <name>` | `DELETE /auth/schemes/:name` |
| List credentials | `adk auth:credentials list` | `GET /auth/credentials` |
| Show credential | `adk auth:credentials show <name>` | — |
| Create credential | `adk auth:credentials create <name>` | `POST /auth/credentials` |
| Delete credential | `adk auth:credentials delete <name>` | `DELETE /auth/credentials/:name` |
| Test credential | ❌ | `POST /auth/credentials/:name/test` |
| List mappings | `adk auth:mappings list` | `GET /auth/mappings` |
| Create mapping | `adk auth:mappings create` | `POST/PUT /auth/mappings` |
| Delete mapping | `adk auth:mappings delete` | — |
| Auth debug dashboard | ❌ | `GET /auth/debug` |
| Assign auth to agent | ❌ | `POST /agents/:name/auth/assign` |
| Test agent auth | ❌ | `POST /agents/:name/auth/test` |

**Remaining Gaps:**
- CLI lacks: credential testing, auth debug dashboard, agent auth assignment
- Web lacks: individual scheme/credential show commands (uses modal instead)

---

### 6. Deployment & Infrastructure

| Capability | CLI Command | Web Route |
|:-----------|:------------|:----------|
| Generate deployment assets | `adk deployment generate` | ❌ |
| Scaffold new project | `adk skaffold [name]` | ❌ |
| Start web server | `adk web start` | N/A (is the web) |

**Gap:** Web has no deployment or project scaffolding features.

---

### 7. Documentation & Dashboards

| Capability | CLI Command | Web Route |
|:-----------|:------------|:----------|
| View documentation | ❌ | `GET /docs`, `GET /docs/*` |
| Dashboard home | ❌ | `GET /` |
| Recent activity | ❌ | `GET /activity/recent` |
| Health check | ❌ | `GET /healthz` |

**Gap:** These are inherently UI features not needed in CLI.

---

## Recommendations

### Add to CLI (High Priority)
1. **Authentication commands** — ✅ DONE (`adk auth schemes/credentials/mappings`)
2. **Agent stop command** — ✅ DONE (`adk agent stop`)
3. **Export/download agent** — ✅ DONE (`adk agent export`)

### Add to Web UI (High Priority)
1. **Sidekiq dashboard** — Show worker status, queue depths, job list
2. **Tool execution UI** — Form to execute a tool with parameters
3. **Deployment wizard** — UI for `deployment generate` functionality

### Lower Priority
- **CLI**: AI-powered agent/tool generation (could shell out to API)
- **Web**: Project scaffolding (typically done at CLI)

---

## Feature Coverage Matrix

```
                        CLI    WEB
Agent CRUD              ✓      ✓✓
Agent Execution         ✓      ✓
Agent Chat              ✓      ✓
Tool List/Info          ✓      ✓
Tool Execution          ✓      ✗
Tool AI Generation      ✗      ✓
Session Management      ✓      ✓
Sidekiq Management      ✓      ✗
Authentication          ✓✓     ✓✓
Deployment              ✓      ✗
Scaffolding             ✓      ✗
Documentation           ✗      ✓
Dashboard/Metrics       ✗      ✓
```

Legend: ✓ = supported, ✓✓ = full-featured, ✗ = not supported
