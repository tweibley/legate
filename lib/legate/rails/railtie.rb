# File: lib/legate/rails/railtie.rb
# frozen_string_literal: true

# In a booted Rails app these are already loaded; require them explicitly so a
# cold `require 'legate/rails'` (e.g. in tests) doesn't trip on missing
# ActiveSupport core extensions that rails/railtie assumes.
require 'active_support'
require 'active_support/core_ext/module/delegation'
require 'rails/railtie'

module Legate
  module Rails
    # Integrates Legate with a host Rails application. Loaded via
    # `require 'legate/rails'` (e.g. `gem 'legate', require: 'legate/rails'`),
    # never by `require 'legate'`.
    #
    # It registers the `legate:install` generator and exposes `config.legate`.
    # The wiring itself (pointing the session store at ActiveRecord, reading the
    # API key) lives in the generated `config/initializers/legate.rb`, so apps
    # stay in control — the Railtie forces nothing.
    class Railtie < ::Rails::Railtie
      config.legate = ::ActiveSupport::OrderedOptions.new

      # Make `rails generate legate:install` discoverable.
      generators do
        require 'legate/generators/legate/install_generator'
      end

      # Optional convenience: if the app sets `config.legate.use_active_record_store`
      # truthy, point Legate at the ActiveRecord store after initialization
      # (when the DB connection is ready). Apps that prefer to do this themselves
      # in the initializer simply leave it unset.
      initializer 'legate.session_store' do |app|
        if app.config.legate.use_active_record_store
          require 'legate/session_service/active_record'
          Legate.configure do |c|
            c.session_service = Legate::SessionService::ActiveRecord.new
          end
        end
      end
    end
  end
end
