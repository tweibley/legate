# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in legate.gemspec
gemspec

group :development, :test do
  gem 'rubocop', '~> 1.50'
  gem 'tty-spinner', '~> 0.9.3'
  gem 'yard', '~> 0.9'
end

group :development do
  gem 'dotenv'
  gem 'pry', '~> 0.14'
  gem 'pry-byebug', '~> 3.10'
end

group :test do
  gem 'activerecord', '>= 7.0' # exercises the opt-in AR session store
  gem 'rack-test'
  gem 'railties', '>= 7.0' # exercises the opt-in Railtie + install generator
  gem 'rspec', '~> 3.12'
  gem 'rspec_junit_formatter'
  gem 'simplecov', '~> 0.21', require: false
  gem 'sqlite3', '>= 1.6' # AR adapter for the session-store specs
  gem 'webmock', '~> 3.18'
end
