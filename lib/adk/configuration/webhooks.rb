require 'adk/session_service/base'

module ADK
  class Configuration
    # Configuration settings for the inbound webhook listener and processing.
    class Webhooks
      # @return [Boolean] Whether the webhook listener is enabled. Defaults to false.
      attr_accessor :listener_enabled

      # @return [String] The IP address the listener should bind to. Defaults to '127.0.0.1'.
      attr_accessor :listen_address

      # @return [Integer] The port the listener should bind to. Defaults to 9292.
      attr_accessor :listen_port

      # @return [String] The base path for all webhook routes. Defaults to '/webhooks'.
      attr_accessor :base_path

      # @return [Boolean] Whether the dynamic agent handler route is enabled. Defaults to false.
      attr_accessor :enable_dynamic_agent_handler

      # @return [String] The path pattern for the dynamic agent handler. Defaults to '/agents/:agent_name/trigger'.
      attr_accessor :dynamic_agent_route_pattern

      # @return [Symbol, Proc, nil] A global validator to apply if an agent doesn't specify one.
      attr_accessor :global_validator

      # @return [String, nil] The secret key used by the global validator (e.g., for HMAC).
      attr_accessor :global_secret

      # @return [ADK::SessionService::Base, nil] The default session service instance to use in the webhook worker.
      attr_accessor :default_session_service

      def initialize
        @listener_enabled = false
        @listen_address = '127.0.0.1' # Default to loopback for security
        @listen_port = 9292
        @base_path = '/webhooks'
        @enable_dynamic_agent_handler = false
        @dynamic_agent_route_pattern = '/agents/:agent_name/trigger'
        @global_validator = nil
        @global_secret = nil
        @default_session_service = nil
        @validators = {}
        @static_routes = {} # Store static routes: path -> RouteConfig
      end

      # Registers a named validator proc/lambda.
      #
      # @param name [Symbol] The name to register the validator under.
      # @yield [request, secret] The block that performs validation.
      # @yieldparam request The Rack request object.
      # @yieldparam secret [String, nil] The secret associated with the route/agent.
      # @yieldreturn [Boolean] True if the request is valid, false otherwise.
      # @raise [ArgumentError] If the name is already registered or no block is given.
      def register_validator(name, &block)
        raise ArgumentError, "Validator name :#{name} is already registered." if @validators.key?(name)
        raise ArgumentError, 'Validator requires a block.' unless block_given?

        @validators[name] = block
      end

      # Finds a registered validator by name.
      #
      # @param name [Symbol] The name of the validator.
      # @return [Proc, nil] The validator proc or nil if not found.
      def find_validator(name)
        @validators[name]
      end

      # Registers a static webhook route.
      # Primarily intended for simple, non-agent-related endpoints like health checks.
      # Agent-related webhooks should typically use the dynamic agent handler.
      #
      # @param path [String] The HTTP method and path pattern (e.g., "GET /system/health", "POST /simple").
      # @yield [route_config] The block to configure the route.
      # @yieldparam route_config [RouteConfig] The configuration object for this route.
      # @raise [ArgumentError] If the path is already registered or no block is given.
      def register_route(path, &block)
        raise ArgumentError, "Route path \"#{path}\" is already registered." if @static_routes.key?(path)
        raise ArgumentError, 'Route registration requires a block.' unless block_given?

        config = RouteConfig.new
        yield config
        @static_routes[path] = config
      end

      # Retrieves the configurations for all registered static routes.
      # @return [Hash{String => RouteConfig}] A hash mapping path patterns to their configurations.
      def static_routes
        @static_routes.dup # Return a copy to prevent external modification
      end

      # Internal class to hold configuration for a single static route.
      class RouteConfig
        # @return [Proc, nil] The handler proc for the route. Should return a Rack response array.
        attr_accessor :handler
        # @return [Symbol, Proc, nil] A specific validator for this static route.
        attr_accessor :validator
        # @return [String, nil] The secret key for this static route's validator.
        attr_accessor :secret

        def initialize
          @handler = nil
          @validator = nil
          @secret = nil
        end
      end
    end
  end
end
