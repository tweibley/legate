require 'spec_helper'
require 'gemini-ai' # Make sure gem is loaded for instance_double

RSpec.describe ADK::Planner do
  let(:mock_agent) { instance_double(ADK::Agent, name: 'mock_agent', model_name: 'test-model') }
  let(:mock_tool_list) { [instance_double(ADK::Tool, name: :tool_a, description: 'Does A', parameters: {})] }
  let(:mock_gemini_client) { instance_double(Gemini::Client) }
  let(:task) { "Perform action A" }
  let(:api_key) { 'test-api-key' }

  before do
    # Stub ENV (important for tests)
    allow(ENV).to receive(:[]).and_call_original # Allow other ENV vars
    allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return(api_key)
    allow(ENV).to receive(:[]).with('ADK_LOG_LEVEL').and_return('FATAL') # Silence logs unless needed

    # Mock agent's tools
    allow(mock_agent).to receive(:tools).and_return(mock_tool_list)

    # Mock Gemini client instantiation
    allow(Gemini).to receive(:new).and_return(mock_gemini_client)
  end

  subject(:planner) { described_class.new(agent: mock_agent, model_name: 'test-model') }

  describe '#initialize' do
    it 'initializes Gemini client with correct model and api key' do
       expect(Gemini).to receive(:new).with(
         credentials: { service: 'generative-language-api', api_key: api_key },
         options: { model: 'test-model', server_sent_events: false }
       ).and_return(mock_gemini_client)
       planner # Trigger initialization
       expect(planner.model_name).to eq('test-model')
    end

     it 'uses agent default model if none provided' do
        allow(ADK::Agent).to receive(:DEFAULT_MODEL).and_return('flash-default')
        expect(Gemini).to receive(:new).with(hash_including(options: hash_including(model: 'flash-default'))).and_return(mock_gemini_client)
        described_class.new(agent: mock_agent) # No model_name passed
     end

     it 'handles missing API key' do
       allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return(nil)
       expect(ADK.logger).to receive(:error).with(/GOOGLE_API_KEY not found/)
       expect(Gemini).not_to receive(:new)
       planner_no_key = described_class.new(agent: mock_agent)
       expect(planner_no_key.instance_variable_get(:@client)).to be_nil
     end
  end

  describe '#plan' do
    let(:gemini_response_text) { '[{"tool_name": "tool_a", "parameters": {}}]' }
    let(:gemini_response) { { 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => gemini_response_text }] } }] } }
    let(:expected_plan) { [{ tool: :tool_a, params: {} }] }

    before do
       # Ensure client is mocked for plan tests
       allow(planner).to receive(:client).and_return(mock_gemini_client)
       allow(mock_gemini_client).to receive(:generate_content).and_return(gemini_response)
    end

    it 'builds a prompt including tool descriptions' do
       expect(planner).to receive(:build_multi_step_gemini_prompt).with(task, instance_of(String)).and_call_original
       planner.plan(task)
    end

    it 'calls the Gemini client generate_content' do
        expect(mock_gemini_client).to receive(:generate_content).with(hash_including(contents: anything)).and_return(gemini_response)
        planner.plan(task)
    end

    it 'parses and validates a valid JSON response' do
        result = planner.plan(task)
        expect(result).to eq(expected_plan)
    end

    context 'when gemini response is an empty plan' do
       let(:gemini_response_text) { '[]' }
       it 'returns an empty array' do
          result = planner.plan(task)
          expect(result).to eq([])
       end
    end

     context 'when gemini response has ```json``` markers' do
       let(:gemini_response_text) { "```json\n[{\"tool_name\": \"tool_a\", \"parameters\": {}}]\n```" }
       it 'parses correctly' do
          result = planner.plan(task)
          expect(result).to eq(expected_plan)
       end
     end

    context 'when gemini response is invalid JSON' do
       let(:gemini_response_text) { 'this is not json' }
       it 'returns the fallback plan' do
          expect(planner).to receive(:fallback_plan).with(task, instance_of(String)).and_call_original
          result = planner.plan(task)
          expect(result).to include(hash_including(tool: :echo)) # Check fallback
       end
    end

    context 'when validation fails (e.g., unknown tool)' do
       let(:gemini_response_text) { '[{"tool_name": "unknown_tool", "parameters": {}}]' }
       it 'returns the fallback plan' do
          expect(planner).to receive(:fallback_plan).with(task, instance_of(String)).and_call_original
          result = planner.plan(task)
          expect(result).to include(hash_including(tool: :echo))
       end
    end

     context 'when gemini client raises an error' do
        before { allow(mock_gemini_client).to receive(:generate_content).and_raise(StandardError.new("API Boom")) }
        it 'returns the fallback plan' do
           expect(planner).to receive(:fallback_plan).with(task, instance_of(String)).and_call_original
           result = planner.plan(task)
           expect(result).to include(hash_including(tool: :echo))
           expect(result.first[:params][:message]).to include("API Boom")
        end
     end

     context 'when client is not initialized' do
        before { allow(planner).to receive(:client).and_return(nil) }
        it 'returns the fallback plan' do
          expect(planner).to receive(:fallback_plan).with(task, instance_of(String)).and_call_original
          result = planner.plan(task)
          expect(result).to include(hash_including(tool: :echo))
          expect(result.first[:params][:message]).to include("Gemini client not available")
        end
     end
  end
   # TODO: Add tests for private methods like format_tools_for_prompt, parse, validate if needed
end
