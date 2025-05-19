# File: lib/adk/tool_context.rb
# frozen_string_literal: true

module ADK
  # Provides contextual information to ADK::Tool#perform_execution
  # Includes session details and a reference to the agent's tool registry.
  # Read-only.
  class ToolContext
    attr_reader :session_id, :user_id, :app_name, :tool_registry, :session_service, :logger, :invocation_id

    # Expose pending state delta for inspection but not direct modification
    attr_reader :pending_state_delta

    # @param session_id [String] The ID of the current session.
    # @param user_id [String] The user ID associated with the session.
    # @param app_name [String] The application/agent name associated with the session.
    # @param tool_registry [ADK::ToolRegistry] The tool registry instance of the agent executing the tool.
    # @param session_service [ADK::SessionService::Base, nil] The session service instance.
    # @param logger [Logger, nil] The logger instance.
    # @param invocation_id [String, nil] The ID of the current agent invocation.
    def initialize(session_id:, user_id:, app_name:, tool_registry: nil, session_service: nil, logger: ADK.logger, invocation_id: nil)
      @session_id = session_id
      @user_id = user_id
      @app_name = app_name
      @tool_registry = tool_registry
      @session_service = session_service
      @invocation_id = invocation_id
      @pending_state_delta = {}
    end

    # Retrieves a value from the session state via the session_service.
    # @param key [Symbol, String] The key to retrieve
    # @return [Object, nil] The value or nil if not found
    def state_get(key)
      unless @session_service
        ADK.logger.warn { "[ToolContext] state_get called but no session_service available." }
        return nil
      end

      ADK.logger.debug { "[ToolContext] state_get for key: #{key} in session: #{@session_id}" }
      @session_service.get_state(session_id: @session_id, key: key)
    rescue => e
      ADK.logger.error { "[ToolContext] Error in state_get for key '#{key}': #{e.message}" }
      nil
    end

    # Sets a value in the pending state delta for this context.
    # @param key [Symbol, String] The key to set
    # @param value [Object] The value to store (should be serializable)
    def state_set(key, value)
      ADK.logger.debug { "[ToolContext] state_set for key: #{key} to value: #{value.inspect} (pending)" }
      @pending_state_delta[key.to_sym] = value
    end

    # Merges a hash into the pending state delta for this context.
    # @param hash_to_merge [Hash] The hash to merge into the pending state delta
    def state_update(hash_to_merge)
      unless hash_to_merge.is_a?(Hash)
        ADK.logger.warn { "[ToolContext] state_update called with non-hash: #{hash_to_merge.class}" }
        return
      end

      ADK.logger.debug { "[ToolContext] state_update with hash: #{hash_to_merge.inspect} (pending)" }
      @pending_state_delta.merge!(hash_to_merge.transform_keys(&:to_sym))
    end

    # Clears any accumulated pending state changes within this context instance.
    def clear_pending_state_delta!
      @pending_state_delta = {}
    end
    
    # Authentication-related methods
    
    # Apply authentication to a request using the specified scheme and credential
    # @param request [Hash] The request to authenticate
    # @param scheme [ADK::Auth::Scheme] The authentication scheme to use
    # @param credential [ADK::Auth::Credential] The credential to use
    # @return [Hash] The authenticated request
    def authenticate_request(request, scheme, credential)
      require_relative 'auth/tool_integration'
      
      # Get token store if session service supports it
      token_store = get_token_store
      
      # Apply authentication
      ADK::Auth::ToolIntegration.apply_authentication(request, scheme, credential, token_store)
    end
    
    # Check if a response indicates an authentication error
    # @param response [Hash] The response to check
    # @return [Boolean] True if the response indicates an authentication error
    def authentication_error?(response)
      require_relative 'auth/tool_integration'
      ADK::Auth::ToolIntegration.authentication_error?(response)
    end
    
    # Get an authentication token from the session cache
    # @param scheme [ADK::Auth::Scheme] The authentication scheme
    # @param credential [ADK::Auth::Credential] The credential
    # @return [ADK::Auth::ExchangedCredential, nil] The cached token if available
    def get_cached_token(scheme, credential)
      token_store = get_token_store
      return nil unless token_store
      
      require_relative 'auth/tool_integration'
      cache_key = ADK::Auth::ToolIntegration.generate_cache_key(scheme, credential)
      token_store.get(cache_key)
    end
    
    # Store an authentication token in the session cache
    # @param scheme [ADK::Auth::Scheme] The authentication scheme
    # @param credential [ADK::Auth::Credential] The credential
    # @param token [ADK::Auth::ExchangedCredential] The token to cache
    # @return [Boolean] True if the token was stored successfully
    def store_token(scheme, credential, token)
      token_store = get_token_store
      return false unless token_store
      
      require_relative 'auth/tool_integration'
      cache_key = ADK::Auth::ToolIntegration.generate_cache_key(scheme, credential)
      token_store.store(cache_key, token)
      true
    end
    
    # Clear a cached authentication token
    # @param scheme [ADK::Auth::Scheme] The authentication scheme
    # @param credential [ADK::Auth::Credential] The credential
    # @return [Boolean] True if the token was cleared successfully
    def clear_token(scheme, credential)
      token_store = get_token_store
      return false unless token_store
      
      require_relative 'auth/tool_integration'
      cache_key = ADK::Auth::ToolIntegration.generate_cache_key(scheme, credential)
      token_store.clear(cache_key)
      true
    end

    def to_h
      {
        session_id: @session_id,
        user_id: @user_id,
        app_name: @app_name,
        invocation_id: @invocation_id,
        tool_registry_object_id: @tool_registry&.object_id,
        session_service_present: !@session_service.nil?
      }
    end
    
    private
    
    # Get the token store for caching authentication tokens
    # @return [ADK::Auth::TokenStore, nil] The token store if available
    def get_token_store
      return nil unless @session_service
      
      # If session_service is Redis, we can use its methods directly
      if @session_service.is_a?(ADK::SessionService::Redis)
        require_relative 'auth/token_store'
        return ADK::Auth::TokenStore.new(@session_service)
      end
      
      nil
    end
  end
end
