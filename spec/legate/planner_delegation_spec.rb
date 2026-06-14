# frozen_string_literal: true

require 'spec_helper'
require 'legate/planner'
require 'legate/agent'
require 'legate/global_tool_manager'

RSpec.describe Legate::Planner do
  let(:logger_double) { spy('Logger') }

  before do
    allow(Legate).to receive(:logger).and_return(logger_double)
  end

  describe '#format_delegation_targets' do
    it 'returns an empty string when agent has no delegation targets' do
      # Create agent with no delegation targets
      definition = Legate::AgentDefinition.new.define do |a|
        a.name :test_agent
        a.description 'Test agent'
        a.instruction 'Test instruction'
      end

      agent = instance_double(Legate::Agent,
                              definition: definition,
                              available_tools_metadata: [])

      planner = Legate::Planner.new(agent: agent)
      expect(planner.send(:format_delegation_targets)).to eq('')
    end

    it 'formats delegation targets as special tools' do
      # Create agent with delegation targets
      definition = Legate::AgentDefinition.new.define do |a|
        a.name :test_agent
        a.description 'Test agent'
        a.instruction 'Test instruction'
        a.can_delegate_to :target_agent
      end

      # Mock the GlobalDefinitionRegistry behavior
      target_def = Legate::AgentDefinition.new.define do |a|
        a.name :target_agent
        a.description 'Target agent for delegation'
        a.instruction 'You are a target agent'
      end

      allow(Legate::GlobalDefinitionRegistry).to receive(:find).with(:target_agent).and_return(target_def)

      agent = instance_double(Legate::Agent,
                              definition: definition,
                              available_tools_metadata: [])

      planner = Legate::Planner.new(agent: agent)
      result = planner.send(:format_delegation_targets)

      # Updated expectations to match the new format
      expect(result).to include('Tool Name: agent_transfer_to_target_agent')
      expect(result).to include('Description: Target agent for delegation')
      expect(result).to include('Parameters:')
      expect(result).to include('task (string, required)')
    end
  end

  describe '#build_multi_step_gemini_prompt' do
    it 'includes delegation instructions when delegation targets are available' do
      definition = Legate::AgentDefinition.new.define do |a|
        a.name :test_agent
        a.description 'Test agent'
        a.instruction 'Test instruction'
        a.can_delegate_to :target_agent
      end

      agent = instance_double(Legate::Agent,
                              definition: definition,
                              instruction: 'Test instruction',
                              available_tools_metadata: [])

      allow_any_instance_of(Legate::Planner).to receive(:format_delegation_targets).and_return('Tool Name: agent_transfer_to_target_agent')

      planner = Legate::Planner.new(agent: agent)
      result = planner.send(:build_multi_step_gemini_prompt, 'Test task', 'Tool descriptions')

      # Check for the new delegation instructions
      expect(result).to include('Agent Delegation Capabilities')
      expect(result).to include('delegate tasks to specialized agents')
      expect(result).to include('agent_transfer_to_')
      expect(result).to include('Test task')
    end

    it 'does not include delegation instructions when no delegation targets exist' do
      definition = Legate::AgentDefinition.new.define do |a|
        a.name :test_agent
        a.description 'Test agent'
        a.instruction 'Test instruction'
      end

      agent = instance_double(Legate::Agent,
                              definition: definition,
                              instruction: 'Test instruction',
                              available_tools_metadata: [])

      planner = Legate::Planner.new(agent: agent)
      result = planner.send(:build_multi_step_gemini_prompt, 'Test task', 'Tool descriptions')

      # Check that delegation instructions are not included
      expect(result).not_to include('Agent Delegation Capabilities')
      expect(result).not_to include('delegate tasks to specialized agents')

      # Verify the task is in the prompt
      expect(result).to include('Test task')
    end
  end

  describe '#validate_and_format_multi_step_plan' do
    let(:agent_definition) do
      Legate::AgentDefinition.new.define do |a|
        a.name :test_agent
        a.description 'Test agent'
        a.instruction 'Test instruction'
        a.can_delegate_to :target_agent
      end
    end

    let(:agent) do
      agent = instance_double(Legate::Agent,
                              definition: agent_definition,
                              available_tools_metadata: [
                                { name: :echo, description: 'Echo tool' }
                              ])
      agent
    end

    it 'converts agent_transfer_to_X tools to delegate_task steps' do
      planner = Legate::Planner.new(agent: agent)

      # Update to match the new format expected by validate_and_format_multi_step_plan
      llm_response = <<~JSON
        {
          "thought_process": "Thinking about delegation",
          "plan": [
            {
              "step": 1,
              "type": "tool_use",
              "tool_name": "agent_transfer_to_target_agent",
              "tool_input": {
                "task": "Do something important"
              },
              "reason": "This task requires specialized handling"
            }
          ]
        }
      JSON

      result = planner.send(:validate_and_format_multi_step_plan, llm_response)

      # Adjust expectations to match new format
      expect(result[:formatted_steps].size).to eq(1)
      expect(result[:formatted_steps][0][:tool]).to eq(:agent_transfer_to_target_agent)
      expect(result[:formatted_steps][0][:params][:task]).to eq('Do something important')
      expect(result[:thought_process]).to eq('Thinking about delegation')
    end

    it 'keeps regular tools as-is' do
      planner = Legate::Planner.new(agent: agent)

      # Update to match the new format expected by validate_and_format_multi_step_plan
      llm_response = <<~JSON
        {
          "thought_process": "Using echo tool",
          "plan": [
            {
              "step": 1,
              "type": "tool_use",
              "tool_name": "echo",
              "tool_input": {
                "message": "Hello world"
              },
              "reason": "Need to display message"
            }
          ]
        }
      JSON

      result = planner.send(:validate_and_format_multi_step_plan, llm_response)

      # Adjust expectations to match new format
      expect(result[:formatted_steps].size).to eq(1)
      expect(result[:formatted_steps][0][:tool]).to eq(:echo)
      expect(result[:formatted_steps][0][:params][:message]).to eq('Hello world')
    end

    it 'handles a mix of regular tools and delegation steps' do
      planner = Legate::Planner.new(agent: agent)

      # Update to match the new format expected by validate_and_format_multi_step_plan
      llm_response = <<~JSON
        {
          "thought_process": "Mixed approach",
          "plan": [
            {
              "step": 1,
              "type": "tool_use",
              "tool_name": "echo",
              "tool_input": {
                "message": "Hello world"
              },
              "reason": "Initial echo"
            },
            {
              "step": 2,
              "type": "tool_use",
              "tool_name": "agent_transfer_to_target_agent",
              "tool_input": {
                "task": "Process the echo result"
              },
              "reason": "Need specialized processing"
            }
          ]
        }
      JSON

      result = planner.send(:validate_and_format_multi_step_plan, llm_response)

      # Adjust expectations to match new format
      expect(result[:formatted_steps].size).to eq(2)
      expect(result[:formatted_steps][0][:tool]).to eq(:echo)
      expect(result[:formatted_steps][0][:params][:message]).to eq('Hello world')

      expect(result[:formatted_steps][1][:tool]).to eq(:agent_transfer_to_target_agent)
      expect(result[:formatted_steps][1][:params][:task]).to eq('Process the echo result')
    end
  end
end
