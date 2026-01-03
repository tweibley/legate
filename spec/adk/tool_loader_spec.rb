# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool_loader'

RSpec.describe ADK::ToolLoader do
  describe '.load_from_paths' do
    let(:path) { 'lib/tools' }
    let(:abs_path) { '/app/lib/tools' }
    let(:file_path) { '/app/lib/tools/my_tool.rb' }
    let(:logger) { instance_double(Logger, debug: nil, warn: nil, error: nil) }

    before do
      allow(ADK).to receive(:logger).and_return(logger)
      allow(Dir).to receive(:pwd).and_return('/app')
      allow(File).to receive(:expand_path).with(path, '/app').and_return(abs_path)
      # Default: directory exists
      allow(Dir).to receive(:exist?).with(abs_path).and_return(true)
      allow(Dir).to receive(:glob).with("#{abs_path}/*.rb").and_return([file_path])
      # Mock require on the module itself to avoid loading real files
      allow(described_class).to receive(:require)
    end

    it 'requires ruby files found in the directory' do
      expect(described_class).to receive(:require).with(file_path)
      described_class.load_from_paths([path])
    end

    it 'skips non-existent directories' do
      allow(Dir).to receive(:exist?).with(abs_path).and_return(false)

      expect(described_class).not_to receive(:require)
      expect(logger).to receive(:warn).with(/Tool discovery path does not exist/)
      described_class.load_from_paths([path])
    end

    it 'handles nil paths' do
      expect(logger).not_to receive(:debug)
      described_class.load_from_paths(nil)
    end

    it 'handles empty paths' do
      expect(logger).not_to receive(:debug)
      described_class.load_from_paths([])
    end

    it 'handles LoadError gracefully' do
      allow(described_class).to receive(:require).with(file_path).and_raise(LoadError.new('fail'))
      expect(logger).to receive(:error).with(/Failed to require.*fail/)

      expect { described_class.load_from_paths([path]) }.not_to raise_error
    end

    it 'handles SyntaxError gracefully' do
      allow(described_class).to receive(:require).with(file_path).and_raise(SyntaxError.new('bad syntax'))
      expect(logger).to receive(:error).with(/Failed to require.*bad syntax/)

      expect { described_class.load_from_paths([path]) }.not_to raise_error
    end

    it 'handles StandardError gracefully' do
      allow(described_class).to receive(:require).with(file_path).and_raise(StandardError.new('oops'))
      expect(logger).to receive(:error).with(/Error encountered while requiring.*oops/)

      expect { described_class.load_from_paths([path]) }.not_to raise_error
    end
  end
end
