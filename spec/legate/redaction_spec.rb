# File: spec/legate/redaction_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'legate/redaction'

RSpec.describe Legate::Redaction do
  describe '.redact' do
    it 'redacts a Gemini-style ?key= query parameter' do
      url = 'POST https://generativelanguage.googleapis.com/v1beta/models/m:generateContent?key=AIzaSyABCDEFGHIJ1234567890'
      result = described_class.redact(url)
      expect(result).not_to include('AIzaSyABCDEFGHIJ1234567890')
      expect(result).to include('key=[REDACTED]')
    end

    it 'redacts api_key / access_token / token params' do
      expect(described_class.redact('x?api_key=secret123456')).to include('[REDACTED]')
      expect(described_class.redact('x&access_token=secret123456')).to include('[REDACTED]')
      expect(described_class.redact('x?token=secret123456')).to include('[REDACTED]')
    end

    it 'redacts a bearer token' do
      expect(described_class.redact('Authorization: Bearer abc.def.ghijklmnop'))
        .to eq('Authorization: Bearer [REDACTED]')
    end

    it 'redacts a bare Google API key by prefix' do
      expect(described_class.redact('leaked AIzaSyABCDEFGHIJ1234567890 here'))
        .to eq('leaked [REDACTED] here')
    end

    it 'leaves non-secret text untouched' do
      expect(described_class.redact('the server responded with status 404')).to eq('the server responded with status 404')
    end

    it 'stringifies non-string input' do
      expect(described_class.redact(nil)).to eq('')
      expect(described_class.redact(404)).to eq('404')
    end
  end
end
