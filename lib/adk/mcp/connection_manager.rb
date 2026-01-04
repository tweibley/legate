# frozen_string_literal: true

require_relative 'client'
require_relative 'tool_wrapper'
require_relative 'error'

module ADK
  module Mcp
    # Manages lifecycle of MCP connections and tool discovery.
    # Extracts this responsibility from ADK::Agent to improve cohesion.
    class ConnectionManager
      attr_reader :active_clients

      # @param tool_registry [ADK::ToolRegistry] Registry to register discovered tools into
      # @param allowed_tool_names [Set, Array] List/Set of tool names allowed to be registered
      def initialize(tool_registry:, allowed_tool_names:)
        @tool_registry = tool_registry
        @allowed_tool_names = allowed_tool_names
        @active_clients = []
      end

      # Connects to all configured MCP servers
      # @param configs [Array<Hash>] List of server configurations
      def connect_all(configs)
        return if configs.nil? || configs.empty?

        configs.each do |config|
          connect_server(config)
        end
      end

      # Disconnects all active MCP clients
      def disconnect_all
        return if @active_clients.empty?

        @active_clients.each do |client|
          ADK.logger.info('Disconnecting MCP client...')
          client.disconnect
        rescue StandardError => e
          ADK.logger.error("Error disconnecting MCP client: #{e.message}")
        end
        @active_clients.clear
      end

      private

      def connect_server(config)
        # Transform keys to symbols for the client
        symbolized_config = config.transform_keys(&:to_sym)
        ADK.logger.info("Attempting to connect to MCP server: #{symbolized_config.inspect}")

        begin
          # Validate type using string check to match original logic
          unless %w[stdio sse].include?(symbolized_config[:type].to_s)
            ADK.logger.error("Unsupported MCP server type specified: #{symbolized_config[:type].inspect}. Skipping configuration: #{symbolized_config.inspect}")
            return
          end

          # Explicitly convert known string type values to symbols
          # This matches the patch logic in original Agent code
          if symbolized_config[:type].to_s == 'stdio'
            symbolized_config[:type] = :stdio
          elsif symbolized_config[:type].to_s == 'sse'
            symbolized_config[:type] = :sse
          end

          client = ADK::Mcp::Client.new(symbolized_config)
          client.connect
          @active_clients << client

          discover_and_register_tools(client)
        rescue ADK::Mcp::ConnectionError, ADK::Mcp::ProtocolError => e
          ADK.logger.error("Failed to connect or handshake with MCP server #{config.inspect}: #{e.message}")
        rescue ADK::Mcp::McpError => e
          ADK.logger.error("MCP-related error connecting to server #{config.inspect}: #{e.message}")
        rescue StandardError => e
          ADK.logger.error("Unexpected error connecting to MCP server #{config.inspect}: #{e.class} - #{e.message}")
        end
      end

      def discover_and_register_tools(client)
        mcp_tool_schemas = client.list_tools
        ADK.logger.info("Discovered #{mcp_tool_schemas.count} tools from MCP server.")

        mcp_tool_schemas.each do |schema|
          tool_name_sym = schema[:name].to_sym
          if @allowed_tool_names.include?(tool_name_sym)
            ADK::Mcp::ToolWrapper.from_mcp_schema(schema, client, @tool_registry)
          else
            ADK.logger.debug("Skipping registration of MCP tool '#{tool_name_sym}' as it was not selected in agent definition.")
          end
        end
      rescue ADK::Mcp::McpError => e
        ADK.logger.error("Failed to list tools from MCP server: #{e.message}")
      rescue StandardError => e
        ADK.logger.error("Unexpected error discovering MCP tools: #{e.class} - #{e.message}")
      end
    end
  end
end
