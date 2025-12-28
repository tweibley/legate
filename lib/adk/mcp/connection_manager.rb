# frozen_string_literal: true

require_relative 'client'
require_relative 'tool_wrapper'
require_relative 'error'
require 'logger'

module ADK
  module Mcp
    # Manages the lifecycle of MCP (Model Context Protocol) connections for an agent.
    # Handles connecting, disconnecting, and discovering tools from MCP servers.
    class ConnectionManager
      attr_reader :clients

      # @param configs [Array<Hash>] Configuration for MCP servers.
      # @param tool_registry [ADK::ToolRegistry] Registry to register discovered tools into.
      # @param allowed_tool_names [Set<Symbol>, Array<Symbol>, nil] List of allowed tool names. If nil, all tools are allowed.
      def initialize(configs, tool_registry, allowed_tool_names = nil)
        @configs = configs || []
        @tool_registry = tool_registry
        @allowed_tool_names = allowed_tool_names.is_a?(Array) ? allowed_tool_names.to_set : allowed_tool_names
        @clients = []
      end

      # Connects to all configured MCP servers.
      def connect_all
        return if @configs.empty?

        @configs.each do |config|
          connect_single_server(config)
        end
      end

      # Disconnects all active MCP clients.
      def disconnect_all
        return if @clients.empty?

        @clients.each do |client|
          disconnect_client(client)
        end
        @clients.clear
      end

      private

      def disconnect_client(client)
        ADK.logger.info('Disconnecting MCP client...')
        client.disconnect
      rescue StandardError => e
        ADK.logger.error("Error disconnecting MCP client: #{e.message}")
      end

      def connect_single_server(config)
        # Transform keys to symbols for the client
        symbolized_config = config.transform_keys(&:to_sym)
        ADK.logger.info("Attempting to connect to MCP server: #{symbolized_config.inspect}")

        validate_config!(symbolized_config)
        establish_connection(symbolized_config, config)
      rescue ADK::Mcp::ConnectionError, ADK::Mcp::ProtocolError => e
        ADK.logger.error("Failed to connect or handshake with MCP server #{config.inspect}: #{e.message}")
      rescue ADK::Mcp::McpError => e
        ADK.logger.error("MCP-related error connecting to server #{config.inspect}: #{e.message}")
      rescue StandardError => e
        ADK.logger.error("Unexpected error connecting to MCP server #{config.inspect}: #{e.class} - #{e.message}")
      end

      def establish_connection(symbolized_config, original_config)
        client = ADK::Mcp::Client.new(symbolized_config)
        client.connect # This performs handshake and gets capabilities
        @clients << client
        discover_and_register_tools(client)
      end

      def validate_config!(config)
        # Ensure type is symbolized and valid
        config[:type] = config[:type].to_sym if config[:type].is_a?(String)

        return if %i[stdio sse].include?(config[:type])

        raise ADK::Mcp::ConnectionError, "Unsupported MCP server type specified: #{config[:type].inspect}"
      end

      # Discovers tools from a connected MCP client and registers them.
      # @param client [ADK::Mcp::Client]
      def discover_and_register_tools(client)
        ADK.logger.debug("[ConnectionManager] discover_and_register - Registry ID: #{@tool_registry.object_id}")

        mcp_tool_schemas = fetch_tools(client)
        return unless mcp_tool_schemas

        mcp_tool_schemas.each do |schema|
          register_tool_from_schema(schema, client)
        end
      end

      def fetch_tools(client)
        mcp_tool_schemas = client.list_tools
        ADK.logger.debug("[ConnectionManager] list_tools returned: #{mcp_tool_schemas.inspect}")
        ADK.logger.info("Discovered #{mcp_tool_schemas.count} tools from MCP server.")
        mcp_tool_schemas
      rescue ADK::Mcp::McpError => e
        ADK.logger.error("Failed to list tools from MCP server: #{e.message}")
        nil
      rescue StandardError => e
        ADK.logger.error("Unexpected error discovering MCP tools: #{e.class} - #{e.message}")
        nil
      end

      def register_tool_from_schema(schema, client)
        tool_name_sym = schema[:name].to_sym

        # Only register if allowed (if allowed_tool_names is set)
        if @allowed_tool_names.nil? || @allowed_tool_names.include?(tool_name_sym)
          ADK::Mcp::ToolWrapper.from_mcp_schema(schema, client, @tool_registry)
        else
          ADK.logger.debug("Skipping registration of MCP tool '#{tool_name_sym}' as it was not selected in agent definition.")
        end
      end
    end
  end
end
