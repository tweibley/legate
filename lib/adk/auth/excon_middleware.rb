# File: lib/adk/auth/excon_middleware.rb
# frozen_string_literal: true

require 'excon'
require_relative 'tool_integration'

module ADK
  module Auth
    # Excon middleware for automatically handling authentication
    # This middleware can be inserted into the Excon middleware stack
    # to automatically apply authentication to requests and handle
    # authentication errors.
    class ExconMiddleware < Excon::Middleware::Base
      # Attributes needed by the shell middleware when accessing the configured instance
      attr_reader :scheme, :credential, :token_store, :token_manager
      attr_reader :auto_retry, :max_retries, :backoff_strategy, :backoff_factor
      attr_reader :retry_non_idempotent, :retry_on

      # Initialize the middleware
      # @param stack [Array] The middleware stack
      # @param options [Hash] The options for configuring the middleware
      def initialize(stack, options = {})
        super(stack)
        
        @scheme = options[:scheme]
        @credential = options[:credential]
        @token_store = options[:token_store]
        @token_manager = options[:token_manager]
        @auto_retry = options.fetch(:auto_retry, true)
        @max_retries = options.fetch(:max_retries, 3)
        @backoff_strategy = options.fetch(:backoff_strategy, :exponential)
        @backoff_factor = options.fetch(:backoff_factor, 1.0)
        @retry_non_idempotent = options.fetch(:retry_non_idempotent, false)
        @retry_on_config = Array(options.fetch(:retry_on, [])) + [401, 403]

        if @scheme && @credential
          ADK.logger.debug("ExconMiddleware: Factory-created instance configured: #{@scheme.scheme_type}") if defined?(ADK.logger)
          register_token_lifecycle_callbacks if @token_manager && @token_manager.respond_to?(:register_callback)
        else
          # This is the shell instance created by Excon
          ADK.logger.debug("ExconMiddleware: Shell instance initialized by Excon.") if defined?(ADK.logger)
        end
      end

      # Called for each request in the Excon middleware stack
      # @param datum [Hash] The request/response data
      # @yield [Hash] The updated request/response data
      # @return [Hash] The request/response data
      def request_call(datum)
        # Determine if this is the shell or the configured instance
        # The shell instance will have a non-nil @stack from Excon, 
        # and its @scheme will be nil (as Excon doesn't pass those to initialize by default)
        is_shell_instance = @scheme.nil? && @stack

        if is_shell_instance
          config_instance = datum[:connection].data[:auth_middleware_config]
          unless config_instance
            ADK.logger.warn("ExconMiddleware (shell): No :auth_middleware_config found. Passing through.") if defined?(ADK.logger)
            return @stack.request_call(datum)
          end
          ADK.logger.debug("ExconMiddleware (shell) delegating to configured instance for request logic.") if defined?(ADK.logger)
          # Modify datum using logic from config_instance, then shell calls @stack
          apply_authentication_logic(datum, config_instance)
          return @stack.request_call(datum)
        else
          # This is the factory-configured instance, being called directly (e.g. by the shell, or in tests)
          # It should not call @stack.request_call itself if its @stack is the factory-provided nil.
          ADK.logger.debug("ExconMiddleware (configured instance) applying auth logic directly.") if defined?(ADK.logger)
          apply_authentication_logic(datum, self) # Apply logic using its own config
          # This instance does not proceed down the Excon stack; it returns modified datum to the shell.
          return datum 
        end
      end

      # Called after each response in the Excon middleware stack
      # @param datum [Hash] The request/response data
      # @yield [Hash] The updated request/response data
      # @return [Hash] The request/response data
      def response_call(datum)
        is_shell_instance = @scheme.nil? && @stack

        if is_shell_instance
          # Shell instance calls down the stack first
          response_datum_from_stack = @stack.response_call(datum)

          config_instance = datum[:connection].data[:auth_middleware_config]
          unless config_instance
            ADK.logger.warn("ExconMiddleware (shell): No :auth_middleware_config for response. Passing through.") if defined?(ADK.logger)
            return response_datum_from_stack
          end
          ADK.logger.debug("ExconMiddleware (shell) delegating to configured instance for response logic.") if defined?(ADK.logger)
          return process_response_logic(response_datum_from_stack, config_instance)
        else
          # This is the factory-configured instance, being called by the shell.
          ADK.logger.debug("ExconMiddleware (configured instance) processing response logic directly.") if defined?(ADK.logger)
          return process_response_logic(datum, self) # Process using its own config
        end
      end

      private

      # Extracted logic that operates on datum using a config object (which can be self or another instance)
      def apply_authentication_logic(datum, config)
        ADK.logger.debug("Applying auth logic using config: #{config.object_id}, scheme: #{config.scheme.scheme_type}") if defined?(ADK.logger)
        datum[:request] ||= {}
        request_fields = [:scheme, :method, :path, :host, :port, :query]
        request_fields.each do |field|
          datum[:request][field] ||= datum[field] if datum.key?(field) && datum[field]
        end
        datum[:request][:headers] ||= {}

        if config.should_authenticate_with_config?(datum[:request], config)
          begin
            if config.scheme.is_a?(ADK::Auth::Schemes::ApiKey) && config.credential && config.credential[:location] == 'query'
              api_key_name = config.credential[:name]
              api_key_value = config.credential[:api_key]
              datum[:query] ||= {}
              if datum[:query].is_a?(String)
                require 'uri'
                current_params = {}
                URI.decode_www_form(datum[:query]).each { |k, v| current_params[k] = v }
                datum[:query] = current_params
              end
              datum[:query][api_key_name] = api_key_value
              datum[:request][:query] = datum[:query]
              datum.delete(:query_string)
              ADK.logger.debug("Added API key to query: #{api_key_name}=REDACTED") if defined?(ADK.logger)
            else
              cred_to_use = config.token_manager ? (config.token_manager.get_token(config.scheme, config.credential) || config.credential) : config.credential
              auth_req = ToolIntegration.apply_authentication(datum[:request], config.scheme, cred_to_use, config.token_store)
              if auth_req
                datum[:request][:headers].merge!(auth_req[:headers] || {})
                if auth_req[:query]
                  datum[:query] ||= {}
                  if datum[:query].is_a?(Hash) && auth_req[:query].is_a?(Hash)
                    datum[:query].merge!(auth_req[:query])
                  else
                    datum[:query] = auth_req[:query]
                  end
                  datum[:request][:query] = datum[:query]
                end
              end
            end
            ADK.logger.debug("Auth applied. Query: #{datum[:query].inspect}") if defined?(ADK.logger)
          rescue => e
            ADK.logger.error("Failed to apply auth: #{e.message} #{e.backtrace.join("\n")}") if defined?(ADK.logger)
          end
        end
        if datum[:query].is_a?(Hash)
          datum[:query] = datum[:query].transform_keys(&:to_s)
          datum[:request][:query] = datum[:query] if datum[:request]
        end
        ADK.logger.info("[AuthMiddleware] Outgoing query: #{datum[:query].inspect}") if defined?(ADK.logger)
      end

      def process_response_logic(response_datum, config)
        if defined?(ADK.logger) && ADK.logger.debug?
          actual_res = response_datum[:response] || response_datum
          ADK.logger.debug("Processing response. Status: #{actual_res[:status] || 'unknown'}")
        end
        if config.auto_retry && config.should_retry_with_config?(response_datum[:request] || datum[:request], response_datum[:response] || response_datum, config)
            ADK.logger.info("Auth (config instance) retry needed, Idempotent middleware should handle.") if defined?(ADK.logger)
        end
        response_datum
      end

      # Methods intended for internal use by the class or subclasses, 
      # or when operating on an explicit instance (like the config_instance)
      protected

      # Renamed to avoid clash if mixed into shell context, and takes config explicitly
      def should_authenticate_with_config?(request_datum, config)
        return false if config.scheme.nil? || config.credential.nil?
        true
      end

      def should_retry_with_config?(request_datum, response_details, config)
        return false unless request_datum && response_details
        status = response_details[:status]
        return false unless status
        return true if config.instance_variable_get(:@retry_on_config)&.include?(status)
        # relies on @retry_on_config on the config instance
        false
      end

      # This was previously private and unused by current logic, moving to protected for consistency
      def calculate_backoff_time(retry_count) 
        case config.backoff_strategy # Assuming config has backoff_strategy reader
        when :none then 0.0
        when :linear then retry_count * config.backoff_factor
        when :exponential then (2**retry_count) * config.backoff_factor
        else (2**retry_count) * config.backoff_factor
        end
      end

      def register_token_lifecycle_callbacks
        # Ensure @token_manager, @scheme, @credential are from the instance this method is called on (the factory-created one)
        return unless @token_manager && @scheme && @credential # only for fully configured instance
        @token_manager.register_callback(:token_refreshed) do |s, c, _t|
          ADK.logger.info("Token refreshed for #{s.scheme_type}") if defined?(ADK.logger) && s == @scheme && c == @credential
        end
        @token_manager.register_callback(:token_invalidated) do |s, c|
          ADK.logger.info("Token invalidated for #{s.scheme_type}") if defined?(ADK.logger) && s == @scheme && c == @credential
        end
        if @token_manager.respond_to?(:register_callback, :token_expiring) # Check arity for older rubies
          @token_manager.register_callback(:token_expiring) do |s, c, _t, time|
            ADK.logger.info("Token expiring in #{time}s for #{s.scheme_type}") if defined?(ADK.logger) && s == @scheme && c == @credential
          end
        end
      end
    end
  end
end 