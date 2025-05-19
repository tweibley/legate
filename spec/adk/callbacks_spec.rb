# frozen_string_literal: true

require 'spec_helper'
require 'adk/agent'
require 'adk/callbacks/callback_context'
require 'adk/tool_context'
require 'adk/session_service/in_memory'
require 'adk/event'

RSpec.describe "ADK Callbacks" do
  let(:session_service) { ADK::SessionService::InMemory.new }
  let(:user_id) { "test-user-1" }
  let(:app_name) { "test-app" }
  let(:invocation_id) { SecureRandom.uuid }
  let(:agent_name) { :test_agent }
  # Create a session and get its ID
  let(:session) { session_service.create_session(user_id: user_id, app_name: app_name) }
  let(:session_id) { session.id }

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
      session_service.set_state(session_id: session_id, key: :test_key, value: "test value")
      expect(context.state_get(:test_key)).to eq("test value")
    end

    it "tracks state changes in pending_state_delta" do
      context.state_set(:new_key, "new value")
      expect(context.pending_state_delta).to eq(new_key: "new value")
    end

    it "can update multiple keys at once with state_update" do
      context.state_update(key1: "value1", key2: "value2")
      expect(context.pending_state_delta).to eq(key1: "value1", key2: "value2")
    end

    it "can clear the pending state delta" do
      context.state_set(:key, "value")
      expect(context.pending_state_delta).not_to be_empty
      context.clear_pending_state_delta!
      expect(context.pending_state_delta).to be_empty
    end
  end

  describe ADK::ToolContext do
    subject(:context) do
      described_class.new(
        session_id: session_id,
        user_id: user_id,
        app_name: app_name,
        session_service: session_service,
        invocation_id: invocation_id
      )
    end

    it "provides access to session state" do
      session_service.set_state(session_id: session_id, key: :test_key, value: "test value")
      expect(context.state_get(:test_key)).to eq("test value")
    end

    it "tracks state changes in pending_state_delta" do
      context.state_set(:new_key, "new value")
      expect(context.pending_state_delta).to eq(new_key: "new value")
    end
  end

  describe "Agent callback DSL" do
    it "allows setting callbacks via DSL" do
      definition = ADK::Agent.define do |a|
        a.name :callback_test
        a.description "Test agent with callbacks"
        a.instruction "Test instruction"
        
        a.before_agent_callback do |ctx|
          # This is a valid callback
          nil
        end
        
        a.after_agent_callback do |ctx, content|
          # This is a valid callback
          content
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
        
        a.before_agent_callback do |ctx|
          before_agent_called = true
          ctx.state_set(:before_agent_ran, true)
          nil # Continue with normal execution
        end
      end
      
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      agent.start
      
      # Mock the planner to return an empty plan
      allow_any_instance_of(ADK::Planner).to receive(:plan).and_return({ steps: [] })
      
      # Run task (this should execute before_agent_callback)
      agent.run_task(session_id: session_id, user_input: "test input", session_service: session_service)
      
      # Verify callback was called
      expect(before_agent_called).to be true
      # Verify state was set
      expect(session_service.get_state(session_id: session_id, key: :before_agent_ran)).to be true
    end
    
    it "allows before_agent_callback to override normal execution" do
      definition = ADK::Agent.define do |a|
        a.name :before_agent_override_test
        a.description "Agent to test before_agent_callback override"
        a.instruction "Test instruction"
        
        a.before_agent_callback do |ctx|
          ctx.state_set(:override_executed, true)
          { status: :success, result: "Execution overridden by callback" }
        end
      end
      
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      agent.start
      
      # Mock the planner - this should never be called due to override
      planner_mock = instance_double(ADK::Planner)
      expect(planner_mock).not_to receive(:plan)
      agent.instance_variable_set(:@planner, planner_mock)
      
      # Run task (should be overridden by before_agent_callback)
      result = agent.run_task(session_id: session_id, user_input: "test input", session_service: session_service)
      
      # Verify result content matches override
      expect(result.content[:result]).to eq("Execution overridden by callback")
      # Verify state change was applied
      expect(session_service.get_state(session_id: session_id, key: :override_executed)).to be true
    end
    
    it "executes after_agent_callback before returning the final result" do
      after_agent_called = false
      
      definition = ADK::Agent.define do |a|
        a.name :after_agent_test
        a.description "Agent to test after_agent_callback"
        a.instruction "Test instruction"
        
        a.after_agent_callback do |ctx, content|
          after_agent_called = true
          ctx.state_set(:after_agent_ran, true)
          content.merge(result: "Modified by after_agent_callback")
        end
      end
      
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      agent.start
      
      # Mock the planner to return an empty plan (resulting in fallback mode echo)
      allow_any_instance_of(ADK::Planner).to receive(:plan).and_return({ steps: [] })
      
      # Run task (this should execute after_agent_callback)
      result = agent.run_task(session_id: session_id, user_input: "test input", session_service: session_service)
      
      # Verify callback was called
      expect(after_agent_called).to be true
      # Verify result was modified
      expect(result.content[:result]).to eq("Modified by after_agent_callback")
      # Verify state was set
      expect(session_service.get_state(session_id: session_id, key: :after_agent_ran)).to be true
    end
    
    it "executes before_tool_callback before tool execution" do
      before_tool_called = false
      
      definition = ADK::Agent.define do |a|
        a.name :before_tool_test
        a.description "Agent to test before_tool_callback"
        a.instruction "Test instruction"
        a.use_tool :test_tool
        
        a.before_tool_callback do |tool, params, ctx|
          puts "DEBUG: before_tool_callback called!"
          before_tool_called = true
          ctx.state_set(:before_tool_ran, true)
          nil # Continue with normal tool execution
        end
      end
      
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      puts "DEBUG: Agent callbacks: #{agent.before_tool_callback.inspect}"
      agent.start
      
      # Override the global planner mock for this test
      allow_any_instance_of(ADK::Planner).to receive(:plan).and_return({ 
        steps: [{ tool: :test_tool, params: { arg: "value" } }] 
      })
      
      # Run task (this should execute before_tool_callback before the test_tool executes)
      result = agent.run_task(session_id: session_id, user_input: "test input", session_service: session_service)
      puts "DEBUG: After run_task, result: #{result.inspect}"
      
      # Get all events from the session
      events = session_service.get_session(session_id: session_id).events
      puts "DEBUG: Events: #{events.inspect}"
      
      # Verify callback was called
      expect(before_tool_called).to be true
      # Verify state was set
      expect(session_service.get_state(session_id: session_id, key: :before_tool_ran)).to be true
    end
    
    it "allows before_tool_callback to override tool execution" do
      definition = ADK::Agent.define do |a|
        a.name :before_tool_override_test
        a.description "Agent to test before_tool_callback override"
        a.instruction "Test instruction"
        a.use_tool :test_tool
        
        a.before_tool_callback do |tool, params, ctx|
          ctx.state_set(:tool_overridden, true)
          { status: :success, result: "Tool execution overridden by callback" }
        end
      end
      
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      agent.start
      
      # Override the global planner mock for this test
      allow_any_instance_of(ADK::Planner).to receive(:plan).and_return({ 
        steps: [{ tool: :test_tool, params: { arg: "value" } }] 
      })
      
      # Run task (this should execute before_tool_callback which overrides the tool execution)
      agent.run_task(session_id: session_id, user_input: "test input", session_service: session_service)
      
      # Get all events from the session
      events = session_service.get_session(session_id: session_id).events
      
      # Find the tool result event
      tool_result_event = events.find { |e| e.role == :tool_result && e.tool_name == :test_tool }
      
      # Verify result content matches override
      expect(tool_result_event.content[:result]).to eq("Tool execution overridden by callback")
      # Verify state change was applied
      expect(session_service.get_state(session_id: session_id, key: :tool_overridden)).to be true
    end
    
    it "executes after_tool_callback after tool execution" do
      after_tool_called = false
      
      definition = ADK::Agent.define do |a|
        a.name :after_tool_test
        a.description "Agent to test after_tool_callback"
        a.instruction "Test instruction"
        a.use_tool :test_tool
        
        a.after_tool_callback do |tool, params, ctx, result|
          after_tool_called = true
          ctx.state_set(:after_tool_ran, true)
          result.merge(result: "Test tool executed and modified by callback")
        end
      end
      
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      agent.start
      
      # Override the global planner mock for this test
      allow_any_instance_of(ADK::Planner).to receive(:plan).and_return({ 
        steps: [{ tool: :test_tool, params: { arg: "value" } }] 
      })
      
      # Run task (this should execute the tool and then after_tool_callback)
      agent.run_task(session_id: session_id, user_input: "test input", session_service: session_service)
      
      # Get all events from the session
      events = session_service.get_session(session_id: session_id).events
      
      # Find the tool result event
      tool_result_event = events.find { |e| e.role == :tool_result && e.tool_name == :test_tool }
      
      # Verify callback was called
      expect(after_tool_called).to be true
      # Verify result was modified
      expect(tool_result_event.content[:result]).to eq("Test tool executed and modified by callback")
      # Verify state was set
      expect(session_service.get_state(session_id: session_id, key: :after_tool_ran)).to be true
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
        
        a.before_tool_callback do |tool, params, ctx|
          raise "Deliberate error in before_tool_callback"
        end
      end
      
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      agent.start
      
      # Run task (this should catch the error in before_agent_callback)
      result = agent.run_task(session_id: session_id, user_input: "test input", session_service: session_service)
      
      # Verify error was caught and returned in result
      expect(result.content[:status]).to eq(:error)
      expect(result.content[:error_message]).to include("Error in before_agent_callback")
    end
  end
end 