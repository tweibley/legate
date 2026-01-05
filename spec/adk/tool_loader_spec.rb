# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool_loader'

RSpec.describe ADK::ToolLoader do
  describe '.load_from_paths' do
    let(:logger) { instance_double(Logger, debug: nil, warn: nil, error: nil, info: nil) }

    before do
      allow(ADK).to receive(:logger).and_return(logger)
    end

    context 'when paths are nil' do
      it 'returns without doing anything' do
        # We expect no file system operations
        expect(Dir).not_to receive(:glob)
        described_class.load_from_paths(nil)
      end
    end

    context 'when paths are empty' do
      it 'returns without doing anything' do
        expect(Dir).not_to receive(:glob)
        described_class.load_from_paths([])
      end
    end

    context 'when a path exists' do
      let(:path) { '/valid/path' }
      let(:absolute_path) { '/valid/path' }
      let(:file_path) { '/valid/path/tool.rb' }

      before do
        allow(File).to receive(:expand_path).with(path, anything).and_return(absolute_path)
        allow(Dir).to receive(:exist?).with(absolute_path).and_return(true)
        allow(Dir).to receive(:glob).with(File.join(absolute_path, '*.rb')).and_return([file_path])
        allow(described_class).to receive(:require)
      end

      it 'requires ruby files in the directory' do
        described_class.load_from_paths([path])
        expect(described_class).to have_received(:require).with(file_path)
      end
    end

    context 'when a path does not exist' do
      let(:path) { '/invalid/path' }
      let(:absolute_path) { '/invalid/path' }

      before do
        allow(File).to receive(:expand_path).with(path, anything).and_return(absolute_path)
        allow(Dir).to receive(:exist?).with(absolute_path).and_return(false)
      end

      it 'logs a warning and skips' do
        described_class.load_from_paths([path])
        expect(logger).to have_received(:warn).with(/does not exist/)
        expect(Dir).not_to receive(:glob)
      end
    end

    context 'when requiring a file raises an error' do
      let(:path) { '/valid/path' }
      let(:absolute_path) { '/valid/path' }
      let(:file_path) { '/valid/path/broken_tool.rb' }

      before do
        allow(File).to receive(:expand_path).with(path, anything).and_return(absolute_path)
        allow(Dir).to receive(:exist?).with(absolute_path).and_return(true)
        allow(Dir).to receive(:glob).with(File.join(absolute_path, '*.rb')).and_return([file_path])
      end

      it 'logs error on LoadError' do
        allow(described_class).to receive(:require).with(file_path).and_raise(LoadError.new('cannot load'))
        described_class.load_from_paths([path])
        expect(logger).to have_received(:error).with(%r{Failed to require/eval tool file.*cannot load})
      end

      it 'logs error on SyntaxError' do
        allow(described_class).to receive(:require).with(file_path).and_raise(SyntaxError.new('unexpected end'))
        described_class.load_from_paths([path])
        expect(logger).to have_received(:error).with(%r{Failed to require/eval tool file.*unexpected end})
      end

      it 'logs error on StandardError' do
        allow(described_class).to receive(:require).with(file_path).and_raise(StandardError.new('something went wrong'))
        described_class.load_from_paths([path])
        expect(logger).to have_received(:error).with(%r{Error encountered while requiring/processing tool file.*something went wrong})
      end
    end
  end
end
