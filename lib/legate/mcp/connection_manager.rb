# File: lib/legate/mcp/connection_manager.rb
# frozen_string_literal: true

require_relative 'client'
require_relative 'tool_wrapper'

module Legate
  module Mcp
    # Owns an agent's MCP client connections: connecting to configured servers,
    # discovering and registering their tools into the agent's tool registry, and
    # disconnecting. Extracted from Legate::Agent to keep MCP lifecycle out of the
    # agent's core responsibilities.
    class ConnectionManager
      attr_reader :clients

      # @param tool_registry [Legate::ToolRegistry] the agent's registry that MCP tools register into
      # @param selected_tool_names [Array<Symbol>] tool names the agent selected (others are skipped)
      # @param agent_name [Symbol, String] for log context
      def initialize(tool_registry:, selected_tool_names:, agent_name:)
        @tool_registry = tool_registry
        @selected_tool_names = selected_tool_names
        @agent_name = agent_name
        @clients = []
      end

      # Connects to each configured MCP server and registers its selected tools.
      # @param servers_config [Array<Hash>, nil] server configs from the definition
      def connect(servers_config)
        return if servers_config.nil? || servers_config.empty?

        servers_config.each do |config|
          # Transform keys to symbols for the client
          symbolized_config = config.transform_keys(&:to_sym)
          Legate.logger.info("Attempting to connect to MCP server: #{symbolized_config.inspect}")
          begin
            unless %w[stdio sse].include?(symbolized_config[:type])
              Legate.logger.error("Unsupported MCP server type specified: #{symbolized_config[:type].inspect}. Skipping configuration: #{symbolized_config.inspect}")
              next # Skip to the next server config
            end

            # Explicitly convert known string type values to symbols
            if symbolized_config[:type] == 'stdio'
              symbolized_config[:type] = :stdio
            elsif symbolized_config[:type] == 'sse'
              symbolized_config[:type] = :sse
            end
            # Pass the modified hash
            client = Legate::Mcp::Client.new(symbolized_config)
            client.connect # This performs handshake and gets capabilities
            @clients << client
            discover_and_register_tools(client)
          rescue Legate::Mcp::ConnectionError, Legate::Mcp::ProtocolError => e # More specific MCP errors
            Legate.logger.error("Failed to connect or handshake with MCP server #{config.inspect}: #{e.message}")
          rescue Legate::Mcp::Error => e
            Legate.logger.error("MCP-related error connecting to server #{config.inspect}: #{e.message}")
          rescue StandardError => e
            Legate.logger.error("Unexpected error connecting to MCP server #{config.inspect}: #{e.class} - #{e.message}")
          end
        end
      end

      # Disconnects all active MCP clients.
      def disconnect
        return if @clients.nil? || @clients.empty?

        @clients.each do |client|
          Legate.logger.info('Disconnecting MCP client...')
          client.disconnect
        rescue StandardError => e
          Legate.logger.error("Error disconnecting MCP client: #{e.message}")
        end
        @clients.clear
      end

      private

      # Discovers tools from a connected MCP client and registers the selected
      # ones with the agent's registry.
      # @param client [Legate::Mcp::Client]
      def discover_and_register_tools(client)
        Legate.logger.debug("[Agent E2E Debug] discover_and_register - @tool_registry ID: #{@tool_registry.object_id}")
        begin
          mcp_tool_schemas = client.list_tools
          Legate.logger.debug("[Agent E2E Debug] list_tools returned: #{mcp_tool_schemas.inspect}")
          Legate.logger.info("Discovered #{mcp_tool_schemas.count} tools from MCP server.")
          mcp_tool_schemas.each do |schema|
            tool_name_sym = schema[:name].to_sym
            if @selected_tool_names.include?(tool_name_sym)
              # Pass the agent's specific registry instance
              Legate::Mcp::ToolWrapper.from_mcp_schema(schema, client, @tool_registry)
            else
              Legate.logger.debug("Skipping registration of MCP tool '#{tool_name_sym}' as it was not selected in agent definition.")
            end
          end
        rescue Legate::Mcp::Error => e
          Legate.logger.error("Failed to list tools from MCP server: #{e.message}")
        rescue StandardError => e
          Legate.logger.error("Unexpected error discovering MCP tools: #{e.class} - #{e.message}")
        end
      end
    end
  end
end
