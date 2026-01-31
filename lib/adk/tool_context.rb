# File: lib/adk/tool_context.rb
# frozen_string_literal: true

module ADK
  # Provides contextual information to {ADK::Tool#execute}.
  #
  # The ToolContext is the primary interface for tools to interact with the
  # agent's environment, including session state, user information, and
  # authentication services. It is passed as the second argument to the
  # tool's execution method.
  #
  # @example Accessing context in a tool
  #   def perform_execution(params, context)
  #     user_id = context.user_id
  #     previous_count = context.state_get(:count) || 0
  #
  #     # Update state for future steps
  #     context.state_set(:count, previous_count + 1)
  #
  #     { status: :success, result: "Count is now #{previous_count + 1}" }
  #   end
  #
  class ToolContext
    # @return [String] The ID of the current session.
    attr_reader :session_id

    # @return [String] The user ID associated with the session.
    attr_reader :user_id

    # @return [String] The application/agent name associated with the session.
    attr_reader :app_name

    # @return [ADK::ToolRegistry] The tool registry instance of the agent executing the tool.
    attr_reader :tool_registry

    # @return [ADK::SessionService::Base, nil] The session service instance.
    attr_reader :session_service

    # @return [Logger] The logger instance.
    attr_reader :logger

    # @return [String, nil] The ID of the current agent invocation.
    attr_reader :invocation_id

    # Expose pending state delta for inspection but not direct modification.
    # @return [Hash] Pending state changes to be applied after successful execution.
    attr_reader :pending_state_delta

    # Agent-specific authentication configuration.
    # @return [Hash, nil] The agent's auth config or nil if not configured.
    attr_reader :agent_auth_config

    # @param session_id [String] The ID of the current session.
    # @param user_id [String] The user ID associated with the session.
    # @param app_name [String] The application/agent name associated with the session.
    # @param tool_registry [ADK::ToolRegistry] The tool registry instance of the agent executing the tool.
    # @param session_service [ADK::SessionService::Base, nil] The session service instance.
    # @param logger [Logger, nil] The logger instance.
    # @param invocation_id [String, nil] The ID of the current agent invocation.
    # @param agent_auth_config [Hash, nil] Agent-specific authentication configuration.
    def initialize(session_id:, user_id:, app_name:, tool_registry: nil, session_service: nil, logger: ADK.logger, invocation_id: nil, agent_auth_config: nil)
      @session_id = session_id
      @user_id = user_id
      @app_name = app_name
      @tool_registry = tool_registry
      @session_service = session_service
      @logger = logger
      @invocation_id = invocation_id
      @pending_state_delta = {}
      @token_manager = nil
      @agent_auth_config = agent_auth_config
    end

    # Retrieves a value from the session state via the session_service.
    #
    # Use this to access information stored by previous steps or tools in the same session.
    #
    # @param key [Symbol, String] The key to retrieve.
    # @return [Object, nil] The value stored in the session state, or nil if not found.
    # @example Retrieve a stored search query
    #   query = context.state_get(:last_search_query)
    def state_get(key)
      unless @session_service
        ADK.logger.warn { '[ToolContext] state_get called but no session_service available.' }
        return nil
      end

      ADK.logger.debug { "[ToolContext] state_get for key: #{key} in session: #{@session_id}" }
      @session_service.get_state(session_id: @session_id, key: key)
    rescue StandardError => e
      ADK.logger.error { "[ToolContext] Error in state_get for key '#{key}': #{e.message}" }
      nil
    end

    # Sets a value in the pending state delta for this context.
    #
    # The state is NOT updated immediately in the session service. It is stored
    # in a pending delta and applied only if the tool execution completes successfully.
    # This prevents partial state updates if a tool crashes.
    #
    # @param key [Symbol, String] The key to set.
    # @param value [Object] The value to store (must be serializable to JSON).
    # @return [Object] The value that was set.
    # @example Store a calculation result
    #   context.state_set(:workflow_status, 'completed')
    def state_set(key, value)
      ADK.logger.debug { "[ToolContext] state_set for key: #{key} to value: #{value.inspect} (pending)" }
      @pending_state_delta[key.to_sym] = value
    end

    # Merges a hash into the pending state delta for this context.
    #
    # Useful for updating multiple state variables at once.
    #
    # @param hash_to_merge [Hash] The hash of key-value pairs to merge into the pending state delta.
    # @return [Hash] The updated pending state delta.
    # @example Update status and retry count
    #   context.state_update(status: 'active', retries: 0)
    def state_update(hash_to_merge)
      unless hash_to_merge.is_a?(Hash)
        ADK.logger.warn { "[ToolContext] state_update called with non-hash: #{hash_to_merge.class}" }
        return
      end

      ADK.logger.debug { "[ToolContext] state_update with hash: #{hash_to_merge.inspect} (pending)" }
      @pending_state_delta.merge!(hash_to_merge.transform_keys(&:to_sym))
    end

    # Clears any accumulated pending state changes within this context instance.
    #
    # This is typically used internally by the framework if an operation is aborted.
    # @return [Hash] The empty pending state delta.
    def clear_pending_state_delta!
      @pending_state_delta = {}
    end

    # --- Authentication-related methods ---

    # Apply authentication to a request using the specified scheme and credential.
    #
    # @param request [Hash] The request to authenticate.
    # @param scheme [ADK::Auth::Scheme] The authentication scheme to use.
    # @param credential [ADK::Auth::Credential] The credential to use.
    # @return [Hash] The authenticated request with necessary headers/params added.
    def authenticate_request(request, scheme, credential)
      require_relative 'auth/tool_integration'

      # Try to use token manager if available
      token_manager = get_token_manager
      if token_manager
        # First get the token from token manager
        token = token_manager.get_token(scheme, credential, force_refresh: false)

        # Then apply authentication
        return ADK::Auth::ToolIntegration.apply_authentication(
          request,
          scheme,
          credential,
          nil,
          token_manager
        )
      end

      # Fall back to token store if token manager not available
      token_store = get_token_store

      # Apply authentication
      ADK::Auth::ToolIntegration.apply_authentication(request, scheme, credential, token_store)
    end

    # Check if a response indicates an authentication error.
    #
    # @param response [Hash] The response object (usually with :status and :body).
    # @return [Boolean] True if the response indicates an authentication error (e.g., 401).
    def authentication_error?(response)
      require_relative 'auth/tool_integration'
      ADK::Auth::ToolIntegration.authentication_error?(response)
    end

    # Check if a request likely requires authentication.
    #
    # @param request [Hash] The request object.
    # @return [Boolean] True if the request likely requires authentication.
    def requires_authentication?(request)
      require_relative 'auth/tool_integration'
      ADK::Auth::ToolIntegration.requires_authentication?(request)
    end

    # Get an authentication token from the session cache.
    #
    # @param scheme [ADK::Auth::Scheme] The authentication scheme.
    # @param credential [ADK::Auth::Credential] The credential.
    # @param force_refresh [Boolean] Whether to force a token refresh.
    # @return [ADK::Auth::ExchangedCredential, nil] The token if available.
    def get_token(scheme, credential, force_refresh: false)
      # Try to use token manager if available
      token_manager = get_token_manager
      if token_manager
        return token_manager.get_token(scheme, credential, force_refresh: force_refresh)
      end

      # Fall back to old mechanism if token manager not available
      token_store = get_token_store
      return nil unless token_store

      require_relative 'auth/tool_integration'
      cache_key = ADK::Auth::ToolIntegration.generate_cache_key(scheme, credential)
      token_store.get(cache_key)
    end

    # Refresh an authentication token.
    #
    # @param scheme [ADK::Auth::Scheme] The authentication scheme.
    # @param credential [ADK::Auth::Credential] The credential.
    # @param token [ADK::Auth::ExchangedCredential, nil] The current token, if available.
    # @return [ADK::Auth::ExchangedCredential, nil] The refreshed token if successful.
    def refresh_token(scheme, credential, token = nil)
      # Try to use token manager if available
      token_manager = get_token_manager
      if token_manager
        return token_manager.refresh_token(scheme, credential, token)
      end

      # Fall back to direct refresh if token manager not available
      if token && scheme.supports_refresh? && token.refreshable?
        begin
          refreshed = scheme.refresh_token(token, credential)
          store_token(scheme, credential, refreshed)
          return refreshed
        rescue ADK::Auth::TokenRefreshError => e
          ADK.logger.error("Failed to refresh token: #{e.message}")
          return nil
        end
      end

      nil
    end

    # Store an authentication token in the session cache.
    #
    # @param scheme [ADK::Auth::Scheme] The authentication scheme.
    # @param credential [ADK::Auth::Credential] The credential.
    # @param token [ADK::Auth::ExchangedCredential] The token to cache.
    # @return [Boolean] True if the token was stored successfully.
    def store_token(scheme, credential, token)
      token_store = get_token_store
      return false unless token_store

      require_relative 'auth/tool_integration'
      cache_key = ADK::Auth::ToolIntegration.generate_cache_key(scheme, credential)
      token_store.store(cache_key, token)
      true
    end

    # Clear a cached authentication token.
    #
    # @param scheme [ADK::Auth::Scheme] The authentication scheme.
    # @param credential [ADK::Auth::Credential] The credential.
    # @return [Boolean] True if the token was cleared successfully.
    def clear_token(scheme, credential)
      token_store = get_token_store
      return false unless token_store

      require_relative 'auth/tool_integration'
      cache_key = ADK::Auth::ToolIntegration.generate_cache_key(scheme, credential)
      token_store.clear(cache_key)
      true
    end

    # Revoke a token with the authentication provider.
    #
    # @param scheme [ADK::Auth::Scheme] The authentication scheme.
    # @param credential [ADK::Auth::Credential] The credential.
    # @param token [ADK::Auth::ExchangedCredential] The token to revoke.
    # @return [Boolean] True if the token was revoked successfully.
    def revoke_token(scheme, credential, token)
      # Try to use token manager if available
      token_manager = get_token_manager
      if token_manager
        return token_manager.revoke_token(scheme, credential, token)
      end

      # Fall back to direct revocation if token manager not available
      unless scheme.respond_to?(:revoke_token)
        ADK.logger.warn("Scheme #{scheme.scheme_type} does not support token revocation")
        return false
      end

      begin
        result = scheme.revoke_token(token, credential)
        if result
          clear_token(scheme, credential)
        end
        result
      rescue ADK::Auth::Error => e
        ADK.logger.error("Failed to revoke token: #{e.message}")
        false
      end
    end

    # Handle authentication for a request, automatically selecting the appropriate scheme and credential.
    #
    # Checks agent-specific auth config first, then falls back to global Auth::Manager.
    #
    # @param request [Hash] The request to authenticate.
    # @param options [Hash] Options for authentication.
    # @option options [Symbol] :credential_name Specific credential to use.
    # @option options [Symbol] :scheme_type Specific scheme type to use.
    # @return [Hash] The authenticated request or the original request if authentication not possible.
    def handle_request_auth(request, options = {})
      # Skip if request doesn't need authentication
      return request unless requires_authentication?(request)

      require_relative 'auth/manager'

      begin
        auth_manager = ADK::Auth::Manager.instance
        scheme = nil
        credential = nil

        # First, check agent-specific URL mappings
        if @agent_auth_config && @agent_auth_config[:url_mappings]&.any?
          scheme, credential = find_agent_auth_for_url(request[:url], auth_manager)
          if scheme && credential
            ADK.logger.debug { "[ToolContext] Using agent-specific auth for URL: #{request[:url]}" }
            return authenticate_request(request, scheme, credential)
          end
        end

        # Fall back to global Auth::Manager lookup
        scheme, credential = auth_manager.find_scheme_and_credential(
          url: request[:url],
          scheme_type: options[:scheme_type],
          credential_name: options[:credential_name]
        )

        # Apply authentication if found
        if scheme && credential
          return authenticate_request(request, scheme, credential)
        end
      rescue => e
        ADK.logger.error("Error in automatic authentication: #{e.message}")
      end

      # Return the original request if no authentication applied
      request
    end

    # Find authentication for a URL using agent-specific mappings.
    #
    # @param url [String] The URL to find authentication for.
    # @param auth_manager [ADK::Auth::Manager] The auth manager to resolve schemes/credentials.
    # @return [Array<ADK::Auth::Scheme, ADK::Auth::Credential>, nil] The scheme and credential, or nil if not found.
    def find_agent_auth_for_url(url, auth_manager)
      return nil unless @agent_auth_config && @agent_auth_config[:url_mappings]

      @agent_auth_config[:url_mappings].each do |mapping|
        pattern = mapping[:pattern]
        next unless pattern

        matched = if pattern.is_a?(Regexp)
          !!(url =~ pattern)
        elsif pattern.is_a?(String)
          if pattern.include?('*')
            # Convert glob pattern to regex
            regex = Regexp.new('^' + Regexp.escape(pattern).gsub('\\*', '.*') + '$')
            !!(url =~ regex)
          else
            url == pattern || url.start_with?(pattern)
          end
        else
          false
        end

        if matched
          scheme_name = mapping[:scheme_name]
          credential_name = mapping[:credential_name]

          # Resolve from Auth::Manager
          scheme = auth_manager.get_scheme(scheme_name)
          credential = auth_manager.get_credential(credential_name)

          if scheme && credential
            return [scheme, credential]
          else
            ADK.logger.warn { "[ToolContext] Agent auth mapping matched but scheme '#{scheme_name}' or credential '#{credential_name}' not found in Auth::Manager" }
          end
        end
      end

      nil
    end

    # Create or get the token manager for this context.
    # @return [ADK::Auth::TokenManager, nil] The token manager if available.
    def get_token_manager
      return @token_manager if @token_manager

      token_store = get_token_store
      return nil unless token_store

      require_relative 'auth/token_manager'
      @token_manager = ADK::Auth::TokenManager.new(token_store)
    end

    # @return [Hash] A hash representation of the context, suitable for serialization or logging.
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

    # Get the token store for caching authentication tokens.
    # @return [ADK::Auth::TokenStore, nil] The token store if available.
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
