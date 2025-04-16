# File: spec/adk/tools/agent_tool_spec.rb
require 'spec_helper'
require 'redis' # Need this for Redis::CannotConnectError

RSpec.describe ADK::Tools::AgentTool do
  subject(:tool) { described_class.new }

  let(:target_agent_name) { 'calculator_agent' }
  let(:task_to_delegate) { 'what is 10 * 5' }
  let(:params) { { target_agent_name: target_agent_name, task: task_to_delegate } }

  # --- Mocks ---
  let(:mock_redis) { instance_double(Redis) }
  let(:mock_target_agent) { instance_double(ADK::Agent) }
  let(:mock_calculator_tool) { instance_double(ADK::Tools::Calculator) }
  let(:target_definition) do
    {
      'description' => 'A calculator',
      'tools' => '["calculator"]',
      'model' => 'gemini-test-model'
    }
  end
  let(:target_key) { "adk:agent:#{target_agent_name}" }
  let(:expected_target_result) { { status: :success, result: 50.0 } }

  before do
    # Mock Redis connection and data loading by default
    allow(Redis).to receive(:new).and_return(mock_redis)
    allow(mock_redis).to receive(:ping)
    allow(mock_redis).to receive(:hmget)
                          .with(target_key, 'description', 'tools', 'model')
                          .and_return(target_definition.values)

    # Mock ToolRegistry for the target agent's tool
    allow(ADK::ToolRegistry).to receive(:create_instance).with(:calculator).and_return(mock_calculator_tool)

    # Mock Agent instantiation for the target agent
    allow(ADK::Agent).to receive(:new).and_call_original # Allow normal agent init
    allow(ADK::Agent).to receive(:new)
                       .with(hash_including(name: matching(/#{target_agent_name}_delegated/), model_name: 'gemini-test-model'))
                       .and_return(mock_target_agent)

    # Mock methods on the target agent instance
    allow(mock_target_agent).to receive(:add_tool).with(mock_calculator_tool)
    allow(mock_target_agent).to receive(:start)
    allow(mock_target_agent).to receive(:run_task).with(task_to_delegate).and_return(expected_target_result)
  end

  describe '#initialize' do
    # Basic checks
    it { expect(tool.name).to eq(:delegate_task) }
    it { expect(tool.parameters.keys).to contain_exactly(:target_agent_name, :task) }
    it { expect(tool.parameters[:target_agent_name][:required]).to be true }
    it { expect(tool.parameters[:task][:required]).to be true }
  end

  describe '#execute' do
    context 'when delegation is successful' do
      it 'connects to redis, loads definition, instantiates agent, adds tools, runs task' do
        expect(Redis).to receive(:new).and_return(mock_redis)
        expect(mock_redis).to receive(:ping)
        expect(mock_redis).to receive(:hmget).with(target_key, 'description', 'tools', 'model').and_return(target_definition.values)
        expect(ADK::Agent).to receive(:new).with(hash_including(name: matching(/#{target_agent_name}_delegated/))).and_return(mock_target_agent)
        expect(ADK::ToolRegistry).to receive(:create_instance).with(:calculator).and_return(mock_calculator_tool)
        expect(mock_target_agent).to receive(:add_tool).with(mock_calculator_tool)
        expect(mock_target_agent).to receive(:start)
        expect(mock_target_agent).to receive(:run_task).with(task_to_delegate).and_return(expected_target_result)

        tool.execute(params)
      end

      it 'returns a success hash containing the target agents result' do
        result = tool.execute(params)
        expect(result).to eq({ status: :success, result: expected_target_result })
      end
    end

    context 'when target agent definition is not found' do
      before do
        allow(mock_redis).to receive(:hmget).with(target_key, 'description', 'tools', 'model').and_return([nil, nil, nil]) # Simulate not found
      end

      it 'returns an error hash' do
        result = tool.execute(params)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include("Target agent definition '#{target_agent_name}' not found")
      end
    end

    context 'when redis connection fails' do
       before do
         allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError.new("Cannot connect"))
       end

       it 'returns an error hash' do
         result = tool.execute(params)
         expect(result[:status]).to eq(:error)
         expect(result[:error_message]).to include("Could not connect to Redis")
       end
    end

     context 'when target agent has invalid tools JSON' do
        let(:invalid_target_definition) { target_definition.merge('tools' => '[invalid json') }
        before do
            allow(mock_redis).to receive(:hmget).with(target_key, 'description', 'tools', 'model').and_return(invalid_target_definition.values)
        end

       it 'returns an error hash' do
         result = tool.execute(params)
         expect(result[:status]).to eq(:error)
         expect(result[:error_message]).to include("Failed to parse tools JSON")
       end
     end

     context 'when target agent task execution raises an error' do
        let(:target_error) { StandardError.new("Target agent failed!") }
        before do
            allow(mock_target_agent).to receive(:run_task).with(task_to_delegate).and_raise(target_error)
        end

       it 'returns an error hash capturing the exception' do
         result = tool.execute(params)
         expect(result[:status]).to eq(:error)
         expect(result[:error_message]).to include("Unexpected error during delegation", "StandardError - Target agent failed!")
       end
     end

    context 'with missing parameters (base validation)' do
       it 'raises ADK::Error if target_agent_name is missing' do
         expect { tool.execute(task: task_to_delegate) }.to raise_error(ADK::Error, /Missing required parameters: target_agent_name/)
       end

        it 'raises ADK::Error if task is missing' do
         expect { tool.execute(target_agent_name: target_agent_name) }.to raise_error(ADK::Error, /Missing required parameters: task/)
       end
    end
  end
end
