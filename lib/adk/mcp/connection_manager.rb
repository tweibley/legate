# frozen_string_literal: true

require 'json'
require_relative 'client'

module ADK
  module Mcp
    # Manages the lifecycle of MCP connections for an agent.
    class ConnectionManager
      attr_reader :active_clients

      def initialize(server_configs, logger = ADK.logger)
        @logger = logger
        @configs = parse_configs(server_configs)
        @active_clients = []
      end

      def connect_all
        return if @configs.empty?

        @configs.each do |config|
          connect_client(config) do |client|
            yield client if block_given?
          end
        end
      end

      def disconnect_all
        @active_clients.each do |client|
          safe_disconnect(client)
        end
        @active_clients.clear
      end

      private

      def connect_client(config)
        client = ADK::Mcp::Client.new(config)
        client.connect
        @active_clients << client
        yield client
      rescue StandardError => e
        @logger.error("Failed to connect to MCP server #{config}: #{e.message}")
      end

      def safe_disconnect(client)
        client.disconnect
      rescue StandardError => e
        @logger.error("Error disconnecting MCP client: #{e.message}")
      end

      def parse_configs(configs)
        return [] if configs.nil? || (configs.respond_to?(:empty?) && configs.empty?)

        # Handle JSON string parsing if needed (legacy agent behavior)
        parsed = parse_json_configs(configs)
        return [] unless parsed.is_a?(Array)

        parsed.map { |c| normalize_config(c) }.compact
      end

      def parse_json_configs(configs)
        configs.is_a?(String) ? JSON.parse(configs, symbolize_names: true) : configs
      rescue JSON::ParserError
        @logger.warn('Invalid MCP config format')
        []
      end

      def normalize_config(config)
        sym_config = config.transform_keys(&:to_sym)
        unless %w[stdio sse].include?(sym_config[:type].to_s)
          @logger.error("Unsupported MCP server type: #{sym_config[:type]}")
          return nil
        end
        sym_config[:type] = sym_config[:type].to_sym
        sym_config
      end
    end
  end
end
