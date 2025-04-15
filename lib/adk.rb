# File: lib/adk.rb
require 'dotenv/load' if File.exist?('.env') # Load early for ENV vars

# frozen_string_literal: true
require 'logger' # Require logger here
require_relative 'adk/version'

# --- Central ADK Logger Configuration ---
module ADK
  @logger = nil

  def self.logger
    @logger ||= begin
      level_str = ENV['ADK_LOG_LEVEL']&.upcase || 'WARN' # Default to WARN
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
end

# --- Require components AFTER logger is configurable ---
require_relative 'adk/tool'
require_relative 'adk/tool_registry'
require_relative 'adk/agent'
require_relative 'adk/session'
require_relative 'adk/memory'
require_relative 'adk/planner'
require_relative 'adk/cli'

# Tools
require_relative 'adk/tools/echo'
require_relative 'adk/tools/calculator'
require_relative 'adk/tools/cat_facts'

module ADK
  class Error < StandardError; end

  # Your code goes here...
end
