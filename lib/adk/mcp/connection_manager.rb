# frozen_string_literal: true

require 'set'

module ADK
  module Mcp
    # Manages connections to MCP servers and tool discovery/registration.
    # Extracts this responsibility from the Agent class.
    class ConnectionManager
      attr_reader :clients

      # @param tool_registry [ADK::ToolRegistry] The registry to register discovered tools into.
      # @param allowed_tool_names [Set<Symbol>, Array<Symbol>] List of allowed tool names (filter).
      def initialize(tool_registry:, allowed_tool_names: Set.new)
        @tool_registry = tool_registry
        @allowed_tool_names = allowed_tool_names.to_set
        @clients = []
      end

      # Connects to all provided server configurations.
      # @param server_configs [Array<Hash>] List of server configuration hashes.
      def connect_all(server_configs)
        return if server_configs.nil? || server_configs.empty?

        server_configs.each do |config|
          connect_single(config)
        end
      end

      # Disconnects all active MCP clients.
      def disconnect_all
        return if @clients.empty?

        @clients.each do |client|
          begin
            ADK.logger.info('Disconnecting MCP client...')
            client.disconnect
          rescue StandardError => e
            ADK.logger.error("Error disconnecting MCP client: #{e.message}")
          end
        end
        @clients.clear
      end

      private

      def connect_single(config)
        symbolized_config = config.transform_keys(&:to_sym)
        ADK.logger.info("Attempting to connect to MCP server: #{symbolized_config.inspect}")

        begin
          validate_and_normalize_config!(symbolized_config)

          client = ADK::Mcp::Client.new(symbolized_config)
          client.connect
          @clients << client

          discover_and_register_tools(client)
        rescue ADK::ConfigurationError => e
          ADK.logger.error("Configuration error for MCP server #{config.inspect}: #{e.message}")
        rescue ADK::Mcp::ConnectionError, ADK::Mcp::ProtocolError => e
          ADK.logger.error("Failed to connect or handshake with MCP server #{config.inspect}: #{e.message}")
        rescue ADK::Mcp::McpError => e
          ADK.logger.error("MCP-related error connecting to server #{config.inspect}: #{e.message}")
        rescue StandardError => e
          ADK.logger.error("Unexpected error connecting to MCP server #{config.inspect}: #{e.class} - #{e.message}")
        end
      end

      def validate_and_normalize_config!(config)
        unless %w[stdio sse].include?(config[:type].to_s)
          raise ADK::ConfigurationError, "Unsupported MCP server type: #{config[:type].inspect}"
        end

        # Normalize type to symbol
        config[:type] = config[:type].to_sym if config[:type].is_a?(String)
      end

      def discover_and_register_tools(client)
        ADK.logger.debug("[ConnectionManager] discover_and_register - Registry ID: #{@tool_registry.object_id}")

        mcp_tool_schemas = client.list_tools
        ADK.logger.info("Discovered #{mcp_tool_schemas.count} tools from MCP server.")

        mcp_tool_schemas.each do |schema|
          tool_name_sym = schema[:name].to_sym
          if @allowed_tool_names.include?(tool_name_sym)
            ADK::Mcp::ToolWrapper.from_mcp_schema(schema, client, @tool_registry)
          else
            ADK.logger.debug("Skipping registration of MCP tool '#{tool_name_sym}' as it was not selected.")
          end
        end
      rescue ADK::Mcp::McpError => e
        ADK.logger.error("Failed to list tools from MCP server: #{e.message}")
      end
    end
  end
end
