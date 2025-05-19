# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/runner'
require 'adk/auth/schemes/oauth2'
require 'adk/auth/credential'
require 'adk/session_service/in_memory'

RSpec.describe ADK::Auth::Runner do
  let(:session_service) { ADK::SessionService::InMemory.new }
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
      # Expose private method for testing
      before do
        class ADK::Auth::Runner
          public :handle_authentication_request
        end
      end
      
      # Restore privacy after tests
      after do
        class ADK::Auth::Runner
          private :handle_authentication_request
        end
      end

      context 'with a cached token' do
        it 'reuses cached tokens when available' do
          # Set up token manager to return a cached token
          allow(token_manager).to receive(:get_token).and_return(exchanged_credential)
          
          # Mock the task fiber so it can be resumed
          fiber_mock = instance_double(Fiber)
          allow(fiber_mock).to receive(:resume).with(exchanged_credential).and_return(exchanged_credential)
          
          # Call handle_authentication_request directly
          result = runner.handle_authentication_request(
            {
              action: :authenticate,
              scheme: oauth2_scheme,
              credential: credential,
              options: {}
            },
            fiber_mock
          )
          
          # Since we mocked token_manager to return a credential and
          # mocked the fiber to return that credential when resumed
          expect(result).to eq(exchanged_credential)
          expect(token_manager).to have_received(:get_token).with(oauth2_scheme, credential)
          expect(fiber_mock).to have_received(:resume).with(exchanged_credential)
        end
      end
      
      context 'without a cached token' do
        it 'handles authentication requests' do
          # Set up token manager to return nil (no cached token)
          allow(token_manager).to receive(:get_token).and_return(nil)
          
          # Create a mock coordinator
          coordinator = instance_double(ADK::Auth::Coordinators::OAuth2Coordinator)
          
          # Configure the coordinator mock
          allow(coordinator).to receive(:start).and_return({
            request_id: 'test-request-id',
            scheme_type: :oauth2,
            auth_request: { type: 'authorization_request' }
          })
          
          # Mock the coordinator creation
          allow(runner).to receive(:create_coordinator).and_return(coordinator)
          
          # Set up a test fiber
          test_fiber = Fiber.new { Fiber.yield }
          
          # Track auth handler calls
          auth_handler_called = false
          
          # Call handle_authentication_request directly with an auth handler
          result = runner.handle_authentication_request(
            {
              action: :authenticate,
              scheme: oauth2_scheme,
              credential: credential
            },
            test_fiber
          ) do |auth_request|
            auth_handler_called = true
            expect(auth_request[:request_id]).to eq('test-request-id')
            nil
          end
          
          # Verify the result
          expect(result[:status]).to eq(:pending)
          expect(result[:request_id]).to eq('test-request-id')
          
          # Verify the handler was called
          expect(auth_handler_called).to be true
          
          # Verify the coordinator was created and started
          expect(runner).to have_received(:create_coordinator)
          expect(coordinator).to have_received(:start)
        end
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