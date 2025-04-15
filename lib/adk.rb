require 'dotenv/load'

# frozen_string_literal: true

require_relative 'adk/version'

# Ensure the Tool base class and registry are loaded first
require_relative 'adk/tool'
require_relative 'adk/tool_registry' # Added registry require

# Core components
require_relative 'adk/agent'
require_relative 'adk/tool'
require_relative 'adk/session'
require_relative 'adk/memory'
require_relative 'adk/planner'

# CLI components
require_relative 'adk/cli'
require_relative 'adk/cli/agent_commands'
require_relative 'adk/cli/tool_commands'

# Tools
require_relative 'adk/tools/echo'
require_relative 'adk/tools/calculator'
# Additional components will be added as they are implemented
# require_relative 'adk/events'
# require_relative 'adk/telemetry'
# require_relative 'adk/evaluation'
# require_relative 'adk/flows'
# require_relative 'adk/code_executors'
# require_relative 'adk/auth'

module ADK
  class Error < StandardError; end

  # Your code goes here...
end
