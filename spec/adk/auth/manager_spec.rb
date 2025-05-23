# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/manager'
require 'adk/auth/credential'

RSpec.describe ADK::Auth::Manager do
  # Use a fresh instance for each test to avoid singleton interference
  before(:each) do
    # Reset the Singleton pattern to get a fresh instance for each test
    ADK::Auth::Manager.instance_variable_set(:@singleton__instance__, nil)
  end
  
  let(:manager) { ADK::Auth::Manager.instance }
  
  let(:api_key_credential) do
    ADK::Auth::Credential.new(
      auth_type: :api_key,
      api_key: 'test-api-key-123'
    )
  end
  
  let(:oauth2_credential) do
    ADK::Auth::Credential.new(
      auth_type: :oauth2,
      client_id: 'client-id-123',
      client_secret: 'client-secret-456',
      redirect_uri: 'https://example.com/callback'
    )
  end
  
  describe '#initialize' do
    it 'registers default built-in schemes' do
      expect(manager.get_scheme(:api_key)).to be_a(ADK::Auth::Schemes::ApiKey)
      expect(manager.get_scheme(:http_bearer)).to be_a(ADK::Auth::Schemes::HTTPBearer)
      expect(manager.get_scheme(:oauth2)).to be_a(ADK::Auth::Schemes::OAuth2)
      expect(manager.get_scheme(:oidc)).to be_a(ADK::Auth::Schemes::OIDC)
      expect(manager.get_scheme(:service_account)).to be_a(ADK::Auth::Schemes::ServiceAccount)
    end
  end
  
  describe '#register_scheme' do
    it 'registers a scheme with a given name' do
      scheme = ADK::Auth::Schemes::ApiKey.new
      result = manager.register_scheme(scheme, :custom_scheme)
      
      expect(result).to eq(:custom_scheme)
      expect(manager.get_scheme(:custom_scheme)).to eq(scheme)
    end
    
    it 'uses scheme type as name if not provided' do
      scheme = ADK::Auth::Schemes::ApiKey.new
      allow(scheme).to receive(:scheme_type).and_return(:custom_type)
      
      result = manager.register_scheme(scheme)
      
      expect(result).to eq(:custom_type)
      expect(manager.get_scheme(:custom_type)).to eq(scheme)
    end
    
    it 'raises an error if scheme is not an ADK::Auth::Scheme' do
      expect {
        manager.register_scheme('not a scheme')
      }.to raise_error(ArgumentError, /Scheme must be an ADK::Auth::Scheme/)
    end
  end
  
  describe '#register_credential' do
    it 'registers a credential with a given name' do
      result = manager.register_credential(api_key_credential, :my_api_key)
      
      expect(result).to eq(:my_api_key)
      expect(manager.get_credential(:my_api_key)).to eq(api_key_credential)
    end
    
    it 'raises an error if credential is not an ADK::Auth::Credential' do
      expect {
        manager.register_credential('not a credential', :test)
      }.to raise_error(ArgumentError, /Credential must be an ADK::Auth::Credential/)
    end
    
    it 'raises an error if name is nil' do
      expect {
        manager.register_credential(api_key_credential, nil)
      }.to raise_error(ArgumentError, /Name must be provided/)
    end
  end
  
  describe '#register_url_mapping' do
    before do
      manager.register_credential(api_key_credential, :my_api_key)
    end
    
    it 'registers a URL pattern to a scheme and credential' do
      manager.register_url_mapping('api.example.com', :api_key, :my_api_key)
      
      # Use find_scheme_and_credential to test the mapping
      scheme, credential = manager.find_scheme_and_credential(url: 'https://api.example.com/v1/data')
      expect(scheme).to be_a(ADK::Auth::Schemes::ApiKey)
      expect(credential).to eq(api_key_credential)
    end
    
    it 'supports regex patterns' do
      manager.register_url_mapping(/api\.example\.com\/v\d+/, :api_key, :my_api_key)
      
      # Use find_scheme_and_credential to test the mapping
      scheme, credential = manager.find_scheme_and_credential(url: 'https://api.example.com/v2/data')
      expect(scheme).to be_a(ADK::Auth::Schemes::ApiKey)
      expect(credential).to eq(api_key_credential)
    end
    
    it 'raises an error if scheme does not exist' do
      expect {
        manager.register_url_mapping('api.example.com', :nonexistent_scheme, :my_api_key)
      }.to raise_error(ArgumentError, /Unknown scheme/)
    end
    
    it 'raises an error if credential does not exist' do
      expect {
        manager.register_url_mapping('api.example.com', :api_key, :nonexistent_credential)
      }.to raise_error(ArgumentError, /Unknown credential/)
    end
  end
  
  describe '#find_scheme_and_credential' do
    before do
      manager.register_credential(api_key_credential, :my_api_key)
      manager.register_credential(oauth2_credential, :my_oauth)
      manager.register_url_mapping('api.example.com', :api_key, :my_api_key)
      manager.register_url_mapping('auth.example.com', :oauth2, :my_oauth)
    end
    
    it 'finds scheme and credential based on URL' do
      result = manager.find_scheme_and_credential(url: 'https://api.example.com/v1/data')
      expect(result[0]).to be_a(ADK::Auth::Schemes::ApiKey)
      expect(result[1]).to eq(api_key_credential)
    end
    
    it 'finds scheme and credential based on credential name' do
      result = manager.find_scheme_and_credential(credential_name: :my_api_key)
      expect(result[0]).to be_a(ADK::Auth::Schemes::ApiKey)
      expect(result[1]).to eq(api_key_credential)
    end
    
    it 'finds scheme and credential based on scheme type' do
      result = manager.find_scheme_and_credential(scheme_type: :oauth2)
      expect(result[0]).to be_a(ADK::Auth::Schemes::OAuth2)
      expect(result[1]).to eq(oauth2_credential)
    end
    
    it 'combines filters to narrow search' do
      result = manager.find_scheme_and_credential(
        url: 'https://api.example.com/v1/data',
        scheme_type: :api_key
      )
      expect(result[0]).to be_a(ADK::Auth::Schemes::ApiKey)
      expect(result[1]).to eq(api_key_credential)
    end
    
    it 'returns nil when no matching scheme and credential found' do
      result = manager.find_scheme_and_credential(url: 'https://unknown.example.com')
      expect(result).to be_nil
    end
    
    it 'returns nil when scheme type filter does not match URL mapping' do
      result = manager.find_scheme_and_credential(
        url: 'https://api.example.com/v1/data',
        scheme_type: :oauth2
      )
      expect(result).to be_nil
    end
  end
end 