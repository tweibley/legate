# File: lib/adk.rb
require 'dotenv/load' if File.exist?('.env') # Load early for ENV vars

# frozen_string_literal: true
require 'logger' # Require logger here
require_relative 'adk/version'

# --- Central ADK Logger Configuration ---
module ADK
  @logger = nil
  # ... (self.logger method remains the same) ...
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
end

# --- Require components AFTER logger is configurable ---
require_relative 'adk/event' # <<< Require Event first
require_relative 'adk/session' # <<< Session depends on Event
require_relative 'adk/tool'
require_relative 'adk/tool_registry'
# --- Load dependencies BEFORE Agent ---
require_relative 'adk/planner'
# --- Load Services ---
require_relative 'adk/session_service/in_memory'
require_relative 'adk/session_service/redis'
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

module ADK
  class Error < StandardError; end
  # Define SessionService module base for namespacing
  module SessionService; end
end
