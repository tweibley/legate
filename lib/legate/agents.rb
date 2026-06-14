# frozen_string_literal: true

# File: lib/legate/agents.rb
# This manifest file loads all agent implementations for workflow agents

require_relative 'agents/sequential_agent'
require_relative 'agents/parallel_agent'
require_relative 'agents/loop_agent'

module Legate
  module Agents
    # This module contains specialized agent implementations for workflow composition
  end
end
