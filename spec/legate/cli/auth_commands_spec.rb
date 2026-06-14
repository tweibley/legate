# File: spec/legate/cli/auth_commands_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'legate/cli/auth_commands'

RSpec.describe Legate::CLI::AuthCommandHelpers do
  let(:helper_class) do
    Class.new do
      include Legate::CLI::AuthCommandHelpers
    end
  end
  let(:helper) { helper_class.new }

  describe '#mask_sensitive_value' do
    it 'masks long values' do
      expect(helper.mask_sensitive_value('abcdefghijklmnop')).to eq('abcd********mnop')
    end

    it 'fully masks short values' do
      expect(helper.mask_sensitive_value('short')).to eq('********')
    end

    it 'preserves ENV: references' do
      expect(helper.mask_sensitive_value('ENV:MY_SECRET')).to eq('ENV:MY_SECRET')
    end

    it 'handles nil values' do
      expect(helper.mask_sensitive_value(nil)).to eq('(not set)')
    end

    it 'handles empty strings' do
      expect(helper.mask_sensitive_value('')).to eq('(not set)')
    end
  end

  describe '#scheme_type_description' do
    it 'returns description for api_key' do
      expect(helper.scheme_type_description(:api_key)).to eq('API Key authentication')
    end

    it 'returns description for oauth2' do
      expect(helper.scheme_type_description(:oauth2)).to eq('OAuth 2.0 flow')
    end

    it 'returns description for http_bearer' do
      expect(helper.scheme_type_description(:http_bearer)).to eq('HTTP Bearer token')
    end

    it 'returns description for oidc' do
      expect(helper.scheme_type_description(:oidc)).to eq('OpenID Connect')
    end

    it 'returns string for unknown types' do
      expect(helper.scheme_type_description(:unknown)).to eq('unknown')
    end
  end

  describe '#credential_type_description' do
    it 'returns description for api_key' do
      expect(helper.credential_type_description(:api_key)).to eq('API Key')
    end

    it 'returns description for oauth2' do
      expect(helper.credential_type_description(:oauth2)).to eq('OAuth2 Client')
    end

    it 'returns description for basic' do
      expect(helper.credential_type_description(:basic)).to eq('Basic Auth')
    end
  end

  describe '#sensitive_field?' do
    it 'identifies api_key as sensitive' do
      expect(helper.sensitive_field?(:api_key)).to be true
    end

    it 'identifies client_secret as sensitive' do
      expect(helper.sensitive_field?(:client_secret)).to be true
    end

    it 'identifies bearer_token as sensitive' do
      expect(helper.sensitive_field?(:bearer_token)).to be true
    end

    it 'identifies password as sensitive' do
      expect(helper.sensitive_field?(:password)).to be true
    end

    it 'identifies client_id as not sensitive' do
      expect(helper.sensitive_field?(:client_id)).to be false
    end

    it 'identifies redirect_uri as not sensitive' do
      expect(helper.sensitive_field?(:redirect_uri)).to be false
    end
  end

  describe '#auth_manager' do
    it 'returns the auth manager singleton' do
      expect(helper.auth_manager).to eq(Legate::Auth::Manager.instance)
    end
  end
end

RSpec.describe Legate::CLI::AuthSchemeCommands do
  let(:auth_manager) { Legate::Auth::Manager.instance }
  let(:command) { described_class.new }

  before do
    auth_manager.instance_variable_set(:@schemes, {})
    auth_manager.instance_variable_set(:@credentials, {})
    auth_manager.instance_variable_set(:@url_mappings, [])
    auth_manager.send(:register_default_schemes)
  end

  describe '#list' do
    it 'lists authentication schemes' do
      output = capture_stdout { command.list }
      expect(output).to include('Authentication Schemes')
    end

    context 'when no schemes registered' do
      before { auth_manager.instance_variable_set(:@schemes, {}) }

      it 'displays a message' do
        output = capture_stdout { command.list }
        expect(output).to include('No authentication schemes registered')
      end
    end
  end

  describe '#show' do
    it 'shows scheme details' do
      output = capture_stdout { command.show('api_key') }
      expect(output).to include('Scheme: api_key')
    end
  end
end

RSpec.describe Legate::CLI::AuthCredentialCommands do
  let(:auth_manager) { Legate::Auth::Manager.instance }
  let(:command) { described_class.new }

  before do
    auth_manager.instance_variable_set(:@schemes, {})
    auth_manager.instance_variable_set(:@credentials, {})
    auth_manager.instance_variable_set(:@url_mappings, [])
    auth_manager.send(:register_default_schemes)
  end

  describe '#list' do
    context 'when no credentials registered' do
      it 'displays a message' do
        output = capture_stdout { command.list }
        expect(output).to include('No credentials registered')
      end
    end

    context 'when credentials exist' do
      before do
        cred = Legate::Auth::Credential.new(auth_type: :api_key, api_key: 'secret123secret')
        auth_manager.register_credential(cred, :test_cred, persist: false)
      end

      after {
        begin
          auth_manager.unregister_credential(:test_cred)
        rescue StandardError
          nil
        end
      }

      it 'lists credentials' do
        output = capture_stdout { command.list }
        expect(output).to include('test_cred')
      end
    end
  end
end

RSpec.describe Legate::CLI::AuthMappingCommands do
  let(:auth_manager) { Legate::Auth::Manager.instance }
  let(:command) { described_class.new }

  before do
    auth_manager.instance_variable_set(:@schemes, {})
    auth_manager.instance_variable_set(:@credentials, {})
    auth_manager.instance_variable_set(:@url_mappings, [])
    auth_manager.send(:register_default_schemes)
  end

  describe '#list' do
    context 'when no mappings registered' do
      it 'displays a message' do
        output = capture_stdout { command.list }
        expect(output).to include('No URL mappings registered')
      end
    end
  end
end

RSpec.describe Legate::CLI::AuthCommands do
  let(:auth_manager) { Legate::Auth::Manager.instance }
  let(:command) { described_class.new }

  before do
    auth_manager.instance_variable_set(:@schemes, {})
    auth_manager.instance_variable_set(:@credentials, {})
    auth_manager.instance_variable_set(:@url_mappings, [])
    auth_manager.send(:register_default_schemes)
  end

  describe '#status' do
    it 'displays authentication system status' do
      output = capture_stdout { command.status }
      expect(output).to include('Authentication System Status')
    end

    it 'shows scheme count' do
      output = capture_stdout { command.status }
      expect(output).to include('Schemes:')
    end

    it 'shows credential count' do
      output = capture_stdout { command.status }
      expect(output).to include('Credentials:')
    end

    it 'shows mapping count' do
      output = capture_stdout { command.status }
      expect(output).to include('Mappings:')
    end
  end
end

def capture_stdout
  original_stdout = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = original_stdout
end
