require 'spec_helper'
require_relative '../../../lib/legate/auth/schemes'
require_relative '../../../lib/legate/auth/manager'
require_relative '../../../lib/legate/auth/credential'

RSpec.describe 'Authentication Scheme Coverage', type: :integration do
  describe 'Scheme Factory Integration' do
    it 'can create all available scheme types through the factory' do
      expected_schemes = {
        api_key: Legate::Auth::Schemes::ApiKey,
        http_bearer: Legate::Auth::Schemes::HTTPBearer,
        oauth2: Legate::Auth::Schemes::OAuth2,
        oidc: Legate::Auth::Schemes::OpenIDConnect,
        openid_connect: Legate::Auth::Schemes::OpenIDConnect,
        service_account: Legate::Auth::Schemes::ServiceAccount,
        google_service_account: Legate::Auth::Schemes::GoogleServiceAccount
      }

      expected_schemes.each do |scheme_type, expected_class|
        scheme_options = case scheme_type
                         when :service_account
                           { token_url: 'https://example.com/token' }
                         when :google_service_account
                           { scopes: ['https://www.googleapis.com/auth/cloud-platform'] }
                         when :oauth2, :oidc, :openid_connect
                           { authorization_url: 'https://example.com/auth', token_url: 'https://example.com/token' }
                         else
                           {}
                         end

        scheme = Legate::Auth::Schemes.create(scheme_type, **scheme_options)
        expect(scheme).to be_a(expected_class),
                          "Expected #{scheme_type} to create #{expected_class}, got #{scheme.class}"
      end
    end
  end

  describe 'Authentication Manager Integration' do
    let(:manager) { Legate::Auth::Manager.instance }

    it 'registers all required schemes by default' do
      required_schemes = %i[api_key http_bearer oauth2 oidc service_account google_service_account]

      required_schemes.each do |scheme_type|
        scheme = manager.get_scheme(scheme_type)
        expect(scheme).not_to be_nil, "Scheme #{scheme_type} should be registered in manager"
        expect(scheme).to respond_to(:scheme_type)
        expect(scheme).to respond_to(:apply_to_request)
      end
    end
  end

  describe 'Credential Compatibility' do
    it 'creates valid credentials for all scheme types' do
      credential_configs = {
        api_key: { api_key: 'test-key' },
        http_bearer: { bearer_token: 'test-token' },
        oauth2: { client_id: 'test-id', client_secret: 'test-secret' },
        oidc: { client_id: 'test-id', client_secret: 'test-secret' },
        service_account: { service_account_key: '{"type":"service_account","client_email":"test@example.com","private_key":"test-key"}' },
        google_service_account: { service_account_key: '{"type":"service_account","client_email":"test@example.com","private_key":"test-key"}' }
      }

      credential_configs.each do |auth_type, attrs|
        expect {
          Legate::Auth::Credential.new(auth_type: auth_type, **attrs)
        }.not_to raise_error, "Should be able to create #{auth_type} credential"
      end
    end
  end

  describe 'Test File Coverage' do
    it 'has test files for all authentication schemes' do
      scheme_test_mapping = {
        api_key: ['api_key_spec.rb'],
        http_bearer: ['http_bearer_spec.rb'],
        oauth2: ['oauth2_spec.rb', 'oauth2_with_mock_spec.rb'],
        openid_connect: ['openid_connect_spec.rb', 'openid_connect_with_mock_spec.rb'], # covers both :oidc and :openid_connect
        service_account: ['service_account_spec.rb', 'service_account_with_mock_spec.rb'],
        google_service_account: ['google_service_account_spec.rb']
      }

      base_path = File.join(File.dirname(__FILE__), 'schemes')

      scheme_test_mapping.each do |scheme, test_files|
        test_files.each do |test_file|
          test_path = File.join(base_path, test_file)
          expect(File.exist?(test_path)).to be(true),
                                            "Missing test file: #{test_file} for scheme: #{scheme}"
        end
      end
    end
  end

  describe 'Scheme Interface Compliance' do
    let(:manager) { Legate::Auth::Manager.instance }

    it 'ensures all registered schemes implement required interface' do
      schemes_to_test = %i[api_key http_bearer oauth2 oidc service_account google_service_account]

      schemes_to_test.each do |scheme_type|
        scheme = manager.get_scheme(scheme_type)
        expect(scheme).not_to be_nil, "Scheme #{scheme_type} not registered"

        # Test required interface methods
        expect(scheme).to respond_to(:scheme_type), "#{scheme_type} missing scheme_type method"
        expect(scheme).to respond_to(:apply_to_request), "#{scheme_type} missing apply_to_request method"
        expect(scheme).to respond_to(:to_h), "#{scheme_type} missing to_h method"

        # Test scheme_type returns correct value
        expect(scheme.scheme_type).to be_a(Symbol), "#{scheme_type} scheme_type should return Symbol"

        # Test to_h returns hash
        expect(scheme.to_h).to be_a(Hash), "#{scheme_type} to_h should return Hash"
      end
    end
  end

  describe 'No Orphaned Schemes' do
    it 'does not have test files for removed/deprecated schemes' do
      # List of schemes that were removed during cleanup
      deprecated_schemes = %w[bearer.rb oidc.rb]

      lib_schemes_path = File.join(Dir.pwd, 'lib', 'legate', 'auth', 'schemes')

      deprecated_schemes.each do |deprecated_file|
        deprecated_path = File.join(lib_schemes_path, deprecated_file)
        expect(File.exist?(deprecated_path)).to be(false),
                                                "Deprecated scheme file still exists: #{deprecated_file}"
      end
    end

    it 'only loads schemes through the main schemes.rb file' do
      # Verify that all schemes are properly loaded through the main file
      expect { Legate::Auth::Schemes }.not_to raise_error

      # Verify factory method works for all known types
      valid_types = %i[api_key http_bearer oauth2 oidc openid_connect service_account google_service_account]

      valid_types.each do |type|
        expect {
          scheme_options = case type
                           when :service_account
                             { token_url: 'https://example.com/token' }
                           when :google_service_account
                             { scopes: ['https://www.googleapis.com/auth/cloud-platform'] }
                           when :oauth2, :oidc, :openid_connect
                             { authorization_url: 'https://example.com/auth', token_url: 'https://example.com/token' }
                           else
                             {}
                           end
          Legate::Auth::Schemes.create(type, **scheme_options)
        }.not_to raise_error, "Failed to create scheme of type: #{type}"
      end
    end
  end
end
