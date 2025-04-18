# File: spec/adk/mcp/util/schema_converter_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'adk/mcp/util/schema_converter'
require 'adk/mcp' # Ensure logger is available
require 'dry-schema' # Needed for testing adk_to_dry_schema

RSpec.describe ADK::Mcp::Util::SchemaConverter do
  let(:logger_spy) { spy('Logger') }

  before do
    allow(ADK::Mcp).to receive(:logger).and_return(logger_spy)
  end

  describe '.json_to_adk' do
    context 'with valid basic types' do
      let(:properties) do
        {
          'name' => { 'type' => 'string', 'description' => 'User name' },
          'age' => { 'type' => 'integer', 'description' => 'User age' },
          'score' => { 'type' => 'number', 'description' => 'User score' },
          'active' => { 'type' => 'boolean', 'description' => 'Activation status' }
        }
      end
      let(:required) { ['name', 'age'] }

      it 'converts properties to ADK parameters hash' do
        expected_params = {
          name: { type: :string, required: true, description: 'User name' },
          age: { type: :integer, required: true, description: 'User age' },
          score: { type: :numeric, required: false, description: 'User score' },
          active: { type: :boolean, required: false, description: 'Activation status' }
        }
        expect(described_class.json_to_adk(properties, required)).to eq(expected_params)
      end

      it 'handles empty required array' do
        expected_params = {
          name: { type: :string, required: false, description: 'User name' },
          age: { type: :integer, required: false, description: 'User age' },
          score: { type: :numeric, required: false, description: 'User score' },
          active: { type: :boolean, required: false, description: 'Activation status' }
        }
        expect(described_class.json_to_adk(properties, [])).to eq(expected_params)
      end

      it 'handles nil required array' do
        expected_params = {
          name: { type: :string, required: false, description: 'User name' },
          age: { type: :integer, required: false, description: 'User age' },
          score: { type: :numeric, required: false, description: 'User score' },
          active: { type: :boolean, required: false, description: 'Activation status' }
        }
        expect(described_class.json_to_adk(properties, nil)).to eq(expected_params)
      end

      it 'handles missing descriptions' do
        props_no_desc = { 'id' => { 'type' => 'string' } }
        expected = { id: { type: :string, required: false, description: '' } }
        expect(described_class.json_to_adk(props_no_desc)).to eq(expected)
      end
    end

    context 'with invalid or unsupported input' do
      it 'returns empty hash for nil properties' do
        expect(described_class.json_to_adk(nil)).to eq({})
      end

      it 'returns empty hash for non-hash properties' do
        expect(described_class.json_to_adk([])).to eq({})
      end

      it 'skips properties with invalid schema format' do
        properties = { 'valid' => { 'type' => 'string' }, 'invalid' => 'not_a_hash' }
        result = described_class.json_to_adk(properties)
        expect(result).to have_key(:valid)
        expect(result).not_to have_key(:invalid)
        expect(logger_spy).to have_received(:warn).with(/Skipping MCP property 'invalid': Invalid schema format/).once
      end

      it 'skips properties with missing type' do
        properties = { 'valid' => { 'type' => 'string' }, 'no_type' => { 'description' => 'test' } }
        result = described_class.json_to_adk(properties)
        expect(result).to have_key(:valid)
        expect(result).not_to have_key(:no_type)
        expect(logger_spy).to have_received(:warn).with(/Skipping MCP property 'no_type': Invalid schema format/).once
      end

      it 'skips and logs warning for unsupported types like array' do
        properties = { 'my_array' => { 'type' => 'array', 'description' => 'List of items' } }
        expect(described_class.json_to_adk(properties)).to be_empty
        expect(logger_spy).to have_received(:warn).with(/Unsupported JSON Schema type 'array'/)
      end

      it 'skips and logs warning for unsupported types like object' do
        properties = { 'my_object' => { 'type' => 'object', 'description' => 'Some structure' } }
        expect(described_class.json_to_adk(properties)).to be_empty
        expect(logger_spy).to have_received(:warn).with(/Unsupported JSON Schema type 'object'/)
      end

      it 'skips and logs warning for unknown types' do
        properties = { 'weird_type' => { 'type' => 'custom_blob', 'description' => 'Weird' } }
        expect(described_class.json_to_adk(properties)).to be_empty
        expect(logger_spy).to have_received(:warn).with(/Unsupported JSON Schema type 'custom_blob'/)
      end
    end
  end

  describe '.adk_to_dry_schema' do
    # Helper to evaluate the generated Proc and build a Dry::Schema instance
    def build_schema_from_proc(proc)
      Dry::Schema.Params(&proc)
    end

    context 'with valid basic ADK parameters' do
      let(:adk_params) do
        {
          name: { type: :string, required: true, description: 'User name' },
          age: { type: :integer, required: true, description: 'User age' },
          score: { type: :numeric, required: false, description: 'User score' },
          active: { type: :boolean, required: false, description: "Is 'active'?" }
        }
      end

      it 'generates a Proc that defines the correct Dry::Schema structure' do
        schema_proc = described_class.adk_to_dry_schema(adk_params)
        expect(schema_proc).to be_a(Proc)

        schema = build_schema_from_proc(schema_proc)

        # Test required fields and types
        valid_data = { name: 'Test', age: 30, score: 99.5, active: true }
        result = schema.call(valid_data)
        expect(result).to be_success
        expect(result.to_h).to eq(valid_data)

        # Test missing required field
        invalid_data_missing = { age: 30 }
        result_missing = schema.call(invalid_data_missing)
        expect(result_missing).to be_failure
        expect(result_missing.errors[:name]).to include('is missing')

        # Test wrong type
        invalid_data_type = { name: 'Test', age: 'thirty', score: 99.5, active: true }
        result_type = schema.call(invalid_data_type)
        expect(result_type).to be_failure
        expect(result_type.errors[:age]).to include('must be an integer')

        # Test optional fields present
        result_optional_present = schema.call({ name: 'Test', age: 30, score: 99.5, active: false })
        expect(result_optional_present).to be_success
        expect(result_optional_present.to_h[:score]).to eq(99.5)
        expect(result_optional_present.to_h[:active]).to eq(false)

        # Test optional fields absent
        result_optional_absent = schema.call({ name: 'Test', age: 30 })
        expect(result_optional_absent).to be_success
        expect(result_optional_absent.to_h).not_to have_key(:score)
        expect(result_optional_absent.to_h).not_to have_key(:active)
      end
    end

    context 'with invalid or unsupported ADK parameters' do
      it 'returns an empty Proc for nil input' do
        schema_proc = described_class.adk_to_dry_schema(nil)
        schema = build_schema_from_proc(schema_proc)
        expect(schema.call({})).to be_success # Empty schema passes anything
      end

      it 'returns an empty Proc for non-hash input' do
        schema_proc = described_class.adk_to_dry_schema([])
        schema = build_schema_from_proc(schema_proc)
        expect(schema.call({})).to be_success
      end

      it 'skips parameters with invalid definition format' do
        adk_params = { valid: { type: :string }, invalid: 'not_a_hash' }
        schema_proc = described_class.adk_to_dry_schema(adk_params)
        schema = build_schema_from_proc(schema_proc)
        expect(schema.rules.key?(:valid)).to be true
        expect(schema.rules.key?(:invalid)).to be false
        expect(logger_spy).to have_received(:warn).with("Skipping ADK parameter 'invalid': Invalid definition format or missing type.").once
      end

      it 'skips parameters with missing type' do
        adk_params = { valid: { type: :string }, no_type: { required: true } }
        schema_proc = described_class.adk_to_dry_schema(adk_params)
        schema = build_schema_from_proc(schema_proc)
        expect(schema.rules.key?(:valid)).to be true
        expect(schema.rules.key?(:no_type)).to be false
        expect(logger_spy).to have_received(:warn).with("Skipping ADK parameter 'no_type': Invalid definition format or missing type.").once
      end

      it 'maps :array and logs warning' do
        adk_params = { list: { type: :array, required: false, description: 'A list' } }
        schema_proc = described_class.adk_to_dry_schema(adk_params)
        schema = build_schema_from_proc(schema_proc)

        # Test validation instead of inspecting internal structure
        expect(schema.call({ list: [1, 2] })).to be_success
        expect(schema.call({})).to be_success # Optional: passes when absent
        expect(schema.call({ list: 'not_an_array' })).to be_failure # Ensure basic type check works

        expect(logger_spy).to have_received(:warn).with(/ADK parameter 'list': Type :array basic mapping/).once
      end

      it 'maps :hash/:object and logs warning' do
        adk_params = { data: { type: :hash, required: true, description: 'Some data' } }
        schema_proc = described_class.adk_to_dry_schema(adk_params)
        schema = build_schema_from_proc(schema_proc)

        # Test validation instead of inspecting internal structure
        expect(schema.call({ data: { a: 1 } })).to be_success
        expect(schema.call({})).to be_failure # Required: fails when absent
        expect(schema.call({ data: 'not_a_hash' })).to be_failure # Ensure basic type check works

        expect(logger_spy).to have_received(:warn).with(/ADK parameter 'data': Type :hash basic mapping/).once
      end

      it 'skips unknown ADK types and logs warning' do
        adk_params = { unknown: { type: :custom_blob, required: true } }
        schema_proc = described_class.adk_to_dry_schema(adk_params)
        expected_log_message = "ADK parameter 'unknown': Unsupported ADK type 'custom_blob'. Skipping."
        expect(logger_spy).to have_received(:warn).with(expected_log_message).once
        schema = build_schema_from_proc(schema_proc)
        expect(schema.rules.key?(:unknown)).to be false
      end
    end
  end
end
