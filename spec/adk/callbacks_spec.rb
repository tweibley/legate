# frozen_string_literal: true

require 'spec_helper'
require 'adk/agent'
require 'adk/callbacks/callback_context'
require 'adk/tool_context'
require 'adk/session_service/in_memory'
require 'adk/event'

RSpec.describe "ADK Callbacks" do
  let(:session_service) { ADK::SessionService::InMemory.new }
  let(:session_id) { "test-session-#{SecureRandom.uuid}" }
  let(:user_id) { "test-user-1" }
  let(:app_name) { "test-app" }
  let(:invocation_id) { SecureRandom.uuid }
  let(:agent_name) { :test_agent }

  before do
    # Create a session in the service
    session_service.create_session(
      user_id: user_id,
      app_name: app_name
    )
  end

  describe ADK::Callbacks::CallbackContext do
    subject(:context) do
      described_class.new(
        agent_name: agent_name,
        invocation_id: invocation_id,
        session_id: session_id,
        user_id: user_id,
        app_name: app_name,
        session_service: session_service
      )
    end

    it "provides access to session state" do
      # Set up some state in the session
      session_service.set_state(session_id: session_id, key: :test_key, value: "test_value")
      
      # CallbackContext should be able to access it
      expect(context.state_get(:test_key)).to eq("test_value")
    end

    it "tracks state changes in pending_state_delta" do
      context.state_set(:new_key, "new_value")
      expect(context.pending_state_delta).to include(new_key: "new_value")
    end

    it "can update multiple keys at once with state_update" do
      context.state_update(key1: "value1", key2: "value2")
      expect(context.pending_state_delta).to include(key1: "value1", key2: "value2")
    end

    it "can clear the pending state delta" do
      context.state_set(:test_key, "test_value")
      expect(context.pending_state_delta).not_to be_empty
      
      context.clear_pending_state_delta!
      expect(context.pending_state_delta).to be_empty
    end
  end

  describe ADK::ToolContext do
    subject(:tool_context) do
      described_class.new(
        session_id: session_id,
        user_id: user_id,
        app_name: app_name,
        session_service: session_service,
        invocation_id: invocation_id
      )
    end

    it "provides access to session state" do
      session_service.set_state(session_id: session_id, key: :tool_test_key, value: "tool_test_value")
      expect(tool_context.state_get(:tool_test_key)).to eq("tool_test_value")
    end

    it "tracks state changes in pending_state_delta" do
      tool_context.state_set(:new_tool_key, "new_tool_value")
      expect(tool_context.pending_state_delta).to include(new_tool_key: "new_tool_value")
    end
  end

  describe "Agent callback DSL" do
    it "allows setting callbacks via DSL" do
      definition = ADK::Agent.define do |a|
        a.name :callback_test_agent
        a.description "Test agent with callbacks"
        a.instruction "Test instruction"
        
        a.before_agent_callback do |ctx|
          # Simple callback that sets state
          ctx.state_set(:before_agent_ran, true)
          nil
        end
        
        a.after_agent_callback do |ctx, result|
          # Callback that modifies result
          result.merge(after_agent_ran: true)
        end
      end
      
      expect(definition.before_agent_callback).to be_a(Proc)
      expect(definition.after_agent_callback).to be_a(Proc)
    end
  end

  describe "Agent callback execution" do
    # Create a mock tool that just returns a success result
    before do
      class TestTool < ADK::Tool
        tool_description "A test tool for callbacks"
        self.explicit_tool_name = :test_tool
        
        def perform_execution(params, context)
          { status: :success, result: "Test tool executed" }
        end
      end
      
      # Register the tool globally
      ADK::GlobalToolManager.register_tool(TestTool)
    end
    
    after do
      # Clean up the global registry
      ADK::GlobalToolManager.reset!
    end
    
    it "executes before_agent_callback at the start of run_task" do
      before_agent_called = false
      
      definition = ADK::Agent.define do |a|
        a.name :before_agent_test
        a.description "Agent to test before_agent_callback"
        a.instruction "Test instruction"
        a.use_tool :test_tool
        
        a.before_agent_callback do |ctx|
          before_agent_called = true
          ctx.state_set(:callback_ran, true)
          nil # Continue normal execution
        end
      end
      
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      agent.start
      
      # Create a mock planner that returns a simple plan
      allow_any_instance_of(ADK::Planner).to receive(:plan).and_return(
        { steps: [] } # Empty plan for simplicity
      )
      
      # Run the agent's task
      result = agent.run_task(session_id: session_id, user_input: "Hello", session_service: session_service)
      
      # Check that callback was called
      expect(before_agent_called).to be true
      
      # Check that state was modified
      expect(session_service.get_state(session_id: session_id, key: :callback_ran)).to be true
    end
    
    it "allows before_agent_callback to override normal execution" do
      definition = ADK::Agent.define do |a|
        a.name :override_agent_test
        a.description "Agent to test callback override"
        a.instruction "Test instruction"
        a.use_tool :test_tool
        
        a.before_agent_callback do |ctx|
          ctx.state_set(:override_executed, true)
          # Return a complete result to override normal execution
          { status: :success, override_result: true }
        end
      end
      
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      agent.start
      
      # The planner should never be called
      expect_any_instance_of(ADK::Planner).not_to receive(:plan)
      
      # Run the agent's task
      result = agent.run_task(session_id: session_id, user_input: "Hello", session_service: session_service)
      
      # Check the result contains our override
      expect(result.content).to include(override_result: true)
      
      # Check that state was set
      expect(session_service.get_state(session_id: session_id, key: :override_executed)).to be true
    end
    
    it "executes after_agent_callback before returning the final result" do
      definition = ADK::Agent.define do |a|
        a.name :after_agent_test
        a.description "Agent to test after_agent_callback"
        a.instruction "Test instruction"
        a.use_tool :test_tool
        
        a.after_agent_callback do |ctx, result|
          # Modify the result
          result.merge(after_callback_modified: true)
        end
      end
      
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      agent.start
      
      # Create a mock planner that returns a simple plan
      allow_any_instance_of(ADK::Planner).to receive(:plan).and_return(
        { steps: [] } # Empty plan for simplicity
      )
      
      # Run the agent's task
      result = agent.run_task(session_id: session_id, user_input: "Hello", session_service: session_service)
      
      # Check that the result was modified by the callback
      expect(result.content).to include(after_callback_modified: true)
    end
    
    it "executes before_tool_callback before tool execution" do
      before_tool_called = false
      
      definition = ADK::Agent.define do |a|
        a.name :before_tool_test
        a.description "Agent to test before_tool_callback"
        a.instruction "Test instruction"
        a.use_tool :test_tool
        
        a.before_tool_callback do |tool, params, ctx|
          before_tool_called = true
          ctx.state_set(:before_tool_ran, true)
          nil # Continue with normal tool execution
        end
      end
      
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      agent.start
      
      # Create a mock planner that returns a plan using our test tool
      allow_any_instance_of(ADK::Planner).to receive(:plan).and_return(
        { 
          steps: [
            {
              tool: :test_tool,
              params: { foo: "bar" }
            }
          ] 
        }
      )
      
      # Run the agent's task
      result = agent.run_task(session_id: session_id, user_input: "Hello", session_service: session_service)
      
      # Verify the callback was called
      expect(before_tool_called).to be true
      
      # Check that state was set
      expect(session_service.get_state(session_id: session_id, key: :before_tool_ran)).to be true
    end
    
    it "allows before_tool_callback to override tool execution" do
      definition = ADK::Agent.define do |a|
        a.name :override_tool_test
        a.description "Agent to test tool override"
        a.instruction "Test instruction"
        a.use_tool :test_tool
        
        a.before_tool_callback do |tool, params, ctx|
          # Return a result to override the tool execution
          { status: :success, result: "Tool execution overridden by callback" }
        end
      end
      
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      agent.start
      
      # Create a mock planner that returns a plan using our test tool
      allow_any_instance_of(ADK::Planner).to receive(:plan).and_return(
        { 
          steps: [
            {
              tool: :test_tool,
              params: { foo: "bar" }
            }
          ] 
        }
      )
      
      # The tool's perform_execution should never be called
      expect_any_instance_of(TestTool).not_to receive(:perform_execution)
      
      # Run the agent's task
      result = agent.run_task(session_id: session_id, user_input: "Hello", session_service: session_service)
      
      # Check events to see if our override was used
      events = session_service.get_session(session_id: session_id).events
      tool_result_event = events.find { |e| e.role == :tool_result }
      
      expect(tool_result_event.content[:result]).to eq("Tool execution overridden by callback")
    end
    
    it "executes after_tool_callback after tool execution" do
      definition = ADK::Agent.define do |a|
        a.name :after_tool_test
        a.description "Agent to test after_tool_callback"
        a.instruction "Test instruction"
        a.use_tool :test_tool
        
        a.after_tool_callback do |tool, params, ctx, result|
          # Modify the result
          result[:result] = "#{result[:result]} and modified by callback"
          result
        end
      end
      
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      agent.start
      
      # Create a mock planner that returns a plan using our test tool
      allow_any_instance_of(ADK::Planner).to receive(:plan).and_return(
        { 
          steps: [
            {
              tool: :test_tool,
              params: { foo: "bar" }
            }
          ] 
        }
      )
      
      # Run the agent's task
      result = agent.run_task(session_id: session_id, user_input: "Hello", session_service: session_service)
      
      # Check events to see if our callback modified the result
      events = session_service.get_session(session_id: session_id).events
      tool_result_event = events.find { |e| e.role == :tool_result }
      
      expect(tool_result_event.content[:result]).to eq("Test tool executed and modified by callback")
    end
    
    it "handles errors in callbacks gracefully" do
      definition = ADK::Agent.define do |a|
        a.name :error_callback_test
        a.description "Agent to test callback error handling"
        a.instruction "Test instruction"
        a.use_tool :test_tool
        
        a.before_agent_callback do |ctx|
          raise "Deliberate error in before_agent_callback"
        end
        
        a.after_tool_callback do |tool, params, ctx, result|
          raise "Deliberate error in after_tool_callback"
        end
      end
      
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      agent.start
      
      # Run the agent's task - it should not raise exceptions to the caller
      result = agent.run_task(session_id: session_id, user_input: "Hello", session_service: session_service)
      
      # The result should indicate an error occurred
      expect(result.content[:status]).to eq(:error)
      expect(result.content[:error_message]).to include("Error in before_agent_callback")
    end
  end
end 