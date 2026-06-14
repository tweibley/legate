# frozen_string_literal: true

require 'spec_helper'
require 'legate/session_service/active_record'
require 'legate/agent'
require 'legate/tool'

# Exercises the opt-in ActiveRecord session store against an in-memory SQLite
# database — the full SessionService contract, durability across a cache drop,
# streaming parity, and a real-agent end-to-end run.
RSpec.describe Legate::SessionService::ActiveRecord do
  before(:all) do
    ::ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    described_class.create_tables!
  end

  after(:all) { ::ActiveRecord::Base.remove_connection }

  before do
    described_class::EventRecord.delete_all
    described_class::SessionRecord.delete_all
    described_class::ScopedStateRecord.delete_all
  end

  subject(:service) { described_class.new }

  # A second service over the same DB connection but with a fresh in-process
  # cache — simulates a restart / another process re-hydrating from rows.
  def reloaded = described_class.new

  it 'is persistent' do
    expect(service.persistent?).to be true
  end

  it 'is opt-in: a bare `require "legate"` does not load ActiveRecord' do
    # The store pulls AR in only when this file is required. Verify the library
    # core stays free of it in a clean subprocess (this process already loaded AR).
    script = 'require "legate"; print(defined?(::ActiveRecord) ? "AR-LOADED" : "AR-ABSENT")'
    lib = File.expand_path('../../../lib', __dir__)
    out = `LEGATE_LOG_LEVEL=NONE #{Gem.ruby} -I#{lib} -e '#{script}' 2>/dev/null`
    expect(out).to include('AR-ABSENT')
    expect(out).not_to include('AR-LOADED')
  end

  describe 'create + get round-trip' do
    it 'creates a session and returns the same cached object within the process' do
      session = service.create_session(app_name: 'app', user_id: 'u1', initial_state: { tone: 'formal' })
      expect(service.get_session(session_id: session.id)).to equal(session)
      expect(session.get_state(:tone)).to eq('formal')
    end

    it 'returns nil for an unknown session' do
      expect(service.get_session(session_id: 'nope')).to be_nil
    end

    it 'bounds the in-process cache (LRU), re-hydrating evicted sessions from the DB' do
      small = described_class.new(max_cached_sessions: 2)
      a = small.create_session(app_name: 'app', user_id: 'u1')
      small.create_session(app_name: 'app', user_id: 'u2') # b
      small.create_session(app_name: 'app', user_id: 'u3') # c -> evicts a (LRU)

      cache = small.instance_variable_get(:@cache)
      expect(cache.size).to eq(2)
      expect(cache).not_to have_key(a.id)
      # The evicted session is still retrievable — re-hydrated from the database.
      expect(small.get_session(session_id: a.id)).not_to be_nil
    end

    it 're-hydrates a session (id, app, user, state) from the database' do
      original = service.create_session(app_name: 'app', user_id: 'u1', initial_state: { tone: 'casual' })

      restored = reloaded.get_session(session_id: original.id)
      expect(restored).not_to be_nil
      expect(restored.app_name).to eq('app')
      expect(restored.user_id).to eq('u1')
      expect(restored.get_state(:tone)).to eq('casual')
    end
  end

  describe '#append_event' do
    it 'persists events and the merged state, surviving a cache drop' do
      session = service.create_session(app_name: 'app', user_id: 'u1')
      service.append_event(session_id: session.id,
                           event: Legate::Event.new(role: :user, content: 'hello'))
      service.append_event(session_id: session.id,
                           event: Legate::Event.new(role: :agent, content: { status: :success, result: 'hi' },
                                                    state_delta: { turns: 1 }))

      restored = reloaded.get_session(session_id: session.id)
      expect(restored.events.map(&:role)).to eq(%i[user agent])
      expect(restored.events.last.content['result']).to eq('hi')
      expect(restored.get_state(:turns)).to eq(1)
    end

    it 'returns false for a missing session' do
      expect(service.append_event(session_id: 'nope', event: Legate::Event.new(role: :user, content: 'x'))).to be false
    end

    it 'is atomic: a failed state write rolls back the event row and evicts the stale cache' do
      session = service.create_session(app_name: 'app', user_id: 'u1')
      # Force the state write (second half of the transaction) to fail.
      allow(service).to receive(:write_session_state).and_raise(::ActiveRecord::StatementInvalid, 'disk full')

      ok = service.append_event(session_id: session.id,
                                event: Legate::Event.new(role: :user, content: 'hello'))

      expect(ok).to be false
      # Nothing persisted: the event insert rolled back with the state write.
      expect(described_class::EventRecord.where(legate_session_id: session.id).count).to eq(0)
      # The cached Session (which optimistically got the event) was evicted, so a
      # fresh read reflects the committed truth — no events.
      expect(reloaded.get_session(session_id: session.id).events).to be_empty
    end
  end

  describe 'scoped state' do
    it 'saves, loads, and clears a scoped value' do
      service.save_scoped_state('user:app:u1', 'pref', { theme: 'dark' })
      expect(reloaded.load_scoped_state('user:app:u1', 'pref')).to eq('theme' => 'dark')

      service.clear_scoped_state('user:app:u1', 'pref')
      expect(service.load_scoped_state('user:app:u1', 'pref')).to be_nil
    end

    it 'upserts on repeated saves of the same scope/key' do
      service.save_scoped_state('app:app', 'count', 1)
      service.save_scoped_state('app:app', 'count', 2)
      expect(service.load_scoped_state('app:app', 'count')).to eq(2)
      expect(described_class::ScopedStateRecord.where(scope: 'app:app', state_key: 'count').count).to eq(1)
    end

    it 'wildcard-clears every key under a scope' do
      service.save_scoped_state('temp:s1', 'a', 1)
      service.save_scoped_state('temp:s1', 'b', 2)
      service.save_scoped_state('temp:s2', 'c', 3)

      service.clear_scoped_state('temp:s1', '*')
      expect(service.load_scoped_state('temp:s1', 'a')).to be_nil
      expect(service.load_scoped_state('temp:s2', 'c')).to eq(3)
    end
  end

  describe '#set_state / #get_state' do
    it 'write-throughs plain state so it survives a reload' do
      session = service.create_session(app_name: 'app', user_id: 'u1')
      service.set_state(session_id: session.id, key: :step, value: 'two')
      expect(reloaded.get_state(session_id: session.id, key: :step)).to eq('two')
    end
  end

  describe '#delete_session' do
    it 'removes the session and its events' do
      session = service.create_session(app_name: 'app', user_id: 'u1')
      service.append_event(session_id: session.id, event: Legate::Event.new(role: :user, content: 'x'))

      expect(service.delete_session(session_id: session.id)).to be true
      expect(reloaded.get_session(session_id: session.id)).to be_nil
      expect(described_class::EventRecord.where(legate_session_id: session.id).count).to eq(0)
    end

    it 'returns false for a missing session' do
      expect(service.delete_session(session_id: 'nope')).to be false
    end
  end

  describe '#list_sessions' do
    it 'filters by app_name and user_id' do
      service.create_session(app_name: 'app1', user_id: 'u1')
      service.create_session(app_name: 'app1', user_id: 'u2')
      service.create_session(app_name: 'app2', user_id: 'u1')

      expect(service.list_sessions(app_name: 'app1').size).to eq(2)
      expect(service.list_sessions(user_id: 'u1').size).to eq(2)
      expect(service.list_sessions(app_name: 'app1', user_id: 'u1').size).to eq(1)
    end
  end

  describe 'streaming parity (EventBroadcast)' do
    it 'delivers appended events to subscribers' do
      session = service.create_session(app_name: 'app', user_id: 'u1')
      received = []
      service.subscribe(session.id) { |e| received << e }

      service.append_event(session_id: session.id, event: Legate::Event.new(role: :user, content: 'hi'))
      expect(received.map(&:role)).to eq([:user])
    end
  end

  describe 'end-to-end with a real agent' do
    let(:greeting_tool_class) do
      Class.new(Legate::Tool) do
        self.explicit_tool_name = :greeting
        tool_description 'Greets a name'
        parameter :name, type: :string, required: true

        private

        def perform_execution(params, _context)
          { status: :success, result: "Hello, #{params[:name]}!" }
        end
      end
    end

    before do
      Legate::GlobalToolManager.reset!
      Legate::GlobalToolManager.register_tool(greeting_tool_class)
    end

    it 'persists a full run so it can be reloaded from the database' do
      planner = instance_double(Legate::Planner)
      allow(planner).to receive(:plan).and_return(
        { thought_process: 'greet', steps: [{ tool: :greeting, params: { name: 'World' }, reason: 'greet' }] }
      )
      definition = Legate::AgentDefinition.new
      definition.define do |d|
        d.name :greeter
        d.description 'Greets'
        d.instruction 'Greet people.'
        d.use_tool :greeting
      end
      agent = Legate::Agent.new(definition: definition, session_service: service, planner_override: planner)
      agent.start
      session = service.create_session(app_name: 'greeter', user_id: 'u1')

      agent.run_task(session_id: session.id, user_input: 'greet World', session_service: service)

      restored = reloaded.get_session(session_id: session.id)
      expect(restored.events.map(&:role)).to eq(%i[user tool_request tool_result agent])
      expect(restored.events.last.content['result']).to eq('Hello, World!')
    end
  end
end
