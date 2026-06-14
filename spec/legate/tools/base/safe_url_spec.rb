# File: spec/legate/tools/base/safe_url_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'legate/tools/base/safe_url'

RSpec.describe Legate::Tools::Base::SafeUrl do
  describe '.resolve!' do
    it 'rejects non-http(s) schemes' do
      expect { described_class.resolve!('ftp://example.com/x') }
        .to raise_error(Legate::ToolArgumentError, /must use http or https/)
    end

    it 'rejects a malformed URL' do
      expect { described_class.resolve!('http://exa mple.com') }
        .to raise_error(Legate::ToolArgumentError)
    end

    context 'with literal restricted addresses' do
      {
        'loopback' => 'http://127.0.0.1/',
        'localhost' => 'http://localhost/',
        'private 10.x' => 'http://10.0.0.1/',
        'private 192.168.x' => 'http://192.168.1.1/admin',
        'cloud metadata' => 'http://169.254.169.254/latest/meta-data/',
        'this network 0.0.0.0/8' => 'http://0.0.0.0/',
        'CGNAT 100.64.0.0/10' => 'http://100.64.0.1/',
        'IPv6 loopback' => 'http://[::1]/'
      }.each do |label, url|
        it "blocks #{label}" do
          expect { described_class.resolve!(url) }
            .to raise_error(Legate::ToolArgumentError, /restricted network address|could not resolve/i)
        end
      end
    end

    it 'allows a public literal IP and returns the pinned IP' do
      uri, ip = described_class.resolve!('http://8.8.8.8/path')
      expect(uri.host).to eq('8.8.8.8')
      expect(ip).to eq('8.8.8.8')
    end

    it 'blocks a hostname that resolves to a private IP' do
      allow(Legate::Auth::UrlGuard).to receive(:resolved_ips).with('evil.test').and_return(['10.1.2.3'])
      expect { described_class.resolve!('http://evil.test/') }
        .to raise_error(Legate::ToolArgumentError, /restricted network address.*10\.1\.2\.3/)
    end

    it 'returns the first resolved IP for a public hostname' do
      allow(Legate::Auth::UrlGuard).to receive(:resolved_ips).with('safe.test').and_return(['93.184.216.34'])
      uri, ip = described_class.resolve!('https://safe.test/page')
      expect(uri.host).to eq('safe.test')
      expect(ip).to eq('93.184.216.34')
    end

    it 'fails closed when a host cannot be resolved' do
      allow(Legate::Auth::UrlGuard).to receive(:resolved_ips).with('nope.invalid').and_return([])
      expect { described_class.resolve!('http://nope.invalid/') }
        .to raise_error(Legate::ToolArgumentError, /Could not resolve host/)
    end

    it 'skips validation (no pin) under the development bypass' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('LEGATE_ALLOW_PRIVATE_TOOL_URLS').and_return('1')
      uri, ip = described_class.resolve!('http://localhost:3000/')
      expect(uri.host).to eq('localhost')
      expect(ip).to be_nil
    end
  end
end
