# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/runner'
require 'adk/auth/schemes/oauth2'
require 'adk/auth/credential'
require 'adk/session_service/memory'

RSpec.describe ADK::Auth::Runner do
  let(:session_service) { ADK::SessionService::Memory.new }
  let(:token_store) { ADK::Auth::TokenStore.new(session_service) }
  let(:token_manager) { ADK::Auth::TokenManager.new(token_store) }
  let(:runner) { ADK::Auth::Runner.new(session_service: session_service, token_store: token_store, token_manager: token_manager) }
  
  let(:oauth2_scheme) do
    ADK::Auth::Schemes::OAuth2.new(
      authorization_url: 'https://example.com/auth',
      token_url: 'https://example.com/token',
      scopes: ['read', 'write']
    )
  end
  
  let(:credential) do
    ADK::Auth::Credential.new(
      auth_type: :oauth2,
      client_id: 'test-client-id',
      client_secret: 'test-client-secret'
    )
  end
  
  let(:exchanged_credential) do
    ADK::Auth::ExchangedCredential.new(
      auth_type: :oauth2,
      access_token: 'test-access-token',
      refresh_token: 'test-refresh-token',
      token_type: 'Bearer',
      expires_in: 3600,
      expires_at: Time.now + 3600
    )
  end
  
  describe '#run' do
    it 'runs a task within a fiber' do
      result = runner.run(-> { 'test result' })
      expect(result).to eq('test result')
    end
    
    it 'handles errors in the task' do
      expect do
        runner.run(-> { raise 'Test error' })
      end.to raise_error(RuntimeError, 'Test error')
    end
    
    context 'with authentication' do
      before do
        # Stub token manager to return nil (no cached token)
        allow(token_manager).to receive(:get_token).and_return(nil)
      end
      
      it 'handles authentication requests from the task' do
        # Create a mock context with an auth_session method
        context = Object.new
        
        # Set up a counter to track yield calls
        auth_request_counter = 0
        
        # Run the task with a handler that returns authentication responses
        result = runner.run(-> {
          # The first time we call auth_session, it should yield for authentication
          token = context.auth_session(oauth2_scheme, credential)
          # Return the token we got back
          token
        }, context) do |request|
          # Track the yield
          auth_request_counter += 1
          
          # Assert the request has expected structure
          expect(request[:action]).to eq(:authenticate)
          expect(request[:scheme]).to eq(oauth2_scheme)
          expect(request[:credential]).to eq(credential)
          
          # Create a mock auth response
          if auth_request_counter == 1
            # First yield provides the auth URL
            expect(runner.instance_variable_get(:@active_coordinators).length).to eq(1)
            request_id = runner.instance_variable_get(:@active_coordinators).keys.first
            
            # Simulate the user completing authentication
            response = { 'response_uri' => 'https://example.com/callback?code=test-code&state=test-state' }
            
            # Stub the exchange_token method to return a credential
            allow_any_instance_of(ADK::Auth::Schemes::OAuth2).to receive(:exchange_token).and_return(exchanged_credential)
            
            # Handle the response and return the credential
            result = runner.handle_auth_response(request_id, response)
            result[:credential]
          end
        end
        
        # Verify the result is the exchanged credential
        expect(result).to eq(exchanged_credential)
        expect(auth_request_counter).to eq(1)
      end
      
      it 'reuses cached tokens when available' do
        # Set up token manager to return a cached token
        allow(token_manager).to receive(:get_token).and_return(exchanged_credential)
        
        # Create a mock context with an auth_session method
        context = Object.new
        
        # Run the task that uses auth_session
        result = runner.run(-> {
          # This should not yield since we have a cached token
          token = context.auth_session(oauth2_scheme, credential)
          # Return the token
          token
        }, context) do |request|
          # This handler should never be called
          fail "Handler was called unexpectedly"
        end
        
        # Verify the result is the cached credential
        expect(result).to eq(exchanged_credential)
        expect(token_manager).to have_received(:get_token).with(oauth2_scheme, credential)
      end
    end
  end
  
  describe '#handle_auth_response' do
    it 'returns an error for invalid request IDs' do
      result = runner.handle_auth_response('invalid-id', {})
      expect(result[:status]).to eq(:error)
      expect(result[:error]).to include('No active authentication flow found')
    end
    
    it 'processes valid responses' do
      # Mock starting an authentication flow
      auth_coordinator = instance_double(ADK::Auth::Coordinators::OAuth2Coordinator)
      allow(auth_coordinator).to receive(:start).and_return({ request_id: 'test-id', scheme_type: :oauth2, auth_request: { type: 'authorization_request' } })
      allow(auth_coordinator).to receive(:resume).and_return(exchanged_credential)
      allow(auth_coordinator).to receive(:complete?).and_return(true)
      allow(auth_coordinator).to receive(:success?).and_return(true)
      
      # Manually add the coordinator to the active coordinators
      runner.instance_variable_get(:@active_coordinators)['test-id'] = auth_coordinator
      
      # Process the response
      result = runner.handle_auth_response('test-id', { 'response_uri' => 'https://example.com/callback?code=test' })
      
      # Verify the result
      expect(result[:status]).to eq(:completed)
      expect(result[:credential]).to eq(exchanged_credential)
      
      # Verify the coordinator was called
      expect(auth_coordinator).to have_received(:resume).with({ 'response_uri' => 'https://example.com/callback?code=test' })
    end
  end
  
  describe '#cancel_auth_flow' do
    it 'returns false for invalid request IDs' do
      result = runner.cancel_auth_flow('invalid-id')
      expect(result).to be false
    end
    
    it 'cancels valid authentication flows' do
      # Mock a coordinator
      auth_coordinator = instance_double(ADK::Auth::Coordinators::OAuth2Coordinator)
      allow(auth_coordinator).to receive(:cancel).and_return(true)
      
      # Manually add the coordinator to the active coordinators
      runner.instance_variable_get(:@active_coordinators)['test-id'] = auth_coordinator
      
      # Cancel the flow
      result = runner.cancel_auth_flow('test-id', 'User cancelled')
      
      # Verify the result
      expect(result).to be true
      
      # Verify the coordinator was called
      expect(auth_coordinator).to have_received(:cancel).with('User cancelled')
    end
  end
end 