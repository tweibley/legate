# frozen_string_literal: true
# File: spec/spec_helper.rb
require 'bundler/setup'

require 'simplecov'
require 'dotenv/load'

SimpleCov.profiles.define 'adk' do
  add_filter 'lib/adk/web/app.rb'
  add_group 'Tools', 'lib/adk/tools'
  add_group 'Workers', 'lib/adk/workers'
  add_group 'Agents', 'lib/adk/agents'
  add_group 'Events', 'lib/adk/events'
  add_group 'Stores', 'lib/adk/stores'
  add_group 'Utils', 'lib/adk/utils'
  add_group 'Examples', 'examples'
  add_group 'MCP', 'lib/adk/mcp'
  add_group 'CLI', 'lib/adk/cli'
  add_group 'Errors', 'lib/adk/errors'
  add_group 'Session Service', 'lib/adk/session_service'
  add_group 'Web', 'lib/adk/web'
end

SimpleCov.start 'adk'

# --- Load ADK Library ---
require 'adk'
require 'gemini-ai'
# --- End Load ADK ---

require 'webmock/rspec'
# WebMock.disable_net_connect!(allow_localhost: true) # Disable real HTTP requests during tests

require 'timecop' # If using Timecop for time manipulation
# require 'sidekiq/testing' # No longer needed here

# Configure Sidekiq testing mode
# Sidekiq::Testing.fake! # Moved inside RSpec.configure

# --- Global ADK Initialization (if necessary) ---
# Example: Load definitions if your tests rely on pre-defined agents/tools
ADK.configure do |config|
  # config.redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/1') # Use a test Redis DB
  # config.log_level = Logger::DEBUG # Set log level for tests
  config.session_service = ADK::SessionService::InMemory.new # Assign instance directly
  # Load tool definitions needed globally (if any)
  # Note: Prefer defining mocks/stubs within tests where possible
  # config.tool_paths << File.expand_path('../adk/fixtures/tools', __dir__)
end

# Optional: Load definition files if needed for multiple specs
# definition_files = Dir.glob(File.expand_path('../../examples/definitions/**/*.rb', __dir__))
# definition_files.each { |file| load file }

RSpec.configure do |config|
  # Load and configure Sidekiq testing mode here
  require 'sidekiq/testing'
  Sidekiq::Testing.fake! # Use :fake! for inline testing by default, or :inline! for real execution

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Optional: Run specs in random order to surface order dependencies.
  # config.order = :random
  # Kernel.srand config.seed

  # Optional: Mute the ADK logger during tests unless specifically needed
  # This prevents cluttering test output with normal INFO/DEBUG logs.
  # You can override this in specific tests if needed.
  config.before(:suite) do
    # Set log level high to silence it for most tests
    ADK.logger.level = Logger::FATAL + 1 # Higher than FATAL
  end

  # Optional: Reset logger level after suite if needed elsewhere
  # config.after(:suite) do
  #   # Reset based on ENV or default
  #   # ADK.instance_variable_set(:@logger, nil) # Force re-init
  #   # ADK.logger # Trigger re-init
  # end

  # Clean up Sidekiq jobs between tests
  config.before(:each) do
    Sidekiq::Worker.clear_all
  end

  # Clean up GlobalToolManager between tests to prevent state leakage
  config.after(:each) do
    ADK::GlobalToolManager.reset!
  end

  # Optional: Reset Timecop after each test if used
  config.after(:each) do
    Timecop.return
  end
end
