# frozen_string_literal: true

require 'spec_helper'
require 'legate/auth/url_guard'

RSpec.describe Legate::Auth::UrlGuard do
  describe '.validate!' do
    around do |example|
      original = ENV['LEGATE_ALLOW_PRIVATE_AUTH_URLS']
      ENV.delete('LEGATE_ALLOW_PRIVATE_AUTH_URLS')
      example.run
      ENV['LEGATE_ALLOW_PRIVATE_AUTH_URLS'] = original
    end

    it 'allows a public https URL (literal public IP, no DNS)' do
      expect { described_class.validate!('https://8.8.8.8/path') }.not_to raise_error
    end

    it 'rejects loopback addresses' do
      expect { described_class.validate!('http://127.0.0.1/') }
        .to raise_error(Legate::Auth::Error, /restricted network address/)
    end

    it 'rejects the cloud metadata link-local address' do
      expect { described_class.validate!('http://169.254.169.254/latest/meta-data/') }
        .to raise_error(Legate::Auth::Error, /restricted network address/)
    end

    it 'rejects RFC1918 private addresses' do
      expect { described_class.validate!('http://10.0.0.5/') }
        .to raise_error(Legate::Auth::Error, /restricted network address/)
      expect { described_class.validate!('http://192.168.1.1/') }
        .to raise_error(Legate::Auth::Error, /restricted network address/)
    end

    it 'rejects CGNAT (100.64.0.0/10) addresses' do
      expect { described_class.validate!('http://100.64.0.1/') }
        .to raise_error(Legate::Auth::Error, /restricted network address/)
    end

    it 'rejects 0.0.0.0/8 addresses' do
      expect { described_class.validate!('http://0.0.0.0/') }
        .to raise_error(Legate::Auth::Error, /restricted network address/)
    end

    it 'rejects non-http(s) schemes' do
      expect { described_class.validate!('file:///etc/passwd') }
        .to raise_error(Legate::Auth::Error, /http or https/)
      expect { described_class.validate!('gopher://127.0.0.1/') }
        .to raise_error(Legate::Auth::Error, /http or https/)
    end

    it 'resolves hostnames before deciding (blocks a name that maps to loopback)' do
      allow(Resolv).to receive(:getaddresses).with('evil.example').and_return(['127.0.0.1'])
      expect { described_class.validate!('http://evil.example/') }
        .to raise_error(Legate::Auth::Error, /restricted network address/)
    end

    it 'fails closed when a host cannot be resolved (no silent skip)' do
      allow(Resolv).to receive(:getaddresses).with('nx.example').and_return([])
      expect { described_class.validate!('http://nx.example/') }
        .to raise_error(Legate::Auth::Error, /could not resolve host/)
    end

    it 'blocks IPv4-mapped IPv6 forms of restricted addresses' do
      expect { described_class.validate!('http://[::ffff:127.0.0.1]/') }
        .to raise_error(Legate::Auth::Error, /restricted network address/)
      allow(Resolv).to receive(:getaddresses).with('evil6.example').and_return(['::ffff:169.254.169.254'])
      expect { described_class.validate!('http://evil6.example/') }
        .to raise_error(Legate::Auth::Error, /restricted network address/)
    end

    it 'is bypassable for development via LEGATE_ALLOW_PRIVATE_AUTH_URLS' do
      ENV['LEGATE_ALLOW_PRIVATE_AUTH_URLS'] = '1'
      expect { described_class.validate!('http://127.0.0.1/') }.not_to raise_error
    end
  end
end
