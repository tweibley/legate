# frozen_string_literal: true

require_relative 'client'
require_relative 'tool_wrapper'
require 'logger'

module ADK
  module Mcp
    # Manages the lifecycle of MCP (Model Context Protocol) client connections and tool discovery.
    # This class decouples connection management from the main Agent class.
    class ConnectionManager
      attr_reader :clients

      # @param config [Array<Hash>] List of MCP server configurations.
      # @param tool_registry [ADK::ToolRegistry] The registry to register discovered tools into.
      # @param selected_tool_names [Array<Symbol>, Set<Symbol>] Tools explicitly allowed for the agent.
      # @param logger [Logger] Logger instance (defaults to ADK.logger).
      def initialize(config:, tool_registry:, selected_tool_names: [], logger: ADK.logger)
        @config = config || []
        @tool_registry = tool_registry
        @selected_tool_names = selected_tool_names.to_set
        @logger = logger
        @clients = []
      end

      # Connects to all configured MCP servers and registers their tools.
      def connect_all
        return if @config.empty?

        @config.each do |server_config|
          # Transform keys to symbols for the client
          symbolized_config = server_config.transform_keys(&:to_sym)
          @logger.info("Attempting to connect to MCP server: #{symbolized_config.inspect}")

          begin
            # Validate server type
            server_type = symbolized_config[:type].to_s
            unless %w[stdio sse].include?(server_type)
              @logger.error("Unsupported MCP server type specified: #{server_type.inspect}. Skipping configuration.")
              next
            end

            # Explicitly convert known string type values to symbols for Client
            symbolized_config[:type] = server_type.to_sym

            client = ADK::Mcp::Client.new(symbolized_config)
            client.connect # This performs handshake and gets capabilities
            @clients << client
            discover_and_register_tools(client)
          rescue ADK::Mcp::ConnectionError, ADK::Mcp::ProtocolError => e
            @logger.error("Failed to connect or handshake with MCP server #{server_config.inspect}: #{e.message}")
          rescue ADK::Mcp::McpError => e
            @logger.error("MCP-related error connecting to server #{server_config.inspect}: #{e.message}")
          rescue StandardError => e
            @logger.error("Unexpected error connecting to MCP server #{server_config.inspect}: #{e.class} - #{e.message}")
          end
        end
      end

      # Disconnects all active MCP clients.
      def disconnect_all
        return if @clients.empty?

        @clients.each do |client|
          begin
            @logger.info('Disconnecting MCP client...')
            client.disconnect
          rescue StandardError => e
            @logger.error("Error disconnecting MCP client: #{e.message}")
          end
        end
        @clients.clear
      end

      private

      # Discovers tools from a connected MCP client and registers them with the tool registry.
      # @param client [ADK::Mcp::Client]
      def discover_and_register_tools(client)
        @logger.debug("[Mcp::ConnectionManager] discover_and_register - registry ID: #{@tool_registry.object_id}")
        begin
          mcp_tool_schemas = client.list_tools
          @logger.debug("[Mcp::ConnectionManager] list_tools returned: #{mcp_tool_schemas.inspect}")
          @logger.info("Discovered #{mcp_tool_schemas.count} tools from MCP server.")

          mcp_tool_schemas.each do |schema|
            tool_name_sym = schema[:name].to_sym
            if @selected_tool_names.include?(tool_name_sym)
              # Register the wrapper tool class directly into the registry
              ADK::Mcp::ToolWrapper.from_mcp_schema(schema, client, @tool_registry)
            else
              @logger.debug("Skipping registration of MCP tool '#{tool_name_sym}' as it was not selected in agent definition.")
            end
          end
        rescue ADK::Mcp::McpError => e
          @logger.error("Failed to list tools from MCP server: #{e.message}")
        rescue StandardError => e
          @logger.error("Unexpected error discovering MCP tools: #{e.class} - #{e.message}")
        end
      end
    end
  end
end
