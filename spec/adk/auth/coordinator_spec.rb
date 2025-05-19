# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/coordinator'
require 'adk/auth/schemes/oauth2'
require 'adk/auth/credential'
require 'adk/session_service/memory'

RSpec.describe ADK::Auth::Coordinator do
  let(:session_service) { ADK::SessionService::Memory.new }
  let(:token_store) { ADK::Auth::TokenStore.new(session_service) }
  
  let(:scheme) do
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
  
  # Create a test coordinator subclass that implements the authenticate method
  let(:test_coordinator_class) do
    Class.new(ADK::Auth::Coordinator) do
      attr_reader :auth_steps, :auth_results
      
      def initialize(scheme:, credential:, session_service:, token_store: nil, timeout: DEFAULT_TIMEOUT)
        super
        @auth_steps = []
        @auth_results = []
      end
      
      protected
      
      def authenticate
        @auth_steps << :step1
        step1_response = Fiber.yield({ step: 1, data: 'step1-data' })
        @auth_results << step1_response
        
        @auth_steps << :step2
        step2_response = Fiber.yield({ step: 2, data: 'step2-data' })
        @auth_results << step2_response
        
        # Return a mock exchanged credential
        ADK::Auth::ExchangedCredential.new(
          auth_type: :oauth2,
          access_token: 'test-access-token',
          token_type: 'Bearer',
          expires_in: 3600,
          expires_at: Time.now + 3600
        )
      end
    end
  end
  
  let(:coordinator) do
    test_coordinator_class.new(
      scheme: scheme,
      credential: credential,
      session_service: session_service,
      token_store: token_store
    )
  end
  
  describe '#start' do
    it 'initializes the fiber and returns the first auth request' do
      # Start the authentication flow
      result = coordinator.start
      
      # Verify the request structure
      expect(result).to be_a(Hash)
      expect(result[:request_id]).to be_a(String)
      expect(result[:scheme_type]).to eq(:oauth2)
      expect(result[:auth_request]).to eq({ step: 1, data: 'step1-data' })
      
      # Verify coordinator state
      expect(coordinator.status).to eq(ADK::Auth::Coordinator::Status::PENDING)
      expect(coordinator.complete?).to be false
      expect(coordinator.auth_steps).to eq([:step1])
    end
  end
  
  describe '#resume' do
    it 'resumes the authentication flow with a response' do
      # Start the authentication flow
      coordinator.start
      
      # Resume with a response to step 1
      step2_result = coordinator.resume({ response: 'step1-response' })
      
      # Verify the step 2 request
      expect(step2_result).to be_a(Hash)
      expect(step2_result[:request_id]).to be_a(String)
      expect(step2_result[:scheme_type]).to eq(:oauth2)
      expect(step2_result[:auth_request]).to eq({ step: 2, data: 'step2-data' })
      
      # Verify coordinator state is still pending
      expect(coordinator.status).to eq(ADK::Auth::Coordinator::Status::PENDING)
      expect(coordinator.complete?).to be false
      expect(coordinator.auth_steps).to eq([:step1, :step2])
      expect(coordinator.auth_results).to eq([{ response: 'step1-response' }])
      
      # Resume with a response to step 2
      final_result = coordinator.resume({ response: 'step2-response' })
      
      # Verify the final result is the credential
      expect(final_result).to be_a(ADK::Auth::ExchangedCredential)
      expect(final_result.auth_type).to eq(:oauth2)
      expect(final_result.access_token).to eq('test-access-token')
      
      # Verify coordinator state is now completed
      expect(coordinator.status).to eq(ADK::Auth::Coordinator::Status::COMPLETED)
      expect(coordinator.complete?).to be true
      expect(coordinator.success?).to be true
      expect(coordinator.auth_results).to eq([
        { response: 'step1-response' },
        { response: 'step2-response' }
      ])
    end
    
    it 'handles errors during authentication' do
      # Create a coordinator that raises an error
      error_coordinator_class = Class.new(ADK::Auth::Coordinator) do
        protected
        
        def authenticate
          response = Fiber.yield({ step: 1, data: 'step1-data' })
          raise ADK::Auth::Error, "Authentication failed: #{response[:error]}"
        end
      end
      
      error_coordinator = error_coordinator_class.new(
        scheme: scheme,
        credential: credential,
        session_service: session_service
      )
      
      # Start the authentication flow
      error_coordinator.start
      
      # Resume with an error response
      result = error_coordinator.resume({ error: 'invalid-token' })
      
      # Verify the result is nil (error occurred)
      expect(result).to be_nil
      
      # Verify coordinator state
      expect(error_coordinator.status).to eq(ADK::Auth::Coordinator::Status::FAILED)
      expect(error_coordinator.complete?).to be true
      expect(error_coordinator.success?).to be false
      expect(error_coordinator.error).to be_a(ADK::Auth::Error)
      expect(error_coordinator.error.message).to eq('Authentication failed: invalid-token')
    end
    
    it 'handles timeouts' do
      # Create a coordinator with a very short timeout
      quick_timeout_coordinator = test_coordinator_class.new(
        scheme: scheme,
        credential: credential,
        session_service: session_service,
        timeout: 0.1 # 100ms timeout
      )
      
      # Start the authentication flow
      quick_timeout_coordinator.start
      
      # Wait for the timeout to expire
      sleep 0.2
      
      # Resume should indicate timeout
      result = quick_timeout_coordinator.resume({ response: 'too-late' })
      
      # Verify the result is nil (timeout occurred)
      expect(result).to be_nil
      
      # Verify coordinator state
      expect(quick_timeout_coordinator.status).to eq(ADK::Auth::Coordinator::Status::TIMEOUT)
      expect(quick_timeout_coordinator.complete?).to be true
      expect(quick_timeout_coordinator.success?).to be false
      expect(quick_timeout_coordinator.error).to be_a(ADK::Auth::Error)
      expect(quick_timeout_coordinator.error.message).to include('timed out')
    end
  end
  
  describe '#cancel' do
    it 'cancels an in-progress authentication flow' do
      # Start the authentication flow
      coordinator.start
      
      # Cancel the flow
      result = coordinator.cancel('User cancelled')
      
      # Verify the result
      expect(result).to be true
      
      # Verify coordinator state
      expect(coordinator.status).to eq(ADK::Auth::Coordinator::Status::CANCELLED)
      expect(coordinator.complete?).to be true
      expect(coordinator.success?).to be false
      expect(coordinator.error).to be_a(ADK::Auth::Error)
      expect(coordinator.error.message).to include('cancelled')
    end
    
    it 'returns false when trying to cancel a completed flow' do
      # Start and complete the authentication flow
      coordinator.start
      coordinator.resume({ response: 'step1-response' })
      coordinator.resume({ response: 'step2-response' })
      
      # Try to cancel the flow
      result = coordinator.cancel('Too late')
      
      # Verify the result
      expect(result).to be false
      
      # Verify coordinator state is still completed
      expect(coordinator.status).to eq(ADK::Auth::Coordinator::Status::COMPLETED)
    end
  end
end 