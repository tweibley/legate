# frozen_string_literal: true

require_relative 'client'
require_relative 'tool_wrapper'
require_relative 'error'
require 'json'
require 'set'

module ADK
  module Mcp
    # Manages the lifecycle of MCP connections and tool discovery/registration.
    # Decouples connection logic from the Agent class.
    class ConnectionManager
      attr_reader :clients, :config

      # @param config [Array<Hash>, Array<String>, String] Configuration for MCP servers
      def initialize(config)
        @config = _normalize_config(config)
        @clients = []
      end

      # Connects to all configured servers and registers their tools with the registry.
      # @param tool_registry [ADK::ToolRegistry] The registry to register tools into
      # @param selected_tool_names [Set<Symbol>, Array<Symbol>] The set of tool names allowed to be registered (optional)
      def connect_all(tool_registry, selected_tool_names = nil)
        # Convert array to Set for O(1) lookups if provided
        selected_tools = if selected_tool_names
                           selected_tool_names.is_a?(Set) ? selected_tool_names : selected_tool_names.to_set
                         end

        return if @config.empty?

        @config.each do |server_config|
          begin
            client = _connect_single(server_config)
            next unless client

            @clients << client
            _discover_and_register_tools(client, tool_registry, selected_tools)
          rescue StandardError => e
            ADK.logger.error("Unexpected error in MCP connection flow for #{server_config.inspect}: #{e.class} - #{e.message}")
          end
        end
      end

      # Disconnects all active clients.
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

      def _normalize_config(config)
        if config.is_a?(String) && !config.strip.empty?
          begin
            parsed = JSON.parse(config)
            parsed.is_a?(Array) ? parsed : []
          rescue JSON::ParserError => e
            ADK.logger.error("Failed to parse MCP config string: #{e.message}")
            []
          end
        elsif config.is_a?(Array)
          config
        else
          # Handle nil or invalid types by returning empty array
          []
        end
      end

      def _connect_single(server_config)
        # Transform keys to symbols for the client
        symbolized_config = server_config.transform_keys(&:to_sym)

        # Validate type
        unless %w[stdio sse].include?(symbolized_config[:type].to_s)
          ADK.logger.error("Unsupported MCP server type specified: #{symbolized_config[:type].inspect}. Skipping configuration: #{symbolized_config.inspect}")
          return nil
        end

        # Normalize type to symbol for Client (client expects :stdio or :sse symbols)
        symbolized_config[:type] = symbolized_config[:type].to_sym

        ADK.logger.info("Attempting to connect to MCP server: #{symbolized_config.inspect}")

        begin
          client = ADK::Mcp::Client.new(symbolized_config)
          client.connect # This performs handshake and gets capabilities
          client
        rescue ADK::Mcp::ConnectionError, ADK::Mcp::ProtocolError => e
          ADK.logger.error("Failed to connect or handshake with MCP server #{server_config.inspect}: #{e.message}")
          nil
        rescue ADK::Mcp::McpError => e
          ADK.logger.error("MCP-related error connecting to server #{server_config.inspect}: #{e.message}")
          nil
        end
      end

      def _discover_and_register_tools(client, tool_registry, selected_tools)
        ADK.logger.debug("[ConnectionManager] discover_and_register - Registry ID: #{tool_registry.object_id}")
        begin
          mcp_tool_schemas = client.list_tools
          ADK.logger.debug("[ConnectionManager] list_tools returned: #{mcp_tool_schemas.inspect}")
          ADK.logger.info("Discovered #{mcp_tool_schemas.count} tools from MCP server.")

          mcp_tool_schemas.each do |schema|
            tool_name_sym = schema[:name].to_sym

            # Check if tool is selected (only if filter is provided)
            if selected_tools.nil? || selected_tools.include?(tool_name_sym)
              ADK::Mcp::ToolWrapper.from_mcp_schema(schema, client, tool_registry)
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
