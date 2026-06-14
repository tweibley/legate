# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legate/generators/runtime_tool_loader'

RSpec.describe Legate::Generators::RuntimeToolLoader do
  let(:tmp_tools_dir) { Dir.mktmpdir('legate-tools') }

  before do
    allow(Legate.config).to receive(:allow_runtime_tool_load).and_return(true)
    allow(described_class).to receive(:tools_dir).and_return(tmp_tools_dir)
  end

  after { FileUtils.remove_entry(tmp_tools_dir) if File.directory?(tmp_tools_dir) }

  def tool_source(class_name: 'SpecReverseTool', register: true)
    src = <<~RUBY
      require 'legate/tool'
      class #{class_name} < Legate::Tool
        tool_description 'reverses text'
        parameter :text, type: :string, required: true
        private
        def perform_execution(params, _context)
          { status: :success, result: params[:text].to_s.reverse }
        end
      end
    RUBY
    src += "Legate::GlobalToolManager.register_tool(#{class_name})\n" if register
    src
  end

  describe '.enabled?' do
    it 'reflects the config flag' do
      allow(Legate.config).to receive(:allow_runtime_tool_load).and_return(false)
      expect(described_class.enabled?).to be false
    end
  end

  describe '.load_source!' do
    it 'writes tools/<name>.rb, loads it, and registers the tool' do
      result = described_class.load_source!(tool_source, suggested_name: 'Spec Reverse')
      expect(result[:ok]).to be true
      expect(result[:tool_name]).to eq('spec_reverse_tool')
      expect(File).to exist(File.join(tmp_tools_dir, 'spec_reverse.rb'))
      expect(Legate::GlobalToolManager.registered_tool_names).to include(:spec_reverse_tool)
    end

    it 'returns an error (and does nothing) when disabled' do
      allow(Legate.config).to receive(:allow_runtime_tool_load).and_return(false)
      result = described_class.load_source!(tool_source, suggested_name: 'spec_reverse')
      expect(result[:ok]).to be false
      expect(Dir.empty?(tmp_tools_dir)).to be true
    end

    it 'rejects code the CodeValidator flags as unsafe' do
      result = described_class.load_source!("system('rm -rf /')", suggested_name: 'evil')
      expect(result[:ok]).to be false
      expect(result[:error]).to match(/dangerous/i)
    end

    it 'reports when the code registers no tool' do
      result = described_class.load_source!(tool_source(class_name: 'SpecNoRegister', register: false), suggested_name: 'spec_no_register')
      expect(result[:ok]).to be false
      expect(result[:error]).to match(/did not register/i)
    end

    it 'never raises — a tool that errors at load time returns an error result' do
      bad = "raise 'boom during load'\n"
      expect { @r = described_class.load_source!(bad, suggested_name: 'boom') }.not_to raise_error
      expect(@r[:ok]).to be false
      expect(@r[:error]).to match(/boom during load/)
    end
  end
end

RSpec.describe Legate::Configuration do
  it 'defaults allow_runtime_tool_load ON outside production and OFF in production' do
    original = ENV['RACK_ENV']
    ENV['RACK_ENV'] = 'development'
    expect(described_class.new.allow_runtime_tool_load).to be true
    ENV['RACK_ENV'] = 'production'
    expect(described_class.new.allow_runtime_tool_load).to be false
  ensure
    ENV['RACK_ENV'] = original
  end
end
