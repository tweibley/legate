# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Agent Authentication Integration' do
  describe 'AgentDefinition auth DSL' do
    let(:definition) do
      ADK::AgentDefinition.new.define do |a|
        a.name :auth_test_agent
        a.instruction 'Test agent with auth configuration'
        
        # Test auth DSL methods
        a.use_credential :google_maps_api
        a.use_credential :openai_key
        
        a.auth_mapping 'https://maps.googleapis.com/*', scheme: :api_key, credential: :google_maps_api
        a.auth_mapping(/api\.openai\.com/, scheme: :http_bearer, credential: :openai_key)
        
        a.auth_scheme :google_maps, :api_key
        a.auth_credential :google_maps, :google_maps_api
      end
    end
    
    it 'stores credential names' do
      expect(definition.auth_credential_names).to include(:google_maps_api)
      expect(definition.auth_credential_names).to include(:openai_key)
      expect(definition.auth_credential_names.size).to eq(2)
    end
    
    it 'stores URL mappings with string patterns' do
      string_mapping = definition.auth_url_mappings.find { |m| m[:pattern].is_a?(String) }
      expect(string_mapping).not_to be_nil
      expect(string_mapping[:pattern]).to eq('https://maps.googleapis.com/*')
      expect(string_mapping[:scheme_name]).to eq(:api_key)
      expect(string_mapping[:credential_name]).to eq(:google_maps_api)
    end
    
    it 'stores URL mappings with regexp patterns' do
      regexp_mapping = definition.auth_url_mappings.find { |m| m[:pattern].is_a?(Regexp) }
      expect(regexp_mapping).not_to be_nil
      expect(regexp_mapping[:pattern]).to eq(/api\.openai\.com/)
      expect(regexp_mapping[:scheme_name]).to eq(:http_bearer)
      expect(regexp_mapping[:credential_name]).to eq(:openai_key)
    end
    
    it 'stores scheme assignments' do
      expect(definition.auth_scheme_assignments[:google_maps]).to eq(:api_key)
    end
    
    it 'stores credential assignments' do
      expect(definition.auth_credential_assignments[:google_maps]).to eq(:google_maps_api)
    end
    
    context 'argument validation' do
      it 'requires credential name to be a Symbol' do
        expect {
          ADK::AgentDefinition.new.define do |a|
            a.name :test
            a.instruction 'test'
            a.use_credential 'string_name'
          end
        }.to raise_error(ArgumentError, /must be a Symbol/)
      end
      
      it 'requires auth_mapping pattern to be String or Regexp' do
        expect {
          ADK::AgentDefinition.new.define do |a|
            a.name :test
            a.instruction 'test'
            a.auth_mapping 123, scheme: :api_key, credential: :test
          end
        }.to raise_error(ArgumentError, /must be a String or Regexp/)
      end
      
      it 'requires auth_mapping scheme to be a Symbol' do
        expect {
          ADK::AgentDefinition.new.define do |a|
            a.name :test
            a.instruction 'test'
            a.auth_mapping 'https://example.com/*', scheme: 'api_key', credential: :test
          end
        }.to raise_error(ArgumentError, /Scheme must be a Symbol/)
      end
    end
  end
  
  describe 'AgentDefinition#to_h and .from_hash' do
    let(:original_definition) do
      ADK::AgentDefinition.new.define do |a|
        a.name :serialization_test
        a.instruction 'Test serialization'
        a.use_credential :test_cred
        a.auth_mapping 'https://api.test.com/*', scheme: :api_key, credential: :test_cred
        a.auth_mapping(/example\.com/, scheme: :http_bearer, credential: :test_cred)
        a.auth_scheme :test_service, :api_key
        a.auth_credential :test_service, :test_cred
      end
    end
    
    it 'serializes auth config to hash' do
      hash = original_definition.to_h
      
      expect(hash[:auth_credential_names]).to eq([:test_cred])
      expect(hash[:auth_url_mappings].length).to eq(2)
      expect(hash[:auth_scheme_assignments]).to eq({ 'test_service' => 'api_key' })
      expect(hash[:auth_credential_assignments]).to eq({ 'test_service' => 'test_cred' })
    end
    
    it 'deserializes auth config from hash' do
      hash = original_definition.to_h
      restored = ADK::AgentDefinition.from_hash(hash)
      
      expect(restored.auth_credential_names).to include(:test_cred)
      expect(restored.auth_url_mappings.length).to eq(2)
      expect(restored.auth_scheme_assignments[:test_service]).to eq(:api_key)
      expect(restored.auth_credential_assignments[:test_service]).to eq(:test_cred)
    end
    
    it 'restores regexp patterns from hash' do
      hash = original_definition.to_h
      restored = ADK::AgentDefinition.from_hash(hash)
      
      regexp_mapping = restored.auth_url_mappings.find { |m| m[:pattern].is_a?(Regexp) }
      expect(regexp_mapping).not_to be_nil
      expect(regexp_mapping[:pattern].source).to eq('example\\.com')
    end
  end
  
  describe 'Agent auth config initialization' do
    let(:definition) do
      ADK::AgentDefinition.new.define do |a|
        a.name :agent_auth_test
        a.instruction 'Test agent auth initialization'
        a.use_credential :my_api_key
        a.auth_mapping 'https://api.example.com/*', scheme: :api_key, credential: :my_api_key
      end
    end
    
    let(:session_service) do
      service = instance_double(ADK::SessionService::InMemory)
      allow(service).to receive(:get_session).and_return(nil)
      allow(service).to receive(:append_event).and_return(true)
      allow(service).to receive(:create_session).and_return(nil)
      service
    end
    
    before do
      allow(ADK::GlobalToolManager).to receive(:find_class).and_return(nil)
    end
    
    it 'loads auth config from definition' do
      agent = ADK::Agent.new(definition: definition, session_service: session_service)
      
      expect(agent.auth_credential_names).to include(:my_api_key)
      expect(agent.auth_url_mappings.length).to eq(1)
      expect(agent.auth_url_mappings.first[:scheme_name]).to eq(:api_key)
    end
  end
  
  describe 'ToolContext agent_auth_config' do
    let(:auth_config) do
      {
        credential_names: Set.new([:test_api_key]),
        url_mappings: [
          { pattern: 'https://api.test.com/*', scheme_name: :api_key, credential_name: :test_api_key }
        ],
        scheme_assignments: {},
        credential_assignments: {}
      }
    end
    
    let(:context) do
      ADK::ToolContext.new(
        session_id: 'test-session',
        user_id: 'test-user',
        app_name: 'test-agent',
        agent_auth_config: auth_config
      )
    end
    
    it 'stores agent_auth_config' do
      expect(context.agent_auth_config).to eq(auth_config)
    end
    
    it 'includes agent_auth_config in url mapping lookup' do
      auth_manager = instance_double(ADK::Auth::Manager)
      scheme = instance_double(ADK::Auth::Scheme)
      credential = instance_double(ADK::Auth::Credential)
      
      allow(ADK::Auth::Manager).to receive(:instance).and_return(auth_manager)
      allow(auth_manager).to receive(:get_scheme).with(:api_key).and_return(scheme)
      allow(auth_manager).to receive(:get_credential).with(:test_api_key).and_return(credential)
      
      result = context.find_agent_auth_for_url('https://api.test.com/v1/endpoint', auth_manager)
      
      expect(result).to eq([scheme, credential])
    end
    
    it 'returns nil when URL does not match any mapping' do
      auth_manager = instance_double(ADK::Auth::Manager)
      allow(ADK::Auth::Manager).to receive(:instance).and_return(auth_manager)
      
      result = context.find_agent_auth_for_url('https://other.api.com/endpoint', auth_manager)
      
      expect(result).to be_nil
    end
    
    context 'with regexp pattern' do
      let(:auth_config) do
        {
          credential_names: Set.new([:openai_key]),
          url_mappings: [
            { pattern: /api\.openai\.com/, scheme_name: :http_bearer, credential_name: :openai_key }
          ],
          scheme_assignments: {},
          credential_assignments: {}
        }
      end
      
      it 'matches regexp patterns' do
        auth_manager = instance_double(ADK::Auth::Manager)
        scheme = instance_double(ADK::Auth::Scheme)
        credential = instance_double(ADK::Auth::Credential)
        
        allow(ADK::Auth::Manager).to receive(:instance).and_return(auth_manager)
        allow(auth_manager).to receive(:get_scheme).with(:http_bearer).and_return(scheme)
        allow(auth_manager).to receive(:get_credential).with(:openai_key).and_return(credential)
        
        result = context.find_agent_auth_for_url('https://api.openai.com/v1/chat/completions', auth_manager)
        
        expect(result).to eq([scheme, credential])
      end
    end
  end
end

