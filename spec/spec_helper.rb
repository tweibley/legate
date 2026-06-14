# frozen_string_literal: true

# File: spec/spec_helper.rb
require 'bundler/setup'

require 'simplecov'
require 'dotenv/load'

SimpleCov.profiles.define 'legate' do
  add_filter 'lib/legate/web/app.rb'
  add_group 'Tools', 'lib/legate/tools'
  add_group 'Workers', 'lib/legate/workers'
  add_group 'Agents', 'lib/legate/agents'
  add_group 'Events', 'lib/legate/events'
  add_group 'Stores', 'lib/legate/stores'
  add_group 'Utils', 'lib/legate/utils'
  add_group 'Examples', 'examples'
  add_group 'MCP', 'lib/legate/mcp'
  add_group 'CLI', 'lib/legate/cli'
  add_group 'Errors', 'lib/legate/errors'
  add_group 'Session Service', 'lib/legate/session_service'
  add_group 'Web', 'lib/legate/web'
end

SimpleCov.start 'legate'

# --- Load Legate Library ---
require 'legate'
require 'gemini-ai'
# --- End Load Legate ---

require 'webmock/rspec'
# WebMock.disable_net_connect!(allow_localhost: true) # Disable real HTTP requests during tests

require 'timecop' # If using Timecop for time manipulation

# --- Global Legate Initialization (if necessary) ---
# Example: Load definitions if your tests rely on pre-defined agents/tools
Legate.configure do |config|
  config.session_service = Legate::SessionService::InMemory.new # Assign instance directly
end

# Optional: Load definition files if needed for multiple specs
# definition_files = Dir.glob(File.expand_path('../../examples/definitions/**/*.rb', __dir__))
# definition_files.each { |file| load file }

RSpec.configure do |config|
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

  # Optional: Mute the Legate logger during tests unless specifically needed
  # This prevents cluttering test output with normal INFO/DEBUG logs.
  # You can override this in specific tests if needed.
  config.before(:suite) do
    # Set log level high to silence it for most tests
    Legate.logger.level = Logger::FATAL + 1 # Higher than FATAL
  end

  # Optional: Reset logger level after suite if needed elsewhere
  # config.after(:suite) do
  #   # Reset based on ENV or default
  #   # Legate.instance_variable_set(:@logger, nil) # Force re-init
  #   # Legate.logger # Trigger re-init
  # end

  # Clean up GlobalToolManager between tests to prevent state leakage
  config.after(:each) do
    Legate::GlobalToolManager.reset!
  end

  # Optional: Reset Timecop after each test if used
  config.after(:each) do
    Timecop.return
  end
end
