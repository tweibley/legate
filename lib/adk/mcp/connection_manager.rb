# frozen_string_literal: true

require 'logger'
require 'json'
require_relative 'client'
require_relative 'tool_wrapper'
require_relative 'error' # Ensure error classes are available

module ADK
  module Mcp
    # Manages MCP connections, tool discovery, and registration for an Agent.
    class ConnectionManager
      attr_reader :clients

      # @param config [Array<Hash>, String] The MCP servers configuration.
      # @param tool_registry [ADK::ToolRegistry] The tool registry to register tools with.
      # @param selected_tool_names [Set<Symbol>, Array<Symbol>] List of tools selected for the agent.
      # @param agent_name [Symbol, String, nil] Name of the agent (for logging context).
      def initialize(config, tool_registry, selected_tool_names, agent_name: nil)
        @config = _parse_config(config)
        @tool_registry = tool_registry
        @selected_tool_names = selected_tool_names.to_a.map(&:to_sym) # Normalize to array of symbols
        @agent_name = agent_name
        @clients = []
      end

      # Connects to all configured MCP servers.
      def connect_all
        return if @config.empty?

        @config.each do |server_config|
          # Transform keys to symbols for the client
          symbolized_config = server_config.transform_keys(&:to_sym)
          log_info("Attempting to connect to MCP server: #{symbolized_config.inspect}")

          begin
            # Validate type
            unless %w[stdio sse].include?(symbolized_config[:type].to_s)
              ADK.logger.error("Unsupported MCP server type specified: #{symbolized_config[:type].inspect}. Skipping.")
              next
            end

            # Normalize type to symbol
            symbolized_config[:type] = symbolized_config[:type].to_sym

            client = ADK::Mcp::Client.new(symbolized_config)
            client.connect # This performs handshake and gets capabilities
            @clients << client
            _discover_and_register_tools(client)
          rescue ADK::Mcp::ConnectionError, ADK::Mcp::ProtocolError => e
            ADK.logger.error("Failed to connect or handshake with MCP server #{server_config.inspect}: #{e.message}")
          rescue ADK::Mcp::McpError => e
            ADK.logger.error("MCP-related error connecting to server #{server_config.inspect}: #{e.message}")
          rescue StandardError => e
            ADK.logger.error("Unexpected error connecting to MCP server #{server_config.inspect}: #{e.class} - #{e.message}")
          end
        end
      end

      # Disconnects all active MCP clients.
      def disconnect_all
        return if @clients.empty?

        @clients.each do |client|
          log_info('Disconnecting MCP client...')
          client.disconnect
        rescue StandardError => e
          ADK.logger.error("Error disconnecting MCP client: #{e.message}")
        end
        @clients.clear
      end

      private

      # Parses the configuration into an array of hashes
      def _parse_config(config)
        if config.is_a?(String) && !config.strip.empty?
          begin
            parsed = JSON.parse(config)
            parsed.is_a?(Array) ? parsed : []
          rescue JSON::ParserError => e
            prefix = @agent_name ? "Agent '#{@agent_name}': " : ''
            ADK.logger.error("#{prefix}Failed to parse MCP server config JSON: #{e.message}")
            []
          end
        elsif config.is_a?(Array)
          config
        else
          prefix = @agent_name ? "Agent '#{@agent_name}': " : ''
          ADK.logger.debug("#{prefix}No valid MCP server config provided. Defaulting to empty array.")
          []
        end
      end

      # Discovers tools from a connected MCP client and registers them.
      def _discover_and_register_tools(client)
        ADK.logger.debug("[ConnectionManager] discover_and_register - registry: #{@tool_registry.object_id}")
        begin
          mcp_tool_schemas = client.list_tools
          ADK.logger.debug("[ConnectionManager] list_tools returned: #{mcp_tool_schemas.inspect}")
          log_info("Discovered #{mcp_tool_schemas.count} tools from MCP server.")

          mcp_tool_schemas.each do |schema|
            tool_name_sym = schema[:name].to_sym
            if @selected_tool_names.include?(tool_name_sym)
              # Pass the registry instance
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

      def log_info(msg)
        prefix = @agent_name ? "Agent '#{@agent_name}': " : '[ConnectionManager] '
        ADK.logger.info("#{prefix}#{msg}")
      end
    end
  end
end
