# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ADK::ToolLoader do
  let(:logger) { instance_spy(Logger) }
  before { allow(ADK).to receive(:logger).and_return(logger) }

  it 'skips nil/empty/missing paths' do
    allow(Dir).to receive(:exist?).and_return(false)
    [nil, [], ['/bad']].each { |p| described_class.load_from_paths(p) }
    expect(logger).not_to have_received(:debug).with(/Attempting to load/)
    expect(logger).to have_received(:warn).with(/does not exist/).once
  end

  context 'with valid files' do
    let(:file) { '/p/tool.rb' }
    before do
      allow(Dir).to receive_messages(exist?: true, glob: [file])
    end

    it 'loads file and catches errors' do
      expect(described_class).to receive(:require).with(file)
      described_class.load_from_paths(['/p'])

      [LoadError, SyntaxError, StandardError].each do |err|
        allow(described_class).to receive(:require).and_raise(err)
        expect { described_class.load_from_paths(['/p']) }.not_to raise_error
        expect(logger).to have_received(:error).with(/#{err}/)
      end
    end
  end
end
