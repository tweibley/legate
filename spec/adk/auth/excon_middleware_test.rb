# frozen_string_literal: true

require 'spec_helper'
require 'adk/auth/excon_middleware'
require 'adk/auth/middleware_factory'
require 'adk/auth/schemes/api_key'
require 'adk/auth/credential'
require 'adk/auth/tool_integration'

RSpec.describe "ApiKey Integration Test" do
  describe "direct test of ApiKey with Excon integration" do
    # Create the scheme and credentials
    let(:scheme) { ADK::Auth::Schemes::ApiKey.new }
    
    let(:credential_query) { 
      ADK::Auth::Credential.new(
        auth_type: :api_key, 
        api_key: 'test-api-key',
        location: 'query',
        name: 'api_key'
      )
    }
    
    let(:credential_cookie) { 
      ADK::Auth::Credential.new(
        auth_type: :api_key, 
        api_key: 'test-api-key',
        location: 'cookie',
        name: 'api_key'
      )
    }
    
    let(:credential_header) { 
      ADK::Auth::Credential.new(
        auth_type: :api_key, 
        api_key: 'test-api-key',
        location: 'header',
        name: 'X-API-Key'
      )
    }
    
    it "should add query parameters correctly" do
      request = { url: 'https://example.com/api' }
      
      puts "Direct test - Query - Before: #{request.inspect}"
      result = scheme.apply_to_request(request, credential_query)
      puts "Direct test - Query - After: #{result.inspect}"
      
      expect(result[:url]).to include('api_key=test-api-key')
    end
    
    it "should add cookies correctly" do
      request = {}
      
      puts "Direct test - Cookie - Before: #{request.inspect}"
      result = scheme.apply_to_request(request, credential_cookie)
      puts "Direct test - Cookie - After: #{result.inspect}"
      
      expect(result[:headers]['Cookie']).to eq('api_key=test-api-key')
    end
    
    it "should work when called through tool integration directly" do
      # Test with query parameters
      request = { url: 'https://example.com/api' }
      
      puts "ToolIntegration test - Query - Before: #{request.inspect}"
      result = ADK::Auth::ToolIntegration.apply_authentication(request, scheme, credential_query, nil)
      puts "ToolIntegration test - Query - After: #{result.inspect}"
      
      expect(result[:url]).to include('api_key=test-api-key')
    end
    
    it "should work when called through middleware with header credential" do
      # Create a mock stack for testing
      mock_stack = double("MockStack")
      allow(mock_stack).to receive(:request_call) { |datum| datum }
      
      # Create middleware with the ApiKey scheme
      middleware = ADK::Auth::ExconMiddleware.new(
        mock_stack,
        scheme: scheme,
        credential: credential_header
      )
      
      # Override the apply_authentication method for test diagnosis
      # This needs to be done after middleware creation since middleware initialization
      # happens in the constructor and may have captured the original implementation
      allow(ADK::Auth::ToolIntegration).to receive(:apply_authentication) do |request, scheme, credential, token_store|
        puts "ToolIntegration.apply_authentication called with request: #{request.inspect}"
        auth_result = scheme.apply_to_request(request, credential)
        puts "ToolIntegration returning: #{auth_result.inspect}"
        auth_result
      end
      
      # Test with Excon-stack format which is known to work
      datum = { 
        request: {
          stack: {
            scheme: 'https',
            host: 'example.com',
            path: '/api',
            method: 'GET'
          },
          headers: {}
        }
      }
      
      puts "Middleware test - Header - Before: #{datum.inspect}"
      result = middleware.request_call(datum)
      puts "Middleware test - Header - After: #{result.inspect}"
      
      expect(result[:request][:headers]['X-API-Key']).to eq('test-api-key')
    end
    
    it "should work when called through middleware with query credential" do
      # Create a mock stack for testing
      mock_stack = double("MockStack")
      allow(mock_stack).to receive(:request_call) { |datum| datum }
      
      # Create middleware with the ApiKey scheme
      middleware = ADK::Auth::ExconMiddleware.new(
        mock_stack,
        scheme: scheme,
        credential: credential_query
      )
      
      # Override the apply_authentication method for test diagnosis
      allow(ADK::Auth::ToolIntegration).to receive(:apply_authentication) do |request, scheme, credential, token_store|
        puts "ToolIntegration.apply_authentication called with request: #{request.inspect}"
        auth_result = scheme.apply_to_request(request, credential)
        puts "ToolIntegration returning: #{auth_result.inspect}"
        auth_result
      end
      
      # Test with Excon-stack format which is known to work
      datum = { 
        request: {
          stack: {
            scheme: 'https',
            host: 'example.com',
            path: '/api',
            method: 'GET'
          },
          headers: {}
        }
      }
      
      puts "Middleware test - Query - Before: #{datum.inspect}"
      result = middleware.request_call(datum)
      puts "Middleware test - Query - After: #{result.inspect}"
      
      # With query authentication, the URL should be added to the request
      expect(result[:request][:url]).to include('api_key=test-api-key')
    end
    
    it "should work when called through middleware with cookie credential" do
      # Create a mock stack for testing
      mock_stack = double("MockStack")
      allow(mock_stack).to receive(:request_call) { |datum| datum }
      
      # Create middleware with the ApiKey scheme
      middleware = ADK::Auth::ExconMiddleware.new(
        mock_stack,
        scheme: scheme,
        credential: credential_cookie
      )
      
      # Override the apply_authentication method for test diagnosis
      allow(ADK::Auth::ToolIntegration).to receive(:apply_authentication) do |request, scheme, credential, token_store|
        puts "ToolIntegration.apply_authentication called with request: #{request.inspect}"
        auth_result = scheme.apply_to_request(request, credential)
        puts "ToolIntegration returning: #{auth_result.inspect}"
        auth_result
      end
      
      # Test with Excon-stack format which is known to work
      datum = { 
        request: {
          stack: {
            scheme: 'https',
            host: 'example.com',
            path: '/api',
            method: 'GET'
          },
          headers: {}
        }
      }
      
      puts "Middleware test - Cookie - Before: #{datum.inspect}"
      result = middleware.request_call(datum)
      puts "Middleware test - Cookie - After: #{result.inspect}"
      
      expect(result[:request][:headers]['Cookie']).to eq('api_key=test-api-key')
    end
    
    it "should work with request[:stack] parameter format" do
      # Create a mock stack for testing
      mock_stack = double("MockStack")
      allow(mock_stack).to receive(:request_call) { |datum| datum }
      
      # Create middleware with the ApiKey scheme
      middleware = ADK::Auth::ExconMiddleware.new(
        mock_stack,
        scheme: scheme,
        credential: credential_header
      )
      
      # Override the apply_authentication method for test diagnosis
      allow(ADK::Auth::ToolIntegration).to receive(:apply_authentication) do |request, scheme, credential, token_store|
        puts "ToolIntegration.apply_authentication called with request: #{request.inspect}"
        auth_result = scheme.apply_to_request(request, credential)
        puts "ToolIntegration returning: #{auth_result.inspect}"
        auth_result
      end
      
      # Test with stack parameter (simulating how Excon actually works)
      datum = { 
        request: {
          stack: {
            scheme: 'https',
            host: 'example.com',
            path: '/api',
            method: 'GET'
          },
          headers: {}
        }
      }
      
      puts "Middleware test - Stack format - Before: #{datum.inspect}"
      result = middleware.request_call(datum)
      puts "Middleware test - Stack format - After: #{result.inspect}"
      
      expect(result[:request][:headers]['X-API-Key']).to eq('test-api-key')
    end
  end
end 