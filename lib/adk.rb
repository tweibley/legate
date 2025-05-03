# File: lib/adk.rb
require 'dotenv/load' if File.exist?('.env') # Load early for ENV vars

# frozen_string_literal: true
require 'logger'
require 'sidekiq'
require_relative 'adk/version'
require_relative 'adk/configuration' # Require Configuration class early

# --- Central ADK Module --- 
module ADK
  # --- Eager Logger Initialization ---
  @logger = begin
    default_level = ENV['RACK_ENV'] == 'development' ? 'DEBUG' : 'WARN'
    level_str = ENV['ADK_LOG_LEVEL']&.upcase || default_level
    log_target = $stdout
    if ['NONE', 'SILENT'].include?(level_str)
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
    unless ['NONE', 'SILENT'].include?(level_str)
      # Use puts here as logger might not be fully ready for complex formatting?
      puts "--> ADK Logger initialized with level: #{level_str}, target: #{log_target == IO::NULL ? 'NULL' : 'STDOUT'}"
    end
    logger_instance
  end
  # --- End Eager Logger Initialization ---
  
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

  # Access the eagerly initialized logger
  def self.logger
    @logger
  end

  # Configure ADK settings
  def self.configure
    # Initialize configuration only once
    @configuration ||= ADK::Configuration.new
    yield @configuration # Yield the instance
    # Reconfigure Sidekiq if Redis settings change after yield
    configure_sidekiq
  end

  # Returns the singleton configuration instance.
  # Ensures configuration is initialized if not already done.
  # @return [ADK::Configuration]
  def self.config
    # Ensure configuration exists, initializing if necessary
    @configuration ||= ADK::Configuration.new
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
    Sidekiq.configure_client do |config|
      config.redis = @redis_options.dup # Use a dup to avoid modification issues
      logger.info("Sidekiq client configured with Redis: #{@redis_options[:url]}")
    end
    # Optional: Configure server as well, though ADK itself doesn't run the server.
    # Sidekiq.configure_server do |config|
    #   config.redis = @redis_options.dup
    #   logger.info("Sidekiq server configured with Redis: #{@redis_options[:url]}")
    # end
  rescue Redis::CannotConnectError => e
    logger.error("Sidekiq failed to configure Redis client: #{e.message}")
    # Decide whether to raise or just log. Logging might be safer for library use.
  end
  # --- End Sidekiq Configuration ---
end

# --- Initial Sidekiq Configuration Call (Depends on Logger being ready) ---
ADK.configure_sidekiq

# --- Require components AFTER core module setup (Logger, Config, etc.) ---
require_relative 'adk/errors'
require_relative 'adk/event'
require_relative 'adk/session'
require_relative 'adk/tool_context' 
require_relative 'adk/tool' # Now logger is ready before this require
require_relative 'adk/tool_registry'
require_relative 'adk/global_tool_manager'
require_relative 'adk/planner'
require_relative 'adk/session_service/base'
require_relative 'adk/session_service/in_memory'
require_relative 'adk/session_service/redis'
require_relative 'adk/mcp'
require_relative 'adk/agent'
require_relative 'adk/cli'

# Tools (Can now safely inherit and use ADK.logger)
require_relative 'adk/tools/base/http_client'
require_relative 'adk/tools/webhook_tool'
require_relative 'adk/tools/agent_tool'
require_relative 'adk/tools/echo'
require_relative 'adk/tools/calculator'
require_relative 'adk/tools/cat_facts'
require_relative 'adk/tools/random_number_tool'
require_relative 'adk/tools/base_async_job_tool'
require_relative 'adk/tools/check_job_status_tool'
require_relative 'adk/tools/sleepy_tool'

module ADK
  class Error < StandardError; end
  # Define SessionService module base for namespacing
  module SessionService; end
end
