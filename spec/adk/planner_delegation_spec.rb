# frozen_string_literal: true

require 'spec_helper'
require 'adk/planner'
require 'adk/agent'
require 'adk/global_tool_manager'

RSpec.describe ADK::Planner do
  let(:logger_double) { spy('Logger') }
  
  before do
    allow(ADK).to receive(:logger).and_return(logger_double)
  end
  
  describe '#format_delegation_targets' do
    it 'returns an empty string when agent has no delegation targets' do
      # Create agent with no delegation targets
      definition = ADK::AgentDefinition.new.define do |a|
        a.name :test_agent
        a.description 'Test agent'
        a.instruction 'Test instruction'
      end
      
      agent = instance_double(ADK::Agent, 
                             definition: definition,
                             available_tools_metadata: [])
      
      planner = ADK::Planner.new(agent: agent)
      expect(planner.send(:format_delegation_targets)).to eq('')
    end
    
    it 'formats delegation targets as special tools' do
      # Create agent with delegation targets
      definition = ADK::AgentDefinition.new.define do |a|
        a.name :test_agent
        a.description 'Test agent'
        a.instruction 'Test instruction'
        a.can_delegate_to :target_agent
      end
      
      # Mock the GlobalDefinitionRegistry behavior
      target_def = ADK::AgentDefinition.new.define do |a|
        a.name :target_agent
        a.description 'Target agent for delegation'
        a.instruction 'You are a target agent'
      end
      
      allow(ADK::GlobalDefinitionRegistry).to receive(:get).with(:target_agent).and_return(target_def)
      
      agent = instance_double(ADK::Agent, 
                             definition: definition,
                             available_tools_metadata: [])
      
      planner = ADK::Planner.new(agent: agent)
      result = planner.send(:format_delegation_targets)
      
      # Verify the format contains the expected tool description
      expect(result).to include('Tool Name: agent_transfer_to_target_agent')
      expect(result).to include('Target agent for delegation')
      expect(result).to include('Parameters:')
      expect(result).to include('task (string, required)')
    end
  end
  
  describe '#build_multi_step_gemini_prompt' do
    it 'includes delegation instructions when delegation targets are available' do
      definition = ADK::AgentDefinition.new.define do |a|
        a.name :test_agent
        a.description 'Test agent'
        a.instruction 'Test instruction'
        a.can_delegate_to :target_agent
      end
      
      agent = instance_double(ADK::Agent, 
                             definition: definition,
                             instruction: 'Test instruction',
                             available_tools_metadata: [])
      
      allow_any_instance_of(ADK::Planner).to receive(:format_delegation_targets).and_return('Tool Name: agent_transfer_to_target_agent')
      
      planner = ADK::Planner.new(agent: agent)
      result = planner.send(:build_multi_step_gemini_prompt, 'Test task', 'Tool descriptions')
      
      # Verify the prompt includes delegation instructions
      expect(result).to include('Important: You can delegate tasks to other specialized agents')
      expect(result).to include('Look for tools with names starting with "agent_transfer_to_"')
    end
    
    it 'does not include delegation instructions when no delegation targets exist' do
      definition = ADK::AgentDefinition.new.define do |a|
        a.name :test_agent
        a.description 'Test agent'
        a.instruction 'Test instruction'
      end
      
      agent = instance_double(ADK::Agent, 
                             definition: definition,
                             instruction: 'Test instruction',
                             available_tools_metadata: [])
      
      planner = ADK::Planner.new(agent: agent)
      result = planner.send(:build_multi_step_gemini_prompt, 'Test task', 'Tool descriptions')
      
      # Verify the prompt does not include delegation instructions
      expect(result).not_to include('Important: You can delegate tasks to other specialized agents')
      expect(result).not_to include('Look for tools with names starting with "agent_transfer_to_"')
    end
  end
  
  describe '#validate_and_format_multi_step_plan' do
    let(:agent_definition) do
      ADK::AgentDefinition.new.define do |a|
        a.name :test_agent
        a.description 'Test agent'
        a.instruction 'Test instruction'
        a.can_delegate_to :target_agent
      end
    end
    
    let(:agent) do
      agent = instance_double(ADK::Agent, 
                             definition: agent_definition,
                             available_tools_metadata: [
                               { name: :echo, description: 'Echo tool' }
                             ])
      agent
    end
    
    it 'converts agent_transfer_to_X tools to delegate_task steps' do
      planner = ADK::Planner.new(agent: agent)
      
      parsed_response = [
        {
          'tool_name' => 'agent_transfer_to_target_agent',
          'parameters' => {
            'task' => 'Do something important'
          }
        }
      ]
      
      result = planner.send(:validate_and_format_multi_step_plan, parsed_response)
      
      # Expected conversion to delegate_task
      expect(result.size).to eq(1)
      expect(result[0][:tool]).to eq(:delegate_task)
      expect(result[0][:params][:agent_name]).to eq(:target_agent)
      expect(result[0][:params][:task]).to eq('Do something important')
      expect(result[0][:step_type]).to eq(:agent_transfer)
    end
    
    it 'keeps regular tools as-is' do
      planner = ADK::Planner.new(agent: agent)
      
      parsed_response = [
        {
          'tool_name' => 'echo',
          'parameters' => {
            'message' => 'Hello world'
          }
        }
      ]
      
      result = planner.send(:validate_and_format_multi_step_plan, parsed_response)
      
      # Regular tool stays as-is
      expect(result.size).to eq(1)
      expect(result[0][:tool]).to eq(:echo)
      expect(result[0][:params][:message]).to eq('Hello world')
      expect(result[0][:step_type]).to be_nil
    end
    
    it 'handles a mix of regular tools and delegation steps' do
      planner = ADK::Planner.new(agent: agent)
      
      parsed_response = [
        {
          'tool_name' => 'echo',
          'parameters' => {
            'message' => 'Hello world'
          }
        },
        {
          'tool_name' => 'agent_transfer_to_target_agent',
          'parameters' => {
            'task' => 'Process the echo result'
          }
        }
      ]
      
      result = planner.send(:validate_and_format_multi_step_plan, parsed_response)
      
      # Check first step (regular tool)
      expect(result[0][:tool]).to eq(:echo)
      expect(result[0][:params][:message]).to eq('Hello world')
      
      # Check second step (delegation)
      expect(result[1][:tool]).to eq(:delegate_task)
      expect(result[1][:params][:agent_name]).to eq(:target_agent)
      expect(result[1][:params][:task]).to eq('Process the echo result')
      expect(result[1][:step_type]).to eq(:agent_transfer)
    end
  end
end 