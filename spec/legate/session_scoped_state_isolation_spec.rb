# frozen_string_literal: true

# Regression coverage for scoped-state isolation (security: cross-user bleed).
#
# Session previously passed the bare prefix ('user'/'app'/'temp') to the session
# service, so every user shared one global slot per prefix and could read/clear
# each other's state. Session now qualifies the namespace by owner identity. This
# spec drives a REAL InMemory service (no stubbing of the lookup) and asserts the
# isolation/sharing semantics directly.
require 'spec_helper'
require 'legate/session'
require 'legate/session_service/in_memory'

RSpec.describe 'Legate::Session scoped-state isolation' do
  let(:service) { Legate::SessionService::InMemory.new }

  def session_for(app:, user:, id: nil)
    Legate::Session.new(id: id, app_name: app, user_id: user, session_service: service)
  end

  describe 'user: scope' do
    it 'isolates different users in the same app' do
      alice = session_for(app: 'app1', user: 'alice')
      bob   = session_for(app: 'app1', user: 'bob')

      alice.set_state('user:theme', 'dark')
      bob.set_state('user:theme', 'light')

      expect(alice.get_state('user:theme')).to eq('dark')
      expect(bob.get_state('user:theme')).to eq('light')
    end

    it 'shares state across sessions of the same user (the point of user:)' do
      first = session_for(app: 'app1', user: 'alice')
      first.set_state('user:theme', 'dark')

      second = session_for(app: 'app1', user: 'alice') # new session, same user
      expect(second.get_state('user:theme')).to eq('dark')
    end

    it 'isolates the same user across different apps' do
      in_app1 = session_for(app: 'app1', user: 'alice')
      in_app2 = session_for(app: 'app2', user: 'alice')

      in_app1.set_state('user:theme', 'dark')
      expect(in_app2.get_state('user:theme')).to be_nil
    end
  end

  describe 'app: scope' do
    it 'is shared across users of the same app' do
      alice = session_for(app: 'app1', user: 'alice')
      bob   = session_for(app: 'app1', user: 'bob')

      alice.set_state('app:banner', 'hello')
      expect(bob.get_state('app:banner')).to eq('hello')
    end

    it 'is isolated between apps' do
      app1 = session_for(app: 'app1', user: 'alice')
      app2 = session_for(app: 'app2', user: 'alice')

      app1.set_state('app:banner', 'hello')
      expect(app2.get_state('app:banner')).to be_nil
    end
  end

  describe 'temp: scope' do
    it 'is isolated per session' do
      a = session_for(app: 'app1', user: 'alice', id: 'sess-a')
      b = session_for(app: 'app1', user: 'alice', id: 'sess-b')

      a.set_state('temp:scratch', 1)
      expect(b.get_state('temp:scratch')).to be_nil
    end
  end

  describe '#clear_state!' do
    it 'clears only the calling owner, not other users' do
      alice = session_for(app: 'app1', user: 'alice')
      bob   = session_for(app: 'app1', user: 'bob')

      alice.set_state('user:theme', 'dark')
      bob.set_state('user:theme', 'light')

      alice.clear_state!

      expect(alice.get_state('user:theme')).to be_nil
      expect(bob.get_state('user:theme')).to eq('light')
    end
  end

  describe 'identity separator safety' do
    it 'does not let a crafted user_id traverse into another namespace' do
      victim   = session_for(app: 'app1', user: 'alice')
      attacker = session_for(app: 'app1', user: 'alice:pref') # tries to collide

      victim.set_state('user:secret', 'v')
      # Without escaping, attacker's namespace would overlap victim's "user:app1:alice:..."
      expect(attacker.get_state('user:secret')).to be_nil
    end
  end
end
