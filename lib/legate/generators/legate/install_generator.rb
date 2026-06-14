# File: lib/legate/generators/legate/install_generator.rb
# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/migration'

module Legate
  module Generators
    # `rails generate legate:install` — creates the migration for the
    # ActiveRecord session store and an initializer that wires it up.
    class InstallGenerator < ::Rails::Generators::Base
      include ::Rails::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      desc 'Creates the Legate session-store migration and initializer.'

      # Rails requires generators that create migrations to provide the next
      # migration number; mirror ActiveRecord's own implementation.
      def self.next_migration_number(dirname)
        next_num = current_migration_number(dirname) + 1
        ::ActiveRecord::Migration.next_migration_number(next_num)
      end

      def create_migration_file
        migration_template 'create_legate_tables.rb.tt',
                           'db/migrate/create_legate_tables.rb'
      end

      def create_initializer_file
        template 'initializer.rb', 'config/initializers/legate.rb'
      end
    end
  end
end
