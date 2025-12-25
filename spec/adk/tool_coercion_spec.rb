# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ADK::Tool, 'Coercion' do
  let(:tool) do
    Class.new(ADK::Tool) do
      self.explicit_tool_name = :test
      tool_description 'Test'
      parameter :i, type: :integer; parameter :f, type: :float
      parameter :b, type: :boolean; parameter :a, type: :array
      parameter :h, type: :hash
      def perform_execution(*); end
    end.new
  end

  def c(p) = tool.validate_and_coerce_params(p)

  it 'coerces numeric types' do
    expect(c(i: '42')).to eq(i: 42)
    expect(c(i: 42.9)).to eq(i: 42)
    expect(c(f: '42.5')).to eq(f: 42.5)
    expect { c(i: 'x') }.to raise_error(ADK::ToolArgumentError)
  end

  it 'coerces booleans' do
    %w[true t yes 1].each { |v| expect(c(b: v)).to eq(b: true) }
    %w[false f no 0].each { |v| expect(c(b: v)).to eq(b: false) }
    expect { c(b: 2) }.to raise_error(ADK::ToolArgumentError)
  end

  it 'coerces JSON structures' do
    expect(c(a: '[1,2]')).to eq(a: [1, 2])
    expect(c(h: '{"x":1}')).to eq(h: { 'x' => 1 })
    expect { c(a: 'bad') }.to raise_error(ADK::ToolArgumentError)
  end
end
