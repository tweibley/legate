# frozen_string_literal: true

require_relative 'client'
require_relative 'tool_wrapper'
require 'logger'

module ADK
  module Mcp
    # Manages the lifecycle of MCP connections for an agent.
    # Encapsulates connection, tool discovery, and disconnection logic.
    class ConnectionManager
      attr_reader :clients

      # @param agent_name [String] Name of the agent (for logging)
      # @param tool_registry [ADK::ToolRegistry] The agent's tool registry
      # @param configs [Array<Hash>] List of MCP server configurations
      # @param selected_tool_names [Set<Symbol>, Array<Symbol>] Tool names allowed for this agent
      def initialize(agent_name:, tool_registry:, configs:, selected_tool_names:)
        @agent_name = agent_name
        @tool_registry = tool_registry
        @configs = configs || []
        @selected_tool_names = selected_tool_names || []
        @clients = []
      end

      # Connects to all configured MCP servers.
      def connect_all
        return if @configs.empty?

        @configs.each { |config| connect_server(config) }
      end

      # Disconnects all active MCP clients.
      def disconnect_all
        return if @clients.empty?

        @clients.each do |client|
          ADK.logger.info("Agent '#{@agent_name}': Disconnecting MCP client...")
          client.disconnect
        rescue StandardError => e
          ADK.logger.error("Error disconnecting MCP client: #{e.message}")
        end
        @clients.clear
      end

      private

      def connect_server(config)
        # Transform keys to symbols for the client
        symbolized_config = config.transform_keys(&:to_sym)
        ADK.logger.info("Agent '#{@agent_name}': Attempting to connect to MCP server: #{symbolized_config.inspect}")

        begin
          validate_and_connect(symbolized_config, config)
        rescue ADK::Mcp::ConnectionError, ADK::Mcp::ProtocolError => e
          ADK.logger.error("Failed to connect or handshake with MCP server #{config.inspect}: #{e.message}")
        rescue ADK::Mcp::McpError => e
          ADK.logger.error("MCP-related error connecting to server #{config.inspect}: #{e.message}")
        rescue StandardError => e
          ADK.logger.error("Unexpected error connecting to MCP server #{config.inspect}: #{e.class} - #{e.message}")
        end
      end

      def validate_and_connect(symbolized_config, _original_config)
        # Check type validity
        unless %w[stdio sse].include?(symbolized_config[:type].to_s)
          ADK.logger.error("Unsupported MCP server type specified: #{symbolized_config[:type].inspect}. Skipping configuration: #{symbolized_config.inspect}")
          return
        end

        # Explicitly convert known string type values to symbols
        symbolized_config[:type] = symbolized_config[:type].to_sym

        client = ADK::Mcp::Client.new(symbolized_config)
        client.connect
        @clients << client
        discover_and_register_tools(client)
      end

      def discover_and_register_tools(client)
        ADK.logger.debug("[ConnectionManager] discover_and_register - @tool_registry ID: #{@tool_registry.object_id}")

        mcp_tool_schemas = client.list_tools
        ADK.logger.info("Discovered #{mcp_tool_schemas.count} tools from MCP server.")
        mcp_tool_schemas.each do |schema|
          register_tool_if_selected(schema, client)
        end
      rescue ADK::Mcp::McpError => e
        ADK.logger.error("Failed to list tools from MCP server: #{e.message}")
      rescue StandardError => e
        ADK.logger.error("Unexpected error discovering MCP tools: #{e.class} - #{e.message}")
      end

      def register_tool_if_selected(schema, client)
        tool_name_sym = schema[:name].to_sym
        if @selected_tool_names.include?(tool_name_sym)
          ADK::Mcp::ToolWrapper.from_mcp_schema(schema, client, @tool_registry)
        else
          ADK.logger.debug("Skipping registration of MCP tool '#{tool_name_sym}' as it was not selected in agent definition.")
        end
      end
    end
  end
end
