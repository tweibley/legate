# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool_loader'

RSpec.describe ADK::ToolLoader do
  describe '.load_from_paths' do
    let(:paths) { ['/tmp/tools'] }
    let(:logger) { instance_double(Logger, debug: nil, warn: nil, error: nil) }
    let(:absolute_path) { '/tmp/tools' }
    let(:tool_file) { '/tmp/tools/my_tool.rb' }

    before do
      allow(ADK).to receive(:logger).and_return(logger)
      allow(File).to receive(:expand_path).and_return(absolute_path)
      allow(Dir).to receive(:exist?).and_return(false)
      allow(Dir).to receive(:glob).and_return([])
      # We need to stub require to avoid actually loading files
      allow(described_class).to receive(:require)
    end

    context 'when paths are nil' do
      it 'does nothing' do
        described_class.load_from_paths(nil)
        expect(Dir).not_to have_received(:exist?)
      end
    end

    context 'when paths are empty' do
      it 'does nothing' do
        described_class.load_from_paths([])
        expect(Dir).not_to have_received(:exist?)
      end
    end

    context 'when a path does not exist' do
      before do
        allow(Dir).to receive(:exist?).with(absolute_path).and_return(false)
      end

      it 'logs a warning and skips it' do
        described_class.load_from_paths(paths)
        expect(logger).to have_received(:warn).with(/Tool discovery path does not exist/)
        expect(Dir).not_to have_received(:glob)
      end
    end

    context 'when a path exists' do
      before do
        allow(Dir).to receive(:exist?).with(absolute_path).and_return(true)
      end

      context 'with no ruby files' do
        it 'logs debug messages but does not require anything' do
          described_class.load_from_paths(paths)
          expect(logger).to have_received(:debug).with(/Starting tool discovery/)
          expect(logger).to have_received(:debug).with(/Finished tool discovery/)
          expect(described_class).not_to have_received(:require)
        end
      end

      context 'with ruby files' do
        before do
          allow(Dir).to receive(:glob).with(File.join(absolute_path, '*.rb')).and_return([tool_file])
        end

        it 'requires the file' do
          described_class.load_from_paths(paths)
          expect(described_class).to have_received(:require).with(tool_file)
        end

        it 'logs success debug message' do
          described_class.load_from_paths(paths)
          expect(logger).to have_received(:debug).with(/Successfully required/)
        end

        context 'when require raises LoadError' do
          before do
            allow(described_class).to receive(:require).with(tool_file).and_raise(LoadError.new('cannot load'))
          end

          it 'logs an error and continues' do
            described_class.load_from_paths(paths)
            expect(logger).to have_received(:error).with(%r{Failed to require/eval tool file.*LoadError})
          end
        end

        context 'when require raises SyntaxError' do
          before do
            allow(described_class).to receive(:require).with(tool_file).and_raise(SyntaxError.new('bad syntax'))
          end

          it 'logs an error and continues' do
            described_class.load_from_paths(paths)
            expect(logger).to have_received(:error).with(%r{Failed to require/eval tool file.*SyntaxError})
          end
        end

        context 'when require raises StandardError' do
          before do
            allow(described_class).to receive(:require).with(tool_file).and_raise(StandardError.new('oops'))
          end

          it 'logs an error and continues' do
            described_class.load_from_paths(paths)
            expect(logger).to have_received(:error).with(%r{Error encountered while requiring/processing tool file.*StandardError})
          end
        end
      end
    end
  end
end
