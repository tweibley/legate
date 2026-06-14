# Rails integration

Legate runs in any Ruby program, but it ships first-class glue for Rails: a
durable ActiveRecord session store, a Railtie, and an install generator. None of
it is loaded unless you ask for it — `require 'legate'` never touches Rails or
ActiveRecord.

## Install

Add the gem and require the Rails integration:

```ruby
# Gemfile
gem 'legate', require: 'legate/rails'
```

Then run the generator and migrate:

```sh
bin/rails generate legate:install
bin/rails db:migrate
```

That creates two files:

- **`db/migrate/…_create_legate_tables.rb`** — the schema for the session store
  (`legate_sessions`, `legate_events`, `legate_scoped_states`).
- **`config/initializers/legate.rb`** — points Legate at the ActiveRecord store
  and maps `GEMINI_API_KEY` → `GOOGLE_API_KEY` for the planner.

The initializer wires the store explicitly, so you stay in control:

```ruby
require 'legate/session_service/active_record'

Legate.configure do |config|
  config.session_service = Legate::SessionService::ActiveRecord.new
end
```

(Prefer Rails encrypted credentials for the API key in production rather than a
plain env var.)

## Durable sessions

With the ActiveRecord store configured, every conversation — its events and its
state — is persisted to your database and survives restarts. The store behaves
exactly like the in-memory one within a single run (the agent sees one live
`Session` object), but writes through on every change, so another process or a
later request re-hydrates the committed history:

```ruby
service = Legate.config.session_service               # the AR store
session = service.create_session(app_name: 'support', user_id: current_user.id)

agent.run_task(session_id: session.id, user_input: params[:message], session_service: service)

# …later, another request / process:
restored = service.get_session(session_id: session.id)
restored.events   # the full persisted history
restored.get_state(:some_key)
```

`persistent?` returns `true`, and scoped state (`user:` / `app:` / `temp:` keys)
is persisted too.

## Running agents in the background (ActiveJob)

Agent runs can take many seconds — do them off the request thread. Because the
store is durable, the controller enqueues a job and reads the result back from
the persisted session when it's done (poll, or push via Turbo/ActionCable):

```ruby
class LegateRunJob < ApplicationJob
  queue_as :default

  def perform(agent_name:, session_id:, message:)
    agent = MyAgents.build(agent_name)   # your factory: definition -> started Agent
    agent.run_task(
      session_id: session_id,
      user_input: message,
      session_service: Legate.config.session_service,
    )
    # The final answer + full history are now persisted on the session.
  end
end
```

```ruby
# app/controllers/messages_controller.rb
session = Legate.config.session_service.create_session(app_name: 'support', user_id: current_user.id)
LegateRunJob.perform_later(agent_name: 'support', session_id: session.id, message: params[:message])
render json: { session_id: session.id }
```

Pair this with [event streaming](streaming): pass an `on_event:` callback to
`run_task` inside the job to broadcast progress over ActionCable as each tool
runs.

## Without Rails

The store is plain ActiveRecord — you can use it in any Ruby program. Establish a
connection and create the tables yourself:

```ruby
require 'active_record'
require 'legate/session_service/active_record'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'legate.db')
Legate::SessionService::ActiveRecord.create_tables!   # idempotent

Legate.configure { |c| c.session_service = Legate::SessionService::ActiveRecord.new }
```

The host application owns the connection and pool; Legate doesn't manage it.

## Notes

- Event content and state are stored as JSON. Resumed (historical) event content
  comes back with string keys — the live run uses in-memory objects with their
  original keys, so this only affects how you read prior turns.
- The schema is portable across SQLite, PostgreSQL, and MySQL (JSON stored as
  text); the generated migration matches `ActiveRecord.create_tables!`.

## Related

- [Streaming agent events](streaming) — progress over ActionCable from a job.
- [LLM Providers](llm_providers) — configuring the model in the initializer.
