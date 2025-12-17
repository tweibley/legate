# frozen_string_literal: true

# File: lib/adk.rb
require 'dotenv/load' if File.exist?('.env') # Load early for ENV vars

# frozen_string_literal: true
require 'logger'
require 'sidekiq'
require_relative 'adk/version'
require 'redis'
require 'forwardable'
require 'openssl' # For HMAC in validator

# --- Eager Logger Initialization (Moved BEFORE other ADK requires) ---
module ADK
  SILENT_LOG_LEVELS = %w[NONE SILENT].freeze

  class << self
    # --- Logger Initialization Logic ---
    def initialize_logger
      default_level = ENV['RACK_ENV'] == 'development' ? 'DEBUG' : 'WARN'
      level_str = ENV['ADK_LOG_LEVEL']&.upcase || default_level
      log_target = $stdout
      if SILENT_LOG_LEVELS.include?(level_str)
        log_target = IO::NULL
        level = Logger::FATAL + 1
      else
        level = case level_str
                when 'DEBUG' then Logger::DEBUG
                when 'INFO' then Logger::INFO
                when 'WARN' then Logger::WARN
                when 'ERROR' then Logger::ERROR
                when 'FATAL' then Logger::FATAL
                else Logger::WARN
                end
      end
      logger_instance = Logger.new(log_target)
      logger_instance.level = level
      logger_instance.formatter = proc { |severity, _, _, msg| "#{severity}: #{msg}\n" }
      unless SILENT_LOG_LEVELS.include?(level_str)
        puts "--> ADK Logger initialized with level: #{level_str}, target: #{log_target == IO::NULL ? 'NULL' : 'STDOUT'}"
      end
      logger_instance
    end

    # --- Define Logger Accessor Method EARLY ---
    def logger
      @logger
    end
  end

  @logger = initialize_logger
end
# --- End Eager Logger Initialization & Accessor ---

# --- NOW Require Configuration (Depends on Logger for its own initialization maybe?) ---
require_relative 'adk/configuration'

# --- Central ADK Module (Reopened) ---
module ADK
  @configuration = nil
  @redis_options = {
    url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
  }

  def self.load_environment
    begin
      require 'bundler/setup'
    rescue LoadError
      # Ignore if Bundler is not used or gem not found
    end

    begin
      # dotenv/load requires .env to exist, unlike dotenv which doesn't error
      # Let's keep the original top-level require for now as it's simpler
      # and handles the File.exist? check. If we want this method to be the
      # sole source, we'd need to replicate that logic here or use `Dotenv.load`.
      # For now, we'll just try to load dotenv/load again in case the top-level
      # one wasn't run (e.g., if adk is loaded without the top-level file directly)
      require 'dotenv/load'
    rescue LoadError
      # Ignore if dotenv gem is not used or .env doesn't exist
    end
  end

  # Configure ADK settings
  def self.configure
    # Initialize configuration only once
    @configuration ||= ADK::Configuration.new # Configuration class is now loaded
    yield @configuration # Yield the instance
    # Reconfigure Sidekiq if Redis settings change after yield
    configure_sidekiq
  end

  # Returns the singleton configuration instance.
  def self.config
    # Ensure configuration exists, initializing if necessary
    @configuration ||= ADK::Configuration.new # Configuration class is now loaded
  end

  # Accessors for Redis config
  def self.redis_url=(url)
    @redis_options[:url] = url
    configure_sidekiq # Reconfigure on change
  end

  def self.redis_options
    @redis_options
  end

  # --- Sidekiq Configuration ---
  def self.configure_sidekiq
    # Ensure logger is available before trying to use it
    current_logger = ADK.logger
    Sidekiq.configure_client do |config|
      config.redis = @redis_options.dup
      current_logger&.info("Sidekiq client configured with Redis: #{@redis_options[:url]}")
    end
  rescue Redis::CannotConnectError => e
    current_logger&.error("Sidekiq failed to configure Redis client: #{e.message}")
  rescue => e # Catch potential NoMethodError if logger is somehow still nil
    puts "[WARN] Error configuring Sidekiq, logger might not be available: #{e.message}"
  end

  # --- NEW: Register Core Webhook Validators --- #
  config.webhooks.register_validator(:hmac_sha256) do |request, secret|
    return false unless secret

    signature_header = request.env['HTTP_X_HUB_SIGNATURE_256']
    return false unless signature_header&.start_with?('sha256=')

    expected_signature = signature_header.delete_prefix('sha256=')
    request.body.rewind
    payload_body = request.body.read
    request.body.rewind
    calculated_signature = OpenSSL::HMAC.hexdigest('sha256', secret, payload_body)
    calculated_signature.bytesize == expected_signature.bytesize && OpenSSL.fixed_length_secure_compare(
      calculated_signature, expected_signature
    )
  end
  # --- END NEW --- #

  # Reset configuration (mainly for testing)
  def self.reset_config!
  end
end

# --- Initial Sidekiq Configuration Call (Logger is now guaranteed) ---
ADK.configure_sidekiq

# --- Require rest of components ---
require_relative 'adk/errors'
require_relative 'adk/event'
require_relative 'adk/session'
require_relative 'adk/tool_context'
require_relative 'adk/callbacks/callback_context' # Add callbacks module
require_relative 'adk/tool' # Logger is definitely ready now
require_relative 'adk/tool_registry'
require_relative 'adk/global_tool_manager'
require_relative 'adk/planner'
require_relative 'adk/session_service/base'
require_relative 'adk/session_service/in_memory'
require_relative 'adk/session_service/redis'
require_relative 'adk/mcp'
require_relative 'adk/agent'
require_relative 'adk/agents' # Load specialized workflow agents
require_relative 'adk/cli'

# Tools
require_relative 'adk/tools/echo'
require_relative 'adk/tools/calculator'
require_relative 'adk/tools/cat_facts'
require_relative 'adk/tools/random_number_tool'
require_relative 'adk/tools/agent_tool' # Tool that allows an agent to call another agent
require_relative 'adk/tools/base_async_job_tool' # Base class for tools that run asynchronously
require_relative 'adk/tools/check_job_status_tool' # Tool to check the status of async jobs
require_relative 'adk/tools/sleepy_tool' # Example async tool
require_relative 'adk/tools/webhook_tool' # Added webhook_tool here

# <<< ADDED: Require the webhook worker >>>
require_relative 'adk/webhook_job_worker'

# <<< ADDED BACK: Ensure example agent definition is loaded for worker/web >>>
# Using corrected relative path
begin
  require_relative '../examples/webhook_receiver_agent'
rescue LoadError => e
  # Log the error with more detail, including the path attempted
  ADK.logger.warn("Could not load example agent '../examples/webhook_receiver_agent.rb': #{e.message}. This might be expected.")
end

module ADK
  # Reopen module if needed for final definitions
  # class Error < StandardError; end # Already defined
  module SessionService; end
end

ADK.logger.info 'Explicitly registering built-in ADK tools...'
[
  ADK::Tools::Echo,
  ADK::Tools::Calculator,
  ADK::Tools::CatFacts,
  ADK::Tools::RandomNumberTool,
  ADK::Tools::AgentTool, # Ensure this is registered
  ADK::Tools::CheckJobStatusTool,
  ADK::Tools::SleepyTool,
  ADK::Tools::WebhookTool
  # ADK::Tools::BaseAsyncJobTool should NOT be registered as it's abstract
].each do |tool_klass|
  unless tool_klass.respond_to?(:abstract?) && tool_klass.abstract?
    ADK::GlobalToolManager.register_tool(tool_klass)
  else
    ADK.logger.debug "Skipping explicit registration of abstract tool: #{tool_klass}"
  end
end
ADK.logger.info "Explicit tool registration complete. Current global tools: #{ADK::GlobalToolManager.registered_tool_names.inspect}"
