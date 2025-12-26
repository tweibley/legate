# frozen_string_literal: true

require_relative 'client'
require_relative 'tool_wrapper'

module ADK
  module Mcp
    # Manages lifecycle of MCP connections and tool discovery
    class ConnectionManager
      attr_reader :clients

      def initialize(logger = ADK.logger)
        @clients = []
        @logger = logger
      end

      def connect_all(configs)
        return if configs.nil? || configs.empty?

        configs.each do |config|
          symbolized = config.transform_keys(&:to_sym)

          # Handle string types from JSON/config
          if symbolized[:type] == 'stdio'
            symbolized[:type] = :stdio
          elsif symbolized[:type] == 'sse'
            symbolized[:type] = :sse
          end

          unless %i[stdio sse].include?(symbolized[:type])
            @logger.error("Unsupported MCP server type specified: #{symbolized[:type].inspect}. Skipping configuration: #{symbolized.inspect}")
            next
          end

          connect_client(symbolized)
        end
      end

      def disconnect_all
        @clients.each do |client|
          @logger.info('Disconnecting MCP client...')
          client.disconnect
        rescue StandardError => e
          @logger.error("Error disconnecting MCP client: #{e.message}")
        end
        @clients.clear
      end

      def register_tools(registry, selected_tool_names)
        @clients.each do |client|
          mcp_tool_schemas = client.list_tools
          @logger.info("Discovered #{mcp_tool_schemas.count} tools from MCP server.")

          mcp_tool_schemas.each do |schema|
            if selected_tool_names.include?(schema[:name].to_sym)
              ADK::Mcp::ToolWrapper.from_mcp_schema(schema, client, registry)
            else
              @logger.debug("Skipping registration of MCP tool '#{schema[:name]}' as it was not selected in agent definition.")
            end
          end
        rescue ADK::Mcp::McpError => e
          @logger.error("Failed to list tools from MCP server: #{e.message}")
        rescue StandardError => e
          @logger.error("Unexpected error discovering MCP tools: #{e.class} - #{e.message}")
        end
      end

      private

      def connect_client(config)
        @logger.info("Attempting to connect to MCP server: #{config.inspect}")
        client = ADK::Mcp::Client.new(config)
        client.connect
        @clients << client
      rescue ADK::Mcp::ConnectionError, ADK::Mcp::ProtocolError => e
        @logger.error("Failed to connect or handshake with MCP server #{config.inspect}: #{e.message}")
      rescue ADK::Mcp::McpError => e
        @logger.error("MCP-related error connecting to server #{config.inspect}: #{e.message}")
      rescue StandardError => e
        @logger.error("Unexpected error connecting to MCP server #{config.inspect}: #{e.class} - #{e.message}")
      end
    end
  end
end
