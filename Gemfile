source 'https://rubygems.org'

# Specify your gem's dependencies in adk-ruby.gemspec
gemspec

# gem 'temporalio', '0.3.0', require: false

gem 'puma' # Add puma for Sinatra's default server

gem 'simplecov', require: false, group: :test

group :development, :test do
  gem 'rspec', '~> 3.12'
  gem 'rake', '~> 13.0'
  gem 'rubocop', '~> 1.50' # <-- Ensure this line is present here
  gem 'yard', '~> 0.9'
  gem 'webmock'
  # gem 'temporalio'
end

group :development do
  gem 'pry', '~> 0.14'
  gem 'pry-byebug', '~> 3.10'
  gem 'dotenv', '~> 2.0'
  # gem 'temporalio'
end

group :test do
  gem 'rspec', '~> 3.12'
  gem 'simplecov', require: false
  gem 'redis-client', '>= 0.22.1' # For testing Redis session service
  gem 'rack-test' # Added for Sinatra/Rack app testing
  gem "sidekiq"
end

gem "fast-mcp", '~> 1.1.0'

# Web UI dependencies
gem 'sinatra', '~> 3.2'
gem 'sinatra-contrib', '~> 3.2' # Provides custom_logger helper
gem 'slim', '~> 5.0'
gem 'sassc'
# Required for webhook dynamic route matching
gem 'mustermann', '~> 3.0'

# Async job processing (Consider making optional?)
# gem "temporalio"

gem 'kramdown' # For Markdown rendering in Web UI Docs
