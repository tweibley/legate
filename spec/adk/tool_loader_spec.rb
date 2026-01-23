# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool_loader'
require 'tmpdir'

RSpec.describe ADK::ToolLoader do
  let(:logger_spy) { spy('Logger') }

  before do
    allow(ADK).to receive(:logger).and_return(logger_spy)
  end

  describe '.load_from_paths' do
    it 'does nothing when paths are nil' do
      described_class.load_from_paths(nil)
      expect(logger_spy).not_to have_received(:debug)
    end

    it 'does nothing when paths are empty' do
      described_class.load_from_paths([])
      expect(logger_spy).not_to have_received(:debug)
    end

    it 'logs a warning for non-existent directories' do
      described_class.load_from_paths(['/non/existent/path'])
      expect(logger_spy).to have_received(:warn).with(/does not exist/)
    end

    context 'with a valid directory' do
      around do |example|
        Dir.mktmpdir do |dir|
          @temp_dir = dir
          example.run
        end
      end

      it 'loads a valid ruby file' do
        file_path = File.join(@temp_dir, 'valid_tool.rb')
        # We define a dummy class to verify loading
        File.write(file_path, 'module ADK; class ValidToolLoaded; end; end')

        expect {
          described_class.load_from_paths([@temp_dir])
        }.not_to raise_error

        expect(defined?(ADK::ValidToolLoaded)).to be_truthy

        # Cleanup constant to avoid pollution
        ADK.send(:remove_const, :ValidToolLoaded) if defined?(ADK::ValidToolLoaded)
      end

      it 'logs error for syntax error' do
        file_path = File.join(@temp_dir, 'syntax_error.rb')
        File.write(file_path, 'def broken_method') # Missing end

        described_class.load_from_paths([@temp_dir])

        expect(logger_spy).to have_received(:error).with(%r{Failed to require/eval tool file.*SyntaxError})
      end

      it 'logs error for standard error during execution' do
        file_path = File.join(@temp_dir, 'runtime_error.rb')
        File.write(file_path, 'raise StandardError, "Boom"')

        described_class.load_from_paths([@temp_dir])

        expect(logger_spy).to have_received(:error).with(/Error encountered while requiring.*Boom/)
      end
    end
  end
end
