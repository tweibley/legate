# examples/11_agent_delegation.rb
require_relative '../lib/legate'

# Load .env and map GEMINI_API_KEY -> GOOGLE_API_KEY (as the `legate` CLI does).
# The library never reads .env on its own; an application must opt in.
Legate.load_environment

# 1. Define a Specialist
Legate::Agent.define do |agent|
  agent.name :math_expert
  agent.instruction 'You are a math expert. Solve math problems.'
  agent.use_tool :calculator
end

# 2. Define a Manager who delegates
Legate::Agent.define do |agent|
  agent.name :project_manager
  agent.instruction 'You manage the project. If you see a math problem, delegate it to the math expert.'

  # Allow delegation
  agent.can_delegate_to :math_expert
end

puts 'Defined Delegation System: :project_manager can delegate to :math_expert'
