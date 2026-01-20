# frozen_string_literal: true

require 'spec_helper'
require 'adk'

RSpec.describe ADK do
  describe '.redis_client' do
    let(:default_options) { { url: 'redis://localhost:6379/0' } }
    let(:custom_options) { { url: 'redis://custom:6379/9', db: 2 } }

    before do
      # Reset redis_options before each test
      ADK.instance_variable_set(:@redis_options, default_options)
    end

    it 'creates a Redis client with default options' do
      expect(Redis).to receive(:new).with(default_options)
      ADK.redis_client
    end

    it 'merges custom options with default options' do
      expected_options = default_options.merge(custom_options)
      expect(Redis).to receive(:new).with(expected_options)
      ADK.redis_client(custom_options)
    end

    context 'when redis_options is nil' do
      before do
        ADK.instance_variable_set(:@redis_options, nil)
      end

      it 'does not crash and uses empty defaults' do
        expect(Redis).to receive(:new).with({})
        ADK.redis_client
      end

      it 'merges custom options correctly even when defaults are nil' do
        expect(Redis).to receive(:new).with(custom_options)
        ADK.redis_client(custom_options)
      end
    end
  end
end
