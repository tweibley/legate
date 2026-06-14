# File: lib/legate/rails.rb
# frozen_string_literal: true

# Opt-in Rails integration. Require this (not just 'legate') inside a Rails app —
# e.g. in the Gemfile: `gem 'legate', require: 'legate/rails'`. It loads the
# Railtie, which registers the `legate:install` generator and the optional
# ActiveRecord session-store wiring. `require 'legate'` alone never touches Rails.
require 'legate'
require_relative 'rails/railtie'
