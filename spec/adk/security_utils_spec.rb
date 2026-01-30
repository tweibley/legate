# frozen_string_literal: true

require 'rspec'
require 'adk/security_utils'

RSpec.describe ADK::SecurityUtils do
  describe '.validate_url_security' do
    it 'allows public domains' do
      expect { described_class.validate_url_security('example.com') }.not_to raise_error
      expect { described_class.validate_url_security('google.com') }.not_to raise_error
    end

    it 'blocks localhost' do
      expect { described_class.validate_url_security('localhost') }
        .to raise_error(ADK::SecurityError, /Blocked access to restricted network address/)
    end

    it 'blocks 127.0.0.1' do
      expect { described_class.validate_url_security('127.0.0.1') }
        .to raise_error(ADK::SecurityError, /Blocked access to restricted network address/)
    end

    it 'blocks 0.0.0.0' do
      expect { described_class.validate_url_security('0.0.0.0') }
        .to raise_error(ADK::SecurityError, /Blocked access to restricted network address/)
    end

    it 'blocks private IPs (10.x.x.x)' do
      expect { described_class.validate_url_security('10.0.0.1') }
        .to raise_error(ADK::SecurityError, /Blocked access to restricted network address/)
    end

    it 'blocks private IPs (192.168.x.x)' do
      expect { described_class.validate_url_security('192.168.1.1') }
        .to raise_error(ADK::SecurityError, /Blocked access to restricted network address/)
    end

    it 'blocks private IPs (172.16.x.x)' do
      expect { described_class.validate_url_security('172.16.0.1') }
        .to raise_error(ADK::SecurityError, /Blocked access to restricted network address/)
    end

    it 'blocks link-local IPs (169.254.x.x)' do
      expect { described_class.validate_url_security('169.254.169.254') }
        .to raise_error(ADK::SecurityError, /Blocked access to restricted network address/)
    end

    it 'raises error for unresolvable hostnames' do
      expect { described_class.validate_url_security('non-existent-domain.invalid') }
        .to raise_error(ADK::SecurityError, /Could not resolve hostname/)
    end
  end
end
