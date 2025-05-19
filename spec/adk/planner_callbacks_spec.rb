# frozen_string_literal: true

require 'spec_helper'
require 'adk/planner'
require 'adk/agent'
require 'adk/callbacks/callback_context'

RSpec.describe "Planner Callbacks" do
  let(:invocation_id) { SecureRandom.uuid }
  let(:before_model_callback) { nil }
  let(:after_model_callback) { nil }
  
  # Create a minimal agent with callbacks
  let(:agent) do
    agent_def = double('AgentDefinition',
      name: :test_agent,
      description: 'Test agent',
      instruction: 'Test instruction',
      tool_names: []
    )
    
    # Make the agent definition respond to required methods
    allow(agent_def).to receive(:respond_to?).and_return(true)
    allow(agent_def).to receive(:before_model_callback).and_return(before_model_callback)
    allow(agent_def).to receive(:after_model_callback).and_return(after_model_callback)
    allow(agent_def).to receive(:delegation_targets).and_return([])
    allow(agent_def).to receive(:sequential_sub_agent_names).and_return([])
    
    agent = double('Agent',
      name: :test_agent,
      definition: agent_def,
      available_tools_metadata: []
    )
    
    # Make the agent respond to required methods
    allow(agent).to receive(:respond_to?).and_return(true)
    allow(agent).to receive(:before_model_callback).and_return(before_model_callback)
    allow(agent).to receive(:after_model_callback).and_return(after_model_callback)
    allow(agent).to receive(:instruction).and_return("Test instruction")
    
    agent
  end
  
  let(:planner) do
    planner = ADK::Planner.new(agent: agent)
    
    # Replace the client with a stub
    client = double('GeminiClient')
    allow(client).to receive(:generate_content).and_return({
      'candidates' => [
        { 'content' => { 'parts' => [{ 'text' => '{"thought_process": "test", "plan": []}' }] } }
      ]
    })
    planner.instance_variable_set(:@client, client)
    
    planner
  end
  
  describe "before_model_callback" do
    let(:before_model_called) { false }
    let(:before_model_callback) do
      proc do |prompt, ctx|
        expect(prompt).to include("User Request")
        expect(ctx).to be_a(ADK::Callbacks::CallbackContext)
        expect(ctx.invocation_id).to eq(invocation_id)
        
        self.before_model_called = true
        "Modified prompt: #{prompt}"
      end
    end
    
    # Create a method to update the variable outside the proc
    def before_model_called=(value)
      @before_model_called = value
    end
    
    def before_model_called
      @before_model_called
    end
    
    it "modifies the prompt before sending to model" do
      # Mock the client to verify it receives the modified prompt
      expect(planner.instance_variable_get(:@client)).to receive(:generate_content) do |args|
        prompt_text = args[:contents][0][:parts][:text]
        expect(prompt_text).to include("Modified prompt:")
        {
          'candidates' => [
            { 'content' => { 'parts' => [{ 'text' => '{"thought_process": "test", "plan": []}' }] } }
          ]
        }
      end
      
      planner.plan("test input", invocation_id)
      
      expect(before_model_called).to be true
    end
  end
  
  describe "after_model_callback" do
    let(:after_model_called) { false }
    let(:after_model_callback) do
      proc do |response, ctx|
        expect(response).to include("thought_process")
        expect(ctx).to be_a(ADK::Callbacks::CallbackContext)
        expect(ctx.invocation_id).to eq(invocation_id)
        
        self.after_model_called = true
        # Return a valid JSON that will properly parse through validate_and_format_multi_step_plan
        <<~JSON
        {
          "thought_process": "Modified by callback",
          "plan": [
            {
              "step": 1,
              "type": "tool_use",
              "tool_name": "echo",
              "tool_input": {"message": "Modified response"},
              "reason": "Testing callback"
            }
          ]
        }
        JSON
      end
    end
    
    # Create a method to update the variable outside the proc
    def after_model_called=(value)
      @after_model_called = value
    end
    
    def after_model_called
      @after_model_called
    end
    
    it "modifies the model response" do
      # Set up a proper stub client for this test
      client = double('GeminiClient')
      allow(client).to receive(:generate_content).and_return({
        'candidates' => [
          { 'content' => { 'parts' => [{ 'text' => '{"thought_process": "original", "plan": []}' }] } }
        ]
      })
      planner.instance_variable_set(:@client, client)
      
      result = planner.plan("test input", invocation_id)
      
      expect(after_model_called).to be true
      expect(result[:thought_process]).to eq("Modified by callback")
    end
  end
end 