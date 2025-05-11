# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in adk-ruby.gemspec
gemspec

# gem 'temporalio', '0.3.0', require: false

gem 'puma' # Add puma for Sinatra's default server

group :development, :test do
  gem 'rubocop', '~> 1.50' # <-- Ensure this line is present here
  gem 'yard', '~> 0.9'
  # gem 'temporalio'
end

group :development do
  gem 'dotenv', '~> 2.0'
  gem 'pry', '~> 0.14'
  gem 'pry-byebug', '~> 3.10'
  # gem 'temporalio'
end

group :test do
  gem 'rack-test' # Added for Sinatra/Rack app testing
  gem 'redis-client', '>= 0.22.1' # For testing Redis session service
  gem 'rspec', '~> 3.12'
  gem 'sidekiq', '~> 7.3'
  gem 'simplecov', '~> 0.21', require: false
  gem 'webmock', '~> 3.18'
end

gem 'fast-mcp', '~> 1.1.0'

# Web UI dependencies
gem 'sassc'
gem 'sinatra', '~> 3.2'
gem 'sinatra-contrib', '~> 3.2' # Provides custom_logger helper
gem 'slim', '~> 5.0'
# Required for webhook dynamic route matching
gem 'mustermann', '~> 3.0'

# Async job processing (Consider making optional?)
# gem "temporalio"

# for cli ui
gem 'cli-ui'
gem 'reline'

gem 'kramdown' # For Markdown rendering in Web UI Docs
gem 'kramdown-parser-gfm' # For GitHub Flavored Markdown support
