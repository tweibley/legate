# frozen_string_literal: true

require 'spec_helper'
require 'adk/activity_log'
require 'timecop'

RSpec.describe ADK::ActivityLog do
  let(:activity_log) { described_class.instance }

  before do
    activity_log.clear
  end

  after do
    activity_log.clear
  end

  describe '.instance' do
    it 'returns the singleton instance' do
      expect(described_class.instance).to be_a(described_class)
      expect(described_class.instance).to equal(described_class.instance)
    end
  end

  describe '#log' do
    it 'adds an event to the log' do
      activity_log.log(:test_event, { foo: 'bar' })
      events = activity_log.recent
      expect(events.size).to eq(1)
      expect(events.first[:type]).to eq(:test_event)
      expect(events.first[:details]).to eq({ foo: 'bar' })
    end

    it 'adds a timestamp to the event' do
      Timecop.freeze do
        activity_log.log(:test_event)
        expect(activity_log.recent.first[:timestamp]).to be_within(1).of(Time.now.utc)
      end
    end

    it 'limits the number of events stored' do
      max_events = ADK::ActivityLog::MAX_EVENTS
      (max_events + 10).times do |i|
        activity_log.log(:event, { index: i })
      end

      expect(activity_log.recent(100).size).to eq(max_events)
      # Should keep the most recent ones
      expect(activity_log.recent(1).first[:details][:index]).to eq(max_events + 9)
    end

    it 'is thread-safe' do
      threads = []
      100.times do |i|
        threads << Thread.new do
          activity_log.log(:event, { index: i })
        end
      end
      threads.each(&:join)

      expect(activity_log.recent(100).size).to eq([100, ADK::ActivityLog::MAX_EVENTS].min)
    end
  end

  describe '#recent' do
    before do
      10.times { |i| activity_log.log(:event, { index: i }) }
    end

    it 'returns the specified number of recent events' do
      events = activity_log.recent(5)
      expect(events.size).to eq(5)
      # Check order (most recent first)
      expect(events.first[:details][:index]).to eq(9)
      expect(events.last[:details][:index]).to eq(5)
    end

    it 'returns all events if limit is greater than count' do
      events = activity_log.recent(20)
      expect(events.size).to eq(10)
    end
  end

  describe '#clear' do
    it 'removes all events' do
      activity_log.log(:test)
      expect(activity_log.recent).not_to be_empty
      activity_log.clear
      expect(activity_log.recent).to be_empty
    end
  end

  describe 'Class methods delegation' do
    it 'delegates log to instance' do
      expect(activity_log).to receive(:log).with(:test, {})
      described_class.log(:test)
    end

    it 'delegates recent to instance' do
      expect(activity_log).to receive(:recent).with(5)
      described_class.recent(5)
    end

    it 'delegates clear to instance' do
      # We need to make sure we are spying on the actual instance used
      instance = described_class.instance
      expect(instance).to receive(:clear).at_least(:once)
      described_class.clear
    end
  end
end
