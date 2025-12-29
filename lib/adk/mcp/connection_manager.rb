# File: lib/adk/mcp/connection_manager.rb
# frozen_string_literal: true

require 'set'
require_relative 'client'
require_relative 'tool_wrapper'

module ADK
  module Mcp
    # Manages the lifecycle of MCP connections and tool discovery.
    # This class decouples connection logic from the Agent class.
    class ConnectionManager
      attr_reader :clients

      # @param configs [Array<Hash>] List of MCP server configurations.
      # @param tool_registry [ADK::ToolRegistry] The registry to register discovered tools into.
      # @param allowed_tool_names [Array<Symbol>, Set<Symbol>] Tools that are allowed to be registered.
      def initialize(configs:, tool_registry:, allowed_tool_names:)
        @configs = configs || []
        @tool_registry = tool_registry
        @allowed_tool_names = allowed_tool_names.to_set
        @clients = []
      end

      # Connects to all configured MCP servers and registers tools.
      def connect_all
        return if @configs.empty?

        @configs.each do |config|
          # Transform keys to symbols for the client
          symbolized_config = config.transform_keys(&:to_sym)
          ADK.logger.info("Attempting to connect to MCP server: #{symbolized_config.inspect}")

          begin
            # Normalize type to symbol
            if symbolized_config[:type].is_a?(String)
              symbolized_config[:type] = symbolized_config[:type].to_sym
            end

            unless %i[stdio sse].include?(symbolized_config[:type])
              ADK.logger.error("Unsupported MCP server type specified: #{symbolized_config[:type].inspect}. Skipping.")
              next
            end

            client = ADK::Mcp::Client.new(symbolized_config)
            client.connect
            @clients << client
            discover_and_register_tools(client)

          rescue ADK::Mcp::ConnectionError, ADK::Mcp::ProtocolError => e
            ADK.logger.error("Failed to connect or handshake with MCP server #{config.inspect}: #{e.message}")
          rescue ADK::Mcp::McpError => e
            ADK.logger.error("MCP-related error connecting to server #{config.inspect}: #{e.message}")
          rescue StandardError => e
            ADK.logger.error("Unexpected error connecting to MCP server #{config.inspect}: #{e.class} - #{e.message}")
          end
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

      # Discovers tools from a connected MCP client and registers them.
      # @param client [ADK::Mcp::Client]
      def discover_and_register_tools(client)
        begin
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
end
