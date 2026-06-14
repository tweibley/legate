# frozen_string_literal: true

# Legate configuration. See https://github.com/<your-org>/legate and the guides
# under public/docs for details.
require 'legate/session_service/active_record'

Legate.configure do |config|
  # Persist conversations, events, and state in your app's database. Run
  # `rails generate legate:install` then `rails db:migrate` to create the tables.
  config.session_service = Legate::SessionService::ActiveRecord.new

  # Default model for new agents (override per-agent in the definition).
  # config.default_model_name = 'gemini-3.5-flash'
end

# The gemini-ai gem reads GOOGLE_API_KEY; accept GEMINI_API_KEY as an alias so
# either env var works. Prefer Rails encrypted credentials in production.
ENV['GOOGLE_API_KEY'] ||= ENV['GEMINI_API_KEY'] if ENV['GEMINI_API_KEY']
