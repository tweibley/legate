# frozen_string_literal: true

require_relative 'client'
require_relative 'tool_wrapper'

module ADK
  module Mcp
    class ConnectionManager
      def initialize(tool_registry, allowed_tool_names)
        @registry = tool_registry
        @allowed = allowed_tool_names
        @clients = []
      end

      def connect(configs)
        (configs || []).each do |cfg|
          cfg = cfg.transform_keys(&:to_sym)
          cfg[:type] = cfg[:type].to_sym if cfg[:type].is_a?(String)

          unless %i[stdio sse].include?(cfg[:type])
            ADK.logger.error("Unsupported MCP type: #{cfg[:type]}")
            next
          end

          begin
            client = Client.new(cfg).tap(&:connect)
            @clients << client
            register_tools(client)
          rescue StandardError => e
            ADK.logger.error("MCP Connect Error: #{e.message}")
          end
        end
      end

      def disconnect
        @clients.each { |c|
          begin
            c.disconnect
          rescue StandardError
            nil
          end
        }
        @clients.clear
      end

      private

      def register_tools(client)
        client.list_tools.each do |schema|
          next unless @allowed.include?(schema[:name].to_sym)

          ToolWrapper.from_mcp_schema(schema, client, @registry)
        end
      rescue StandardError => e
        ADK.logger.error("MCP Discovery Error: #{e.message}")
      end
    end
  end
end
