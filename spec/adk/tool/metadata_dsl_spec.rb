# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool'

RSpec.describe ADK::Tool::MetadataDsl do
  describe 'name inference' do
    context 'with standard class names' do
      it 'infers snake_case name' do
        stub_const('StandardTool', Class.new(ADK::Tool))
        expect(StandardTool.inferred_name).to eq(:standard_tool)
      end
    end

    context 'with namespaced class names' do
      it 'ignores module namespace' do
        stub_const('ADK::Tools::NamespacedTool', Class.new(ADK::Tool))
        expect(ADK::Tools::NamespacedTool.inferred_name).to eq(:namespaced_tool)
      end
    end

    context 'with acronyms in class names' do
      it 'handles acronyms correctly' do
        stub_const('HTTPClientTool', Class.new(ADK::Tool))
        expect(HTTPClientTool.inferred_name).to eq(:http_client_tool)
      end
    end

    context 'with anonymous classes' do
      let(:tool_class) { Class.new(ADK::Tool) }

      it 'returns nil for anonymous classes' do
        expect(tool_class.inferred_name).to be_nil
      end
    end
  end

  describe 'cache invalidation' do
    let(:tool_class) { Class.new(ADK::Tool) }

    before do
      stub_const('CachedTool', tool_class)
    end

    it 'invalidates cache when description is updated' do
      tool_class.tool_description 'Initial description'
      expect(tool_class.tool_metadata[:description]).to eq('Initial description')

      tool_class.tool_description 'Updated description'
      expect(tool_class.tool_metadata[:description]).to eq('Updated description')
    end

    it 'invalidates cache when parameter is added' do
      expect(tool_class.tool_metadata[:parameters]).to be_empty

      tool_class.parameter :param1, type: :string
      expect(tool_class.tool_metadata[:parameters]).to have_key(:param1)

      tool_class.parameter :param2, type: :integer
      expect(tool_class.tool_metadata[:parameters]).to have_key(:param2)
    end

    it 'invalidates cache when explicit_tool_name is set' do
      # Initial state: inferred name
      expect(tool_class.tool_metadata[:name]).to eq(:cached_tool)

      tool_class.explicit_tool_name = :new_name
      expect(tool_class.tool_metadata[:name]).to eq(:new_name)
    end
  end

  describe 'precedence rules' do
    let(:tool_class) { Class.new(ADK::Tool) }

    before do
      stub_const('PrecedenceTool', tool_class)
    end

    it 'prefers explicit_tool_name over inferred name' do
      tool_class.explicit_tool_name = :explicit_name
      expect(tool_class.tool_metadata[:name]).to eq(:explicit_name)
    end

    it 'prefers explicit_tool_name over legacy define_metadata name' do
      # Simulate legacy define_metadata setting instance variable directly
      tool_class.instance_variable_set(:@tool_name, :legacy_name)
      tool_class.explicit_tool_name = :explicit_name

      expect(tool_class.tool_metadata[:name]).to eq(:explicit_name)
    end

    it 'prefers legacy define_metadata name over inferred name if explicit not set' do
      tool_class.instance_variable_set(:@tool_name, :legacy_name)
      # Ensure explicit name is nil
      tool_class.explicit_tool_name = nil

      expect(tool_class.tool_metadata[:name]).to eq(:legacy_name)
    end

    it 'prefers DSL description over legacy description' do
      tool_class.instance_variable_set(:@description, 'Legacy description')
      tool_class.tool_description 'DSL description'

      expect(tool_class.tool_metadata[:description]).to eq('DSL description')
    end

    it 'merges parameters when using both legacy and DSL methods' do
      # Because both methods use the same underlying instance variable @parameters_definition,
      # they effectively merge. This test documents that behavior.

      tool_class.instance_variable_set(:@parameters_definition, { legacy: { type: :string } })
      tool_class.parameter :dsl, type: :integer

      metadata = tool_class.tool_metadata
      expect(metadata[:parameters]).to have_key(:dsl)
      expect(metadata[:parameters]).to have_key(:legacy)
    end

    it 'falls back to legacy parameters if DSL parameters are empty' do
      # If we set the variable directly (simulating legacy), and don't call DSL methods
      tool_class.instance_variable_set(:@parameters_definition, { legacy: { type: :string } })

      metadata = tool_class.tool_metadata
      expect(metadata[:parameters]).to have_key(:legacy)
    end
  end
end
