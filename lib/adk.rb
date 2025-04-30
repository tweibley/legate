# File: lib/adk.rb
require 'dotenv/load' if File.exist?('.env') # Load early for ENV vars

# frozen_string_literal: true
require 'logger'
require 'sidekiq'
require_relative 'adk/version'

# --- Central ADK Logger Configuration ---
module ADK
  @logger = nil

  # Default Redis connection options (used by SessionService and Sidekiq)
  @redis_options = {
    url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
    # Add other Redis options if needed (password, etc.)
  }

  # Simplifies common environment setup like Bundler and Dotenv.
  # Call this at the beginning of your application entry point.
  # It attempts to load 'bundler/setup' and 'dotenv/load', ignoring
  # LoadError if they are not available or needed in the current context.
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

  def self.logger
    @logger ||= begin
      # Default to DEBUG in development, WARN otherwise
      default_level = ENV['RACK_ENV'] == 'development' ? 'DEBUG' : 'WARN'
      level_str = ENV['ADK_LOG_LEVEL']&.upcase || default_level
      log_target = $stdout # Default target
      # Check for silent flag *before* setting level
      if ['NONE', 'SILENT'].include?(level_str)
        log_target = IO::NULL # Use the null device constant (more portable than '/dev/null')
        level = Logger::FATAL + 1 # Still set level high for consistency
      else

        level = case level_str
                when 'DEBUG' then Logger::DEBUG
                when 'INFO' then Logger::INFO
                when 'WARN' then Logger::WARN
                when 'ERROR' then Logger::ERROR
                when 'FATAL' then Logger::FATAL
                else Logger::WARN # Default fallback
                end
      end
      logger_instance = Logger.new(log_target) # Log to target (stdout or NULL)
      logger_instance.level = level
      logger_instance.formatter = proc { |severity, _, _, msg| "#{severity}: #{msg}\n" }
      unless ['NONE', 'SILENT'].include?(level_str)
        puts "--> ADK Logger initialized with level: #{level_str}, target: #{log_target == IO::NULL ? 'NULL' : 'STDOUT'}"
      end

      logger_instance
    end
  end

  # Configure ADK settings
  def self.configure
    yield self
    # Reconfigure Sidekiq if Redis settings change
    configure_sidekiq
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

# --- Initial Sidekiq Configuration Call ---
ADK.configure_sidekiq

# --- Require components AFTER logger is configurable ---
require_relative 'adk/errors'
require_relative 'adk/event'
require_relative 'adk/session'
require_relative 'adk/tool_context'
require_relative 'adk/tool'
require_relative 'adk/tool_registry'
# --- Load dependencies BEFORE Agent ---
require_relative 'adk/planner'
# --- Load Services ---
require_relative 'adk/session_service/base'
require_relative 'adk/session_service/in_memory'
require_relative 'adk/session_service/redis'
# --- Load Migrations ---
require_relative 'adk/migrations/001_add_state_scoping'

require_relative 'adk/mcp'
# --- Now load Agent ---
require_relative 'adk/agent'
# --- Load CLI and Tools last ---
require_relative 'adk/cli'

# Tools (Order doesn't strictly matter here, but keep AgentTool first if it uses others)
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
