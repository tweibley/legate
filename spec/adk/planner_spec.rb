# File: spec/adk/planner_spec.rb
require 'spec_helper'

RSpec.describe ADK::Planner do
  # Mock basic metadata for tools used in planner tests
  let(:echo_tool_metadata) { { name: :echo, description: 'Echoes input', parameters: { message: { required: true } } } }
  let(:mock_agent_metadata) { [echo_tool_metadata] } # Default metadata for most agent mocks
  let(:agent_with_echo) {
    # Allow instruction call for this mock as well
    instance_double(ADK::Agent, available_tools_metadata: mock_agent_metadata, name: 'test_agent', instruction: nil)
  }
  let(:agent_without_tools) {
    # Allow the call to instruction and return nil
    instance_double(ADK::Agent, available_tools_metadata: [], name: 'test_agent', instruction: nil)
  }

  # Use agent_without_tools as the default agent for most tests
  let(:agent) { agent_without_tools }
  let(:mock_client) { double('Gemini') }
  let(:mock_logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:planner) { described_class.new(agent: agent, logger: mock_logger) }

  describe '#initialize' do
    before do
      allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return('fake-api-key')
      allow(Gemini).to receive(:new).and_return(mock_client)
    end

    it 'initializes with an agent' do
      expect(planner.agent).to eq(agent)
    end

    it 'initializes with a default model name' do
      # Mocked default model constant from Agent
      default_model = 'gemini-2.0-flash'
      allow(ADK::Agent).to receive(:const_get).with(:DEFAULT_MODEL).and_return(default_model)

      # Create a new planner with the mock in place
      planner_with_default = described_class.new(agent: agent, logger: mock_logger)
      expect(planner_with_default.model_name).to eq(default_model)
    end

    it 'uses a custom model name when provided' do
      custom_planner = described_class.new(agent: agent, model_name: 'gemini-2.0-flash', logger: mock_logger)
      expect(custom_planner.model_name).to eq('gemini-2.0-flash')
    end

    it 'logs an error when API key is missing' do
      allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return(nil)
      expect(mock_logger).to receive(:error).with("GOOGLE_API_KEY not found. GeminiPlanner requires an API key.")
      described_class.new(agent: agent, logger: mock_logger)
    end

    it 'logs an error when Gemini client initialization fails' do
      allow(Gemini).to receive(:new).and_raise(StandardError.new("Initialization error"))
      expect(mock_logger).to receive(:error).with(/Failed to initialize Gemini AI client/)
      planner = described_class.new(agent: agent, logger: mock_logger)
      expect(planner.instance_variable_get(:@client)).to be_nil
    end
  end

  describe '#plan' do
    before do
      allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return('fake-api-key')
      allow(Gemini).to receive(:new).and_return(mock_client)
      allow(planner).to receive(:format_tools_for_prompt).and_return('Tool descriptions')
      allow(planner).to receive(:build_multi_step_gemini_prompt).and_return('Planning prompt')
    end

    context 'when Gemini client is not initialized' do
      it 'returns a fallback plan' do
        # Create a test instance of planner for this specific test
        test_planner = described_class.new(agent: agent, logger: mock_logger)

        # Directly set the instance variable to nil
        test_planner.instance_variable_set(:@client, nil)

        # Create a fallback response
        fallback_response = [{ tool: :echo, params: { message: "fallback message" } }]

        # Mock the fallback_plan method
        allow(test_planner).to receive(:fallback_plan).with('test task',
                                                            "Gemini client not available.").and_return(fallback_response)

        # Expect logger to receive the error
        expect(mock_logger).to receive(:error).with("Gemini client not initialized. Falling back to default plan.")

        # Call the method under test
        result = test_planner.plan('test task')

        # Verify the result
        expect(result).to eq(fallback_response)
      end
    end

    context 'when Gemini client is available' do
      let(:gemini_response) do
        {
          'candidates' => [
            {
              'content' => {
                'parts' => [
                  { 'text' => '[{"tool_name": "echo", "parameters": {"message": "Hello"}}]' }
                ]
              }
            }
          ]
        }
      end

      before do
        allow(planner).to receive(:instance_variable_get).with(:@client).and_return(mock_client)
        allow(mock_client).to receive(:generate_content).and_return(gemini_response)
      end

      it 'sends a request to Gemini and processes the response' do
        expect(mock_client).to receive(:generate_content).with(hash_including(
                                                                 contents: [{ role: 'user',
                                                                              parts: { text: 'Planning prompt' } }]
                                                               )).and_return(gemini_response)

        expect(planner).to receive(:parse_gemini_response).with(
          '[{"tool_name": "echo", "parameters": {"message": "Hello"}}]'
        ).and_call_original

        expect(planner).to receive(:validate_and_format_multi_step_plan).and_return([
                                                                                      { tool: :echo,
                                                                                        params: { message: "Hello" } }
                                                                                    ])

        result = planner.plan('task')
        expect(result).to eq([{ tool: :echo, params: { message: "Hello" } }])
      end

      it 'handles empty Gemini response' do
        empty_response = { 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => nil }] } }] }
        allow(mock_client).to receive(:generate_content).and_return(empty_response)

        expect(mock_logger).to receive(:warn).with("Gemini response was empty or couldn't find text.")
        expect(planner).to receive(:fallback_plan)

        planner.plan('task')
      end

      it 'handles JSON parsing errors' do
        invalid_json_response = {
          'candidates' => [{ 'content' => { 'parts' => [{ 'text' => 'Not valid JSON' }] } }]
        }
        allow(mock_client).to receive(:generate_content).and_return(invalid_json_response)

        expect(planner).to receive(:parse_gemini_response).and_raise(JSON::ParserError.new("Invalid JSON"))
        expect(mock_logger).to receive(:error).with(/Failed to parse Gemini response as JSON/)
        expect(planner).to receive(:fallback_plan)

        planner.plan('task')
      end

      it 'handles general errors during planning' do
        allow(mock_client).to receive(:generate_content).and_raise(StandardError.new("API error"))

        expect(mock_logger).to receive(:error).with(/Error during planning with gemini-ai/)
        expect(planner).to receive(:fallback_plan)

        planner.plan('task')
      end
    end
  end

  describe '#parse_gemini_response' do
    it 'parses valid JSON response' do
      result = planner.send(:parse_gemini_response, '[{"key": "value"}]')
      expect(result).to eq([{ "key" => "value" }])
    end

    it 'removes markdown code blocks from response' do
      result = planner.send(:parse_gemini_response, "```json\n[{\"key\": \"value\"}]\n```")
      expect(result).to eq([{ "key" => "value" }])
    end

    it 'removes generic code blocks from response' do
      result = planner.send(:parse_gemini_response, "```\n[{\"key\": \"value\"}]\n```")
      expect(result).to eq([{ "key" => "value" }])
    end

    it 'raises error when response is not a JSON array' do
      expect {
        planner.send(:parse_gemini_response, '{\"key\": \"value\"}')
      }.to raise_error(JSON::ParserError)
    end
  end

  describe '#validate_and_format_multi_step_plan' do
    # Use agent_with_echo for these tests
    let(:agent) { agent_with_echo }
    let(:planner) { described_class.new(agent: agent, logger: mock_logger) }

    it 'returns an empty array if the parsed response is not an array' do
      expect(mock_logger).to receive(:warn)
      result = planner.send(:validate_and_format_multi_step_plan, {})
      expect(result).to eq([])
    end

    it 'returns an empty array if any step is not a hash' do
      expect(mock_logger).to receive(:warn)
      result = planner.send(:validate_and_format_multi_step_plan, [{ "tool_name" => "echo" }, "invalid_step"])
      expect(result).to eq([])
    end

    it 'returns an empty array if tool_name is missing or empty' do
      expect(mock_logger).to receive(:warn)
      result = planner.send(:validate_and_format_multi_step_plan, [{ "tool_name" => "", "parameters" => {} }])
      expect(result).to eq([])
    end

    it 'returns an empty array if tool does not exist' do
      expect(mock_logger).to receive(:warn)
      result = planner.send(:validate_and_format_multi_step_plan,
                            [{ "tool_name" => "unknown_tool", "parameters" => {} }])
      expect(result).to eq([])
    end

    it 'returns an empty array if parameters is not a hash' do
      expect(mock_logger).to receive(:warn)
      result = planner.send(:validate_and_format_multi_step_plan,
                            [{ "tool_name" => "echo", "parameters" => "invalid" }])
      expect(result).to eq([])
    end

    it 'returns a properly formatted plan when input is valid' do
      result = planner.send(:validate_and_format_multi_step_plan,
                            [{ "tool_name" => "echo", "parameters" => { "message" => "Hello" } }])
      expect(result).to eq([{ tool: :echo, params: { message: "Hello" } }])
    end

    it 'converts parameter keys to symbols' do
      result = planner.send(:validate_and_format_multi_step_plan,
                            [{ "tool_name" => "echo", "parameters" => { "message" => "Hello" } }])
      expect(result.first[:params].keys.first).to be_a(Symbol)
    end
  end

  describe '#fallback_plan' do
    context 'when echo tool is available' do
      # Use agent_with_echo here
      let(:agent) { agent_with_echo }
      let(:planner) { described_class.new(agent: agent, logger: mock_logger) }

      it 'creates a fallback plan using the echo tool' do
        expect(mock_logger).to receive(:warn)
        result = planner.send(:fallback_plan, 'original task', 'reason for fallback')
        expect(result).to eq([{
                               tool: :echo,
                               params: { message: "Planning failed: reason for fallback. Original task: original task" }
                             }])
      end
    end

    context 'when echo tool is not available' do
      # Use agent_without_tools here (which is the default let(:agent))
      let(:planner) { described_class.new(agent: agent, logger: mock_logger) }

      it 'returns an empty plan' do
        expect(mock_logger).to receive(:warn)
        expect(mock_logger).to receive(:error).with("Fallback failed: Echo tool not available to the agent.")
        result = planner.send(:fallback_plan, 'original task', 'reason for fallback')
        expect(result).to eq([])
      end
    end
  end

  describe '#format_tools_for_prompt' do
    # Define metadata hashes directly for these tests, agent mock isn't needed
    let(:tool_no_params_metadata) { { name: :test, description: 'Test tool', parameters: {} } }
    let(:tool_with_params_metadata) do
      {
        name: :parameterized,
        description: 'Tool with params',
        parameters: {
          required_param: { type: 'string', required: true, description: 'A required param' },
          optional_param: { type: 'number', required: false, description: 'An optional param' }
        }
      }
    end
    # Planner instance for these tests (can use default agent_without_tools)
    let(:planner) { described_class.new(agent: agent, logger: mock_logger) }

    it 'returns a message when no tools are available' do
      # Stub the call on the specific planner instance for this test
      allow(planner.agent).to receive(:available_tools_metadata).and_return([])
      expect(planner.send(:format_tools_for_prompt)).to eq("No tools available.")
    end

    it 'formats a tool with no parameters' do
      allow(planner.agent).to receive(:available_tools_metadata).and_return([tool_no_params_metadata])
      result = planner.send(:format_tools_for_prompt)
      expect(result).to include("Tool Name: test")
      expect(result).to include("Description: Test tool")
      expect(result).to include("Parameters:\n  None")
    end

    it 'formats a tool with parameters' do
      allow(planner.agent).to receive(:available_tools_metadata).and_return([tool_with_params_metadata])
      result = planner.send(:format_tools_for_prompt)
      expect(result).to include("Tool Name: parameterized")
      expect(result).to include("Description: Tool with params")
      expect(result).to include("required_param (string, required)")
      expect(result).to include("optional_param (number, optional)")
    end

    it 'formats multiple tools' do
      allow(planner.agent).to receive(:available_tools_metadata).and_return([tool_no_params_metadata,
                                                                             tool_with_params_metadata])
      result = planner.send(:format_tools_for_prompt)
      expect(result).to include("Tool Name: test")
      expect(result).to include("Tool Name: parameterized")
    end
  end

  describe '#build_multi_step_gemini_prompt' do
    let(:task) { 'test task' }
    let(:tools_description) { 'tool descriptions' }

    context 'when agent has an instruction' do
      let(:instruction) { 'Be concise.' }
      let(:agent_with_instruction) { instance_double(ADK::Agent, instruction: instruction) }
      let(:planner) { described_class.new(agent: agent_with_instruction, logger: mock_logger) }

      it 'prepends the instruction to the prompt' do
        prompt = planner.send(:build_multi_step_gemini_prompt, task, tools_description)
        expect(prompt).to start_with("AGENT_INSTRUCTION: #{instruction}\n---\n")
        expect(prompt).to include("You are an AI planner") # Check original prompt part is still there
        expect(prompt).to include("User Request: \"#{task}\"")
        expect(prompt).to include(tools_description)
      end
    end

    context 'when agent instruction is nil' do
      let(:agent_without_instruction) { instance_double(ADK::Agent, instruction: nil) }
      let(:planner) { described_class.new(agent: agent_without_instruction, logger: mock_logger) }

      it 'does not include the instruction block' do
        prompt = planner.send(:build_multi_step_gemini_prompt, task, tools_description)
        expect(prompt).not_to include('AGENT_INSTRUCTION:')
        expect(prompt).to start_with("You are an AI planner")
        expect(prompt).to include("User Request: \"#{task}\"")
        expect(prompt).to include(tools_description)
      end
    end

    context 'when agent instruction is an empty string' do
      let(:agent_with_empty_instruction) { instance_double(ADK::Agent, instruction: '   ') }
      let(:planner) { described_class.new(agent: agent_with_empty_instruction, logger: mock_logger) }

      it 'does not include the instruction block' do
        prompt = planner.send(:build_multi_step_gemini_prompt, task, tools_description)
        expect(prompt).not_to include('AGENT_INSTRUCTION:')
        expect(prompt).to start_with("You are an AI planner")
        expect(prompt).to include("User Request: \"#{task}\"")
        expect(prompt).to include(tools_description)
      end
    end

    # Keep original basic tests as well
    let(:planner_basic) {
      described_class.new(agent: agent_without_tools, logger: mock_logger)
    } # Use agent without instruction for these

    it 'includes the task in the prompt' do
      result = planner_basic.send(:build_multi_step_gemini_prompt, task, tools_description)
      expect(result).to include("User Request: \"#{task}\"")
      expect(result).to include("Now, plan the User Request: \"#{task}\"")
    end

    it 'includes the tool descriptions in the prompt' do
      result = planner_basic.send(:build_multi_step_gemini_prompt, task, tools_description)
      expect(result).to include(tools_description)
    end

    it 'includes instructions for JSON format' do
      result = planner_basic.send(:build_multi_step_gemini_prompt, task, tools_description)
      expect(result).to include('Respond ONLY with a single JSON array')
    end
  end
end
