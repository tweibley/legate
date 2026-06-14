# File: lib/legate/web.rb
# frozen_string_literal: true

# Opt-in entry point for the Legate web UI. Require this (not 'legate' alone)
# when you want the Sinatra app and webhook listener. Keeps the web stack
# (Sinatra, Puma, Slim, sass-embedded) out of the core library load path.
require_relative '../legate' unless defined?(Legate::Agent)
require_relative 'web/app'
require_relative 'web/webhook_listener'
