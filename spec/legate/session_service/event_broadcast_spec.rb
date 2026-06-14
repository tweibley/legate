# frozen_string_literal: true

require 'spec_helper'
require 'legate/session_service/in_memory'
require 'legate/event'

# Exercises the EventBroadcast pub/sub through the real InMemory service, since
# append_event is where broadcasting is triggered (R3 streaming seam).
RSpec.describe Legate::SessionService::EventBroadcast do
  subject(:service) { Legate::SessionService::InMemory.new }

  let(:session) { service.create_session(app_name: 'app', user_id: 'u1') }
  let(:event) { Legate::Event.new(role: :agent, content: { status: :success, result: 'ok' }) }

  def append(target_session = session, evt = event)
    service.append_event(session_id: target_session.id, event: evt)
  end

  it 'delivers appended events to a subscriber of that session' do
    received = []
    service.subscribe(session.id) { |e| received << e }

    append
    expect(received).to eq([event])
  end

  it 'stops delivering after unsubscribe' do
    received = []
    handle = service.subscribe(session.id) { |e| received << e }

    append
    service.unsubscribe(handle)
    append

    expect(received.size).to eq(1)
  end

  it 'does not deliver events from a different session' do
    other = service.create_session(app_name: 'app', user_id: 'u2')
    received = []
    service.subscribe(session.id) { |e| received << e }

    append(other)
    expect(received).to be_empty
  end

  it 'isolates a raising subscriber: persistence succeeds and other subscribers still fire' do
    good = []
    service.subscribe(session.id) { |_e| raise 'boom' }
    service.subscribe(session.id) { |e| good << e }

    expect(append).to be true
    expect(good).to eq([event])
  end

  it 'requires a block to subscribe' do
    expect { service.subscribe(session.id) }.to raise_error(ArgumentError)
  end

  it 'is a no-op to unsubscribe nil or a stale handle' do
    handle = service.subscribe(session.id) { |_e| nil }
    service.unsubscribe(handle)
    expect { service.unsubscribe(nil) }.not_to raise_error
    expect { service.unsubscribe(handle) }.not_to raise_error
  end

  it 'supports multiple subscribers on the same session' do
    a = []
    b = []
    service.subscribe(session.id) { |e| a << e }
    service.subscribe(session.id) { |e| b << e }

    append
    expect(a).to eq([event])
    expect(b).to eq([event])
  end
end
