# frozen_string_literal: true

require_relative 'client'
require_relative 'tool_wrapper'

module ADK
  module Mcp
    # Manages lifecycle of MCP connections and tool discovery for an agent
    class ConnectionManager
      attr_reader :clients

      # @param servers_config [Array<Hash>] Configuration for MCP servers
      # @param tool_registry [ADK::ToolRegistry] Registry to add discovered tools to
      # @param selected_tool_names [Array<Symbol>] List of tool names allowed to be registered
      def initialize(servers_config:, tool_registry:, selected_tool_names:)
        @servers_config = servers_config || []
        @tool_registry = tool_registry
        @selected_tool_names = selected_tool_names
        @clients = []
      end

      # Connects to all configured MCP servers and registers their tools
      def connect
        return if @servers_config.empty?

        @servers_config.each do |config|
          # Transform keys to symbols for the client
          symbolized_config = config.transform_keys(&:to_sym)
          ADK.logger.info("Attempting to connect to MCP server: #{symbolized_config.inspect}")

          begin
            unless %w[stdio sse].include?(symbolized_config[:type].to_s)
              ADK.logger.error("Unsupported MCP server type specified: #{symbolized_config[:type].inspect}. Skipping configuration: #{symbolized_config.inspect}")
              next
            end

            # Normalize type to symbol
            symbolized_config[:type] = symbolized_config[:type].to_sym

            client = ADK::Mcp::Client.new(symbolized_config)
            client.connect # This performs handshake and gets capabilities

            # Only add to clients list if connection successful
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

      # Disconnects all active MCP clients
      def disconnect
        return if @clients.empty?

        @clients.each do |client|
          ADK.logger.info('Disconnecting MCP client...')
          client.disconnect
        rescue StandardError => e
          ADK.logger.error("Error disconnecting MCP client: #{e.message}")
        end
        @clients.clear
      end

      private

      # Discovers tools from a connected MCP client and registers them
      # @param client [ADK::Mcp::Client]
      def discover_and_register_tools(client)
        ADK.logger.debug("[ConnectionManager] discover_and_register - @tool_registry ID: #{@tool_registry.object_id}")
        begin
          mcp_tool_schemas = client.list_tools
          ADK.logger.debug("[ConnectionManager] list_tools returned: #{mcp_tool_schemas.inspect}")
          ADK.logger.info("Discovered #{mcp_tool_schemas.count} tools from MCP server.")

          mcp_tool_schemas.each do |schema|
            tool_name_sym = schema[:name].to_sym
            if @selected_tool_names.include?(tool_name_sym)
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
