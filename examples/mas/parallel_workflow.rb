# examples/mas/parallel_workflow.rb
require_relative '../../lib/adk'

# 1. Define Specialized Analysts
ADK::Agent.define do |agent|
  agent.name :market_analyst
  agent.instruction "Analyze market trends."
  agent.use_tool :echo
  agent.output_key :market_analysis
end

ADK::Agent.define do |agent|
  agent.name :tech_analyst
  agent.instruction "Analyze technology trends."
  agent.use_tool :echo
  agent.output_key :tech_analysis
end

# 2. Define Parallel Workflow
ADK::Agent.define do |agent|
  agent.name :comprehensive_analysis
  agent.agent_type :parallel
  agent.description "Run analyses concurrently."
  agent.instruction "Analyze the sector."
  
  # Will run at the same time
  agent.parallel_sub_agents :market_analyst, :tech_analyst
end

puts "Defined Parallel Workflow: :comprehensive_analysis"
