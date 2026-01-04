# frozen_string_literal: true

require_relative 'client'
require_relative 'tool_wrapper'
require 'set'

module ADK
  module Mcp
    # Manages lifecycle of MCP connections and tool discovery.
    # Decouples MCP logic from the main Agent class.
    class ConnectionManager
      attr_reader :clients

      # @param server_configs [Array<Hash>] Configuration for MCP servers
      # @param tool_registry [ADK::ToolRegistry] Registry to add discovered tools to
      # @param allowed_tool_names [Set<Symbol>, Array<Symbol>] List of allowed tool names (optional whitelist)
      def initialize(server_configs:, tool_registry:, allowed_tool_names: nil)
        @server_configs = server_configs || []
        @tool_registry = tool_registry
        @allowed_tool_names = allowed_tool_names&.to_set
        @clients = []
      end

      # Connects to all configured MCP servers.
      def connect_all
        return if @server_configs.empty?

        @server_configs.each do |config|
          connect_single_server(config)
        end
      end

      # Disconnects all active MCP clients.
      def disconnect_all
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

      def connect_single_server(config)
        # Transform keys to symbols for the client
        symbolized_config = config.transform_keys(&:to_sym)
        ADK.logger.info("Attempting to connect to MCP server: #{symbolized_config.inspect}")

        begin
          validate_and_normalize_config!(symbolized_config)

          client = ADK::Mcp::Client.new(symbolized_config)
          client.connect # This performs handshake and gets capabilities
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

      def validate_and_normalize_config!(config)
        unless %w[stdio sse].include?(config[:type].to_s)
          ADK.logger.error("Unsupported MCP server type specified: #{config[:type].inspect}. Skipping configuration: #{config.inspect}")
          raise ADK::Mcp::McpError, "Unsupported MCP server type: #{config[:type]}"
        end

        # Normalize type to symbol
        config[:type] = config[:type].to_sym
      end

      # Discovers tools from a connected MCP client and registers them.
      def discover_and_register_tools(client)
        ADK.logger.debug("[ConnectionManager] discover_and_register - registry ID: #{@tool_registry.object_id}")
        begin
          mcp_tool_schemas = client.list_tools
          ADK.logger.debug("[ConnectionManager] list_tools returned: #{mcp_tool_schemas.inspect}")
          ADK.logger.info("Discovered #{mcp_tool_schemas.count} tools from MCP server.")

          mcp_tool_schemas.each do |schema|
            register_tool_if_allowed(schema, client)
          end
        rescue ADK::Mcp::McpError => e
          ADK.logger.error("Failed to list tools from MCP server: #{e.message}")
        rescue StandardError => e
          ADK.logger.error("Unexpected error discovering MCP tools: #{e.class} - #{e.message}")
        end
      end

      def register_tool_if_allowed(schema, client)
        tool_name_sym = schema[:name].to_sym

        # If allowed_tool_names is nil, we assume all tools are allowed (though in current Agent logic it seems strict)
        # However, Agent explicitly passes the list. If the list is empty, nothing gets registered.
        # If allowed_tool_names is provided, check inclusion.
        if @allowed_tool_names.nil? || @allowed_tool_names.include?(tool_name_sym)
          ADK::Mcp::ToolWrapper.from_mcp_schema(schema, client, @tool_registry)
        else
          ADK.logger.debug("Skipping registration of MCP tool '#{tool_name_sym}' as it was not selected in agent definition.")
        end
      end
    end
  end
end
