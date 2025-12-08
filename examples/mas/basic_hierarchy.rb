# examples/mas/basic_hierarchy.rb
require_relative '../../lib/adk'

# 1. Define Sub-Agents
ADK::Agent.define do |agent|
  agent.name :child_agent_1
  agent.description "A simple child agent."
  agent.instruction "You are child agent 1. Say hello."
  agent.use_tool :echo
end

ADK::Agent.define do |agent|
  agent.name :child_agent_2
  agent.description "Another simple child agent."
  agent.instruction "You are child agent 2. Say goodbye."
  agent.use_tool :echo
end

# 2. Define Parent Agent
parent = ADK::Agent.define do |agent|
  agent.name :parent_agent
  agent.description "A parent managing children."
  agent.instruction "Manage your children."
  
  # Define sub-agents
  agent.sub_agents_define :child_agent_1, :child_agent_2
end

# 3. Instantiate and Explore
# Note: Creating an instance usually requires a definition store and session service configuration
# For demonstration, we assume defaults are set or we use definition object directly if supported.

# In a real app, you would load this definition.
puts "Parent Agent: #{parent.name}"
puts "Sub-Agents defined: #{parent.sub_agent_names.to_a}"

# To actually instantiate hierarchy, we'd need a running setup with GlobalDefinitionRegistry populated.
# This example primarily demonstrates the DEFINITION syntax.
