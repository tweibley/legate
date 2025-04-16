# File: spec/spec_helper.rb
require 'bundler/setup'
# --- Load ADK Library ---
require 'adk'
require 'gemini-ai'
# --- End Load ADK ---

require 'webmock/rspec'
# WebMock.disable_net_connect!(allow_localhost: true) # Disable real HTTP requests during tests

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

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
end
