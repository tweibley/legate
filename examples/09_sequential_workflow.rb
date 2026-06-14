# examples/09_sequential_workflow.rb
require_relative '../lib/legate'

# Load .env and map GEMINI_API_KEY -> GOOGLE_API_KEY (as the `legate` CLI does).
# The library never reads .env on its own; an application must opt in.
Legate.load_environment

# 1. Define Worker Agents
Legate::Agent.define do |agent|
  agent.name :data_gatherer
  agent.instruction 'Gather data about the topic.'
  agent.use_tool :echo # Simulation
  agent.output_key :gathered_data
end

Legate::Agent.define do |agent|
  agent.name :data_processor
  agent.instruction 'Process the gathered data.'
  agent.use_tool :echo # Simulation
  agent.output_key :processed_data
end

Legate::Agent.define do |agent|
  agent.name :report_writer
  agent.instruction 'Write a report based on processed data.'
  agent.use_tool :echo # Simulation
end

# 2. Define Sequential Workflow
Legate::Agent.define do |agent|
  agent.name :report_pipeline
  agent.agent_type :sequential
  agent.description 'A pipeline to gather, process, and write reports.'
  agent.instruction 'Execute the pipeline.'

  # Order matters!
  agent.sequential_sub_agents :data_gatherer, :data_processor, :report_writer
end

puts 'Defined Sequential Workflow: :report_pipeline'
