# frozen_string_literal: true

require 'spec_helper'
require 'legate/rails'
require 'legate/generators/legate/install_generator'
require 'legate/session_service/active_record'

# Coverage for the opt-in Rails glue (R7): the Railtie, the install generator,
# and — most importantly — that the generated migration produces a schema the
# ActiveRecord session store actually works against (drift protection).
RSpec.describe 'Rails integration' do
  let(:templates_dir) { File.expand_path('../../lib/legate/generators/legate/templates', __dir__) }

  describe Legate::Rails::Railtie do
    it 'is a Rails::Railtie' do
      expect(described_class.ancestors).to include(::Rails::Railtie)
    end

    it 'exposes config.legate as ordered options' do
      expect(described_class.config.legate).to be_a(::ActiveSupport::OrderedOptions)
    end
  end

  describe Legate::Generators::InstallGenerator do
    it 'is a Rails generator whose source_root holds both templates' do
      expect(described_class.ancestors).to include(::Rails::Generators::Base)
      expect(File.exist?(File.join(described_class.source_root, 'create_legate_tables.rb.tt'))).to be true
      expect(File.exist?(File.join(described_class.source_root, 'initializer.rb'))).to be true
    end

    it 'defines the migration and initializer creation steps' do
      expect(described_class.instance_method(:create_migration_file)).to be_a(UnboundMethod)
      expect(described_class.instance_method(:create_initializer_file)).to be_a(UnboundMethod)
    end
  end

  describe 'templates are valid Ruby' do
    it 'compiles the migration template' do
      src = File.read(File.join(templates_dir, 'create_legate_tables.rb.tt'))
      expect { RubyVM::InstructionSequence.compile(src) }.not_to raise_error
    end

    it 'compiles the initializer template' do
      src = File.read(File.join(templates_dir, 'initializer.rb'))
      expect { RubyVM::InstructionSequence.compile(src) }.not_to raise_error
    end
  end

  describe 'the generated migration' do
    before(:all) do
      ::ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
      src = File.read(File.expand_path('../../lib/legate/generators/legate/templates/create_legate_tables.rb.tt', __dir__))
      # The template has no ERB tags (the migration superclass version is fixed),
      # so it is plain Ruby — eval it and run it forward against the fresh DB.
      eval(src) # rubocop:disable Security/Eval -- trusted first-party template, under test
      CreateLegateTables.new.tap { |m| m.verbose = false }.migrate(:up)
    end

    after(:all) { ::ActiveRecord::Base.remove_connection }

    it 'creates the three Legate tables' do
      conn = ::ActiveRecord::Base.connection
      expect(conn.table_exists?(:legate_sessions)).to be true
      expect(conn.table_exists?(:legate_events)).to be true
      expect(conn.table_exists?(:legate_scoped_states)).to be true
    end

    it 'produces a schema the ActiveRecord store works against' do
      store = Legate::SessionService::ActiveRecord.new
      session = store.create_session(app_name: 'app', user_id: 'u1')
      store.append_event(session_id: session.id,
                         event: Legate::Event.new(role: :user, content: 'hi', state_delta: { turns: 1 }))

      restored = Legate::SessionService::ActiveRecord.new.get_session(session_id: session.id)
      expect(restored.events.map(&:role)).to eq([:user])
      expect(restored.get_state(:turns)).to eq(1)
    end
  end
end
