# examples/advanced/mas/loop_workflow.rb
require_relative '../../../lib/legate'

# 1. Define Worker
Legate::Agent.define do |agent|
  agent.name :improver
  agent.instruction 'Improve the text quality.'
  agent.use_tool :echo
  # Logic to check quality would be here, setting :quality_met state
end

# 2. Define Loop Workflow
Legate::Agent.define do |agent|
  agent.name :quality_control_loop
  agent.agent_type :loop
  agent.description 'Improve text until quality standard is met.'
  agent.instruction 'Refine content.'

  agent.loop_sub_agents :improver

  # Stop when 'quality_met' is true in session state
  agent.loop_condition :quality_met, true

  # Safety valve: max 5 loops
  agent.loop_max_iterations 5
end

puts 'Defined Loop Workflow: :quality_control_loop'
