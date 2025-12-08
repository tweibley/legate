# examples/mas/delegation_example.rb
require_relative '../../lib/adk'

# 1. Define a Specialist
ADK::Agent.define do |agent|
  agent.name :math_expert
  agent.instruction "You are a math expert. Solve math problems."
  agent.use_tool :calculator
end

# 2. Define a Manager who delegates
ADK::Agent.define do |agent|
  agent.name :project_manager
  agent.instruction "You manage the project. If you see a math problem, delegate it to the math expert."
  
  # Allow delegation
  agent.can_delegate_to :math_expert
end

puts "Defined Delegation System: :project_manager can delegate to :math_expert"