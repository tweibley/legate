source 'https://rubygems.org'

# Specify your gem's dependencies in adk-ruby.gemspec
gemspec

# gem 'temporalio', '0.3.0', require: false

gem 'puma' # Add puma for Sinatra's default server

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

gem "sidekiq"

gem "fast-mcp", '~> 1.1.0'
