# File: spec/legate/session_service/base_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'legate/session_service/base' # Make sure the path is correct

RSpec.describe Legate::SessionService::Base do
  subject(:base_service) { described_class.new }

  describe '#persistent?' do
    it 'returns false by default' do
      expect(base_service.persistent?).to be false
    end
  end

  describe '#save_scoped_state' do
    it 'raises NotImplementedError' do
      expect { base_service.save_scoped_state('user', 'key', 'value') }.to raise_error(NotImplementedError)
    end
  end

  describe '#load_scoped_state' do
    it 'raises NotImplementedError' do
      expect { base_service.load_scoped_state('user', 'key') }.to raise_error(NotImplementedError)
    end
  end

  describe '#clear_scoped_state' do
    it 'raises NotImplementedError' do
      expect { base_service.clear_scoped_state('user', 'key') }.to raise_error(NotImplementedError)
    end
  end
end
