# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool_loader'

RSpec.describe ADK::ToolLoader do
  let(:logger_double) { spy('Logger') }

  before do
    allow(ADK).to receive(:logger).and_return(logger_double)
  end

  describe '.load_from_paths' do
    it 'does nothing if paths is nil or empty' do
      expect(Dir).not_to receive(:exist?)

      ADK::ToolLoader.load_from_paths(nil)
      ADK::ToolLoader.load_from_paths([])
    end

    it 'logs warning and skips if path does not exist' do
      path = '/invalid/path'
      allow(Dir).to receive(:exist?).with(anything).and_return(false)

      ADK::ToolLoader.load_from_paths([path])

      expect(logger_double).to have_received(:warn).with(/does not exist/)
    end

    it 'requires ruby files in the directory' do
      path = '/valid/path'
      file_path = '/valid/path/tool.rb'

      allow(Dir).to receive(:exist?).with(anything).and_return(true)
      allow(Dir).to receive(:glob).with(anything).and_return([file_path])

      # ToolLoader calls `require` on itself (module context) or implicitly
      expect(ADK::ToolLoader).to receive(:require).with(file_path)

      ADK::ToolLoader.load_from_paths([path])
    end

    it 'logs error if require raises LoadError' do
      path = '/valid/path'
      file_path = '/valid/path/bad_tool.rb'

      allow(Dir).to receive(:exist?).with(anything).and_return(true)
      allow(Dir).to receive(:glob).with(anything).and_return([file_path])

      allow(ADK::ToolLoader).to receive(:require).with(file_path).and_raise(LoadError.new('fail'))

      ADK::ToolLoader.load_from_paths([path])

      expect(logger_double).to have_received(:error).with(%r{Failed to require/eval tool file})
    end
  end
end
