# frozen_string_literal: true

require 'spec_helper'
require 'legate/generators/tool_generator'

RSpec.describe Legate::Generators::ToolGenerator do
  let(:adapter) { instance_double(Legate::LLM::Gemini, available?: true) }

  before { allow(Legate::LLM).to receive(:build_adapter).and_return(adapter) }

  def generated_tool_code
    <<~RUBY
      require 'legate/tool'

      class WeatherTool < Legate::Tool
        tool_description 'Looks up the weather'
        parameter :city, type: :string, required: true

        private

        def perform_execution(params, context)
          { status: :success, result: "sunny in \#{params[:city]}" }
        end
      end
    RUBY
  end

  describe '.generate' do
    it 'returns code, a suggested name, and a tool type from the LLM output' do
      allow(adapter).to receive(:generate).and_return(generated_tool_code)
      result = described_class.generate(description: 'a weather tool')
      expect(result[:code]).to include('class WeatherTool < Legate::Tool')
      expect(result[:suggested_name]).to eq('weather_tool')
      expect(result[:tool_type]).to eq('simple')
    end

    it 'strips markdown fences from the response' do
      allow(adapter).to receive(:generate).and_return("```ruby\n#{generated_tool_code}```")
      result = described_class.generate(description: 'a weather tool')
      expect(result[:code]).to start_with("require 'legate/tool'")
      expect(result[:code]).not_to include('```')
    end

    it 'raises ApiKeyMissingError when the adapter is unavailable' do
      allow(adapter).to receive(:available?).and_return(false)
      expect { described_class.generate(description: 'x') }
        .to raise_error(described_class::ApiKeyMissingError)
    end

    it 'raises GenerationError on an empty response' do
      allow(adapter).to receive(:generate).and_return('   ')
      expect { described_class.generate(description: 'x') }
        .to raise_error(described_class::GenerationError, /empty response/)
    end

    it 'wraps an adapter error as ApiError' do
      allow(adapter).to receive(:generate).and_raise(StandardError, 'network down')
      expect { described_class.generate(description: 'x') }
        .to raise_error(described_class::ApiError, /communication error/)
    end

    it 'rejects generated code that the CodeValidator flags as unsafe' do
      allow(adapter).to receive(:generate).and_return("class Bad < Legate::Tool\n  system('rm -rf /')\nend")
      expect { described_class.generate(description: 'x') }
        .to raise_error(described_class::GenerationError)
    end

    it 'validates the description before calling the LLM' do
      expect(adapter).not_to receive(:generate)
      expect { described_class.generate(description: '') }
        .to raise_error(described_class::GenerationError, /Description is required/)
    end
  end
end
