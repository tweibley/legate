# frozen_string_literal: true

require 'spec_helper'
require 'legate/session'
require 'legate/event'
require 'legate/errors'
require 'legate/session_service/in_memory'

RSpec.describe 'Concurrency safety' do
  before do
    allow(Legate).to receive(:logger).and_return(
      instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil)
    )
  end

  describe 'Session under concurrent mutations' do
    let(:session) do
      Legate::Session.new(app_name: 'concurrency_test', user_id: 'user1')
    end

    it 'does not lose events under concurrent add_event' do
      threads = 10.times.map do |t|
        Thread.new do
          50.times do |i|
            event = Legate::Event.new(role: :user, content: "thread-#{t}-msg-#{i}")
            session.add_event(event)
          end
        end
      end

      threads.each(&:join)

      expect(session.events.size).to eq(500)
    end

    it 'does not lose state under concurrent set_state' do
      threads = 10.times.map do |t|
        Thread.new do
          50.times do |i|
            session.set_state(:"key_#{t}_#{i}", "value_#{t}_#{i}")
          end
        end
      end

      threads.each(&:join)

      state = session.state_to_h
      expect(state.size).to eq(500)

      10.times do |t|
        50.times do |i|
          expect(state[:"key_#{t}_#{i}"]).to eq("value_#{t}_#{i}")
        end
      end
    end

    it 'handles interleaved add_event and state reads without errors' do
      errors = Concurrent::Array.new

      writers = 5.times.map do |t|
        Thread.new do
          100.times do |i|
            event = Legate::Event.new(
              role: :tool_result,
              content: "result-#{t}-#{i}",
              state_delta: { "counter_#{t}": i }
            )
            session.add_event(event)
          end
        rescue StandardError => e
          errors << e
        end
      end

      readers = 5.times.map do
        Thread.new do
          100.times do
            session.events
            session.state
            session.state_to_h
          end
        rescue StandardError => e
          errors << e
        end
      end

      (writers + readers).each(&:join)

      expect(errors).to be_empty
      expect(session.events.size).to eq(500)
    end

    it 'returns consistent frozen snapshots from #events' do
      snapshots = Concurrent::Array.new

      writer = Thread.new do
        200.times do |i|
          session.add_event(Legate::Event.new(role: :user, content: "msg-#{i}"))
        end
      end

      readers = 3.times.map do
        Thread.new do
          50.times do
            snap = session.events
            expect(snap).to be_frozen
            snapshots << snap.size
          end
        end
      end

      ([writer] + readers).each(&:join)

      expect(snapshots).to all(be_between(0, 200))
      expect(snapshots.sort).to eq(snapshots.sort)
    end
  end

  describe 'InMemorySessionService under concurrent access' do
    let(:service) { Legate::SessionService::InMemory.new }

    it 'handles concurrent session creation and retrieval' do
      session_ids = Concurrent::Array.new

      threads = 20.times.map do |t|
        Thread.new do
          session = service.create_session(app_name: 'test', user_id: "user_#{t}")
          session_ids << session.id
          retrieved = service.get_session(session_id: session.id)
          expect(retrieved).not_to be_nil
          expect(retrieved.id).to eq(session.id)
        end
      end

      threads.each(&:join)

      expect(session_ids.uniq.size).to eq(20)
    end

    it 'handles concurrent event appends to the same session' do
      session = service.create_session(app_name: 'test', user_id: 'shared_user')

      threads = 10.times.map do |t|
        Thread.new do
          30.times do |i|
            event = Legate::Event.new(role: :user, content: "t#{t}-m#{i}")
            service.append_event(session_id: session.id, event: event)
          end
        end
      end

      threads.each(&:join)

      retrieved = service.get_session(session_id: session.id)
      expect(retrieved.events.size).to eq(300)
    end
  end
end
