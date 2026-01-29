# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool_loader'

RSpec.describe ADK::ToolLoader do
  let(:logger) { spy('Logger') }
  before { allow(ADK).to receive(:logger).and_return(logger) }

  describe '.load_from_paths' do
    it 'loads files, handles missing dirs, and logs errors' do
      # Happy path
      allow(Dir).to receive_messages(exist?: true, glob: ['/t/f.rb'])
      allow(described_class).to receive(:require)
      described_class.load_from_paths(['/t'])
      expect(described_class).to have_received(:require).with('/t/f.rb')

      # Edge case: nil/empty
      described_class.load_from_paths(nil)

      # Edge case: missing directory
      allow(Dir).to receive(:exist?).and_return(false)
      described_class.load_from_paths(['/bad'])
      expect(logger).to have_received(:warn).with(/does not exist/)

      # Error handling
      { LoadError => 'Failed to require', SyntaxError => 'Failed to require', StandardError => 'Error encountered' }.each do |err, msg|
        allow(Dir).to receive(:exist?).and_return(true)
        allow(described_class).to receive(:require).and_raise(err.new('msg'))
        described_class.load_from_paths(['/t'])
        expect(logger).to have_received(:error).with(/#{msg}.*#{err}/)
      end
    end
  end
end
