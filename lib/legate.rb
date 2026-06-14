# frozen_string_literal: true

# File: lib/legate.rb
# NOTE: Loading .env is the application's job, not the library's. The `legate`
# executable does it via Legate.load_environment; requiring 'legate' must not
# read the consumer's working directory (and dotenv is only a dev dependency).
require 'logger'
require_relative 'legate/version'
require 'forwardable'
require 'openssl' # For HMAC in validator

# --- Eager Logger Initialization (Moved BEFORE other Legate requires) ---
module Legate
  # --- Logger Initialization Logic ---
  # Log levels that suppress all output
  SILENT_LOG_LEVELS = %w[NONE SILENT].freeze

  def self.initialize_logger
    level_str = determine_log_level_str
    log_target, level = configure_log_settings(level_str)

    logger_instance = Logger.new(log_target)
    logger_instance.level = level
    logger_instance.formatter = proc { |severity, _, _, msg| "#{severity}: #{msg}\n" }

    logger_instance
  end

  # Private helper methods for logger initialization
  class << self
    private

    def determine_log_level_str
      default_level = ENV['RACK_ENV'] == 'development' ? 'DEBUG' : 'WARN'
      ENV['LEGATE_LOG_LEVEL']&.upcase || default_level
    end

    def configure_log_settings(level_str)
      if SILENT_LOG_LEVELS.include?(level_str)
        [IO::NULL, Logger::FATAL + 1]
      else
        [$stdout, parse_log_level(level_str)]
      end
    end

    def parse_log_level(level_str)
      case level_str
      when 'DEBUG' then Logger::DEBUG
      when 'INFO' then Logger::INFO
      when 'WARN' then Logger::WARN
      when 'ERROR' then Logger::ERROR
      when 'FATAL' then Logger::FATAL
      else Logger::WARN
      end
    end
  end

  @logger = initialize_logger

  # --- Define Logger Accessor Method EARLY ---
  def self.logger
    @logger
  end
end
# --- End Eager Logger Initialization & Accessor ---

# --- NOW Require Configuration (Depends on Logger for its own initialization maybe?) ---
require_relative 'legate/configuration'

# --- Central Legate Module (Reopened) ---
module Legate
  @configuration = nil
  # Guards lazy construction of the singleton configuration so concurrent
  # first-callers (and reset_config! in tests) can't each build one.
  @config_mutex = Mutex.new

  def self.load_environment
    begin
      require 'bundler/setup'
      # Compatibility shim for Bundler 4.0+ and older gems (like Puma 6.x)
      if defined?(Bundler) && !Bundler.const_defined?(:ORIGINAL_ENV)
        env = if Bundler.respond_to?(:original_env)
                Bundler.original_env
              elsif Bundler.respond_to?(:with_original_env)
                Bundler.with_original_env { ENV.to_h }
              else
                ENV.to_h
              end
        Bundler.const_set(:ORIGINAL_ENV, env)
      end
    rescue LoadError
      # Ignore if Bundler is not used or gem not found
    end

    begin
      # Load .env here (the application's entry point), not at library require
      # time. dotenv is a dev-only dependency, so guard against it being absent.
      require 'dotenv/load'
    rescue LoadError
      # Ignore if dotenv gem is not used or .env doesn't exist
    end

    # Accept GEMINI_API_KEY as an alias for GOOGLE_API_KEY (the variable the
    # gemini-ai gem reads). Users naturally reach for "Gemini API key", and the
    # README documents GEMINI_API_KEY — map it here so the CLI and library paths
    # behave like config.ru's deployment entrypoint.
    ENV['GOOGLE_API_KEY'] ||= ENV['GEMINI_API_KEY'] if ENV['GEMINI_API_KEY']
  end

  # Configure Legate settings
  def self.configure
    config # Ensure the singleton exists (under the mutex)
    yield @configuration # Yield the instance
  end

  # Returns the singleton configuration instance.
  def self.config
    @config_mutex.synchronize { @configuration ||= Legate::Configuration.new }
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
    @config_mutex.synchronize { @configuration = nil }
  end
end

# --- Require rest of components ---
require_relative 'legate/errors'
require_relative 'legate/event'
require_relative 'legate/session'
require_relative 'legate/tool_context'
require_relative 'legate/callbacks/callback_context' # Add callbacks module
require_relative 'legate/tool_result'
require_relative 'legate/tool' # Logger is definitely ready now
require_relative 'legate/tool_registry'
require_relative 'legate/global_tool_manager'
require_relative 'legate/tool_loader'
require_relative 'legate/llm'
require_relative 'legate/agentic'
require_relative 'legate/planner'
require_relative 'legate/session_service/base'
require_relative 'legate/session_service/in_memory'
require_relative 'legate/mcp'
require_relative 'legate/plan_executor'
require_relative 'legate/agent'
require_relative 'legate/agents' # Load specialized workflow agents
# NOTE: the CLI (require 'legate/cli') and web UI (require 'legate/web') are
# opt-in — they are NOT loaded here, so `require 'legate'` does not drag in Thor,
# Sinatra, Puma, Slim, or sass-embedded for library-only consumers. The `legate`
# executable loads the CLI explicitly; web hosts load 'legate/web'.

# Tools
require_relative 'legate/tools/echo'
require_relative 'legate/tools/calculator'
require_relative 'legate/tools/cat_facts'
# RandomNumberTool is loaded so examples/tests can opt into it, but it is NOT
# registered as a default tool (see the registration list below) — it's a demo
# tool, not something an agent should be offered out of the box.
require_relative 'legate/tools/random_number_tool'
require_relative 'legate/tools/agent_tool' # Tool that allows an agent to call another agent
require_relative 'legate/tools/base_async_job_tool' # Base class for tools that run asynchronously
require_relative 'legate/tools/check_job_status_tool' # Tool to check the status of async jobs
require_relative 'legate/tools/sleepy_tool' # Example async tool
require_relative 'legate/tools/webhook_tool' # Added webhook_tool here
require_relative 'legate/tools/http_request_tool' # General-purpose SSRF-safe HTTP client
require_relative 'legate/tools/current_time_tool' # Current date/time
require_relative 'legate/tools/read_webpage_tool' # Fetch a page as readable text

module Legate
  # Reopen module if needed for final definitions
  # class Error < StandardError; end # Already defined
  module SessionService; end

  # Lists metadata (name, description, parameters) for every globally registered
  # tool — a discoverable entry point over GlobalToolManager.
  # @return [Array<Hash>]
  def self.tools
    Legate::GlobalToolManager.list_all_tools
  end
end

Legate.logger.debug 'Explicitly registering built-in Legate tools...'
[
  Legate::Tools::Echo,
  Legate::Tools::Calculator,
  Legate::Tools::CatFacts,
  Legate::Tools::AgentTool, # Ensure this is registered
  Legate::Tools::CheckJobStatusTool,
  Legate::Tools::SleepyTool,
  Legate::Tools::WebhookTool,
  Legate::Tools::HttpRequest,
  Legate::Tools::CurrentTime,
  Legate::Tools::ReadWebpage
  # Legate::Tools::BaseAsyncJobTool should NOT be registered as it's abstract
].each do |tool_klass|
  if tool_klass.respond_to?(:abstract?) && tool_klass.abstract?
    Legate.logger.debug "Skipping explicit registration of abstract tool: #{tool_klass}"
  else
    Legate::GlobalToolManager.register_tool(tool_klass)
  end
end
Legate.logger.debug "Explicit tool registration complete. Current global tools: #{Legate::GlobalToolManager.registered_tool_names.inspect}"
