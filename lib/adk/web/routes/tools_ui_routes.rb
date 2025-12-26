# File: lib/adk/web/routes/tools_ui_routes.rb
# frozen_string_literal: true

module ADK
  module Web
    module ToolsUIRoutes
      def self.registered(app)
        # GET /tools - Display available native and MCP tools
        app.get '/tools' do
          logger.info('GET /tools route handler entered (from ToolsUIRoutes)')

          # 1. Get Native Tools
          native_tools_metadata = ADK::Web::ToolsUIRoutes.get_native_tools_metadata

          # 2. Get MCP Tools
          definition_store = instance_variable_get(:@definition_store)
          all_mcp_configs = ADK::Web::ToolsUIRoutes.get_mcp_configs(definition_store, logger)
          mcp_tool_fetch_results = fetch_mcp_tools(all_mcp_configs)
          processed_mcp_tools_metadata = ADK::Web::ToolsUIRoutes.process_mcp_tools(mcp_tool_fetch_results, logger)

          # 3. Set variables for view
          instance_variable_set(:@native_tools, native_tools_metadata.sort_by { |t| t[:name].to_s })

          combined_tools_map = {}
          native_tools_metadata.each { |tool| combined_tools_map[tool[:name]] = tool }
          processed_mcp_tools_metadata.each { |tool| combined_tools_map[tool[:name]] ||= tool }
          instance_variable_set(:@all_tools_list, combined_tools_map.values.sort_by { |t| t[:name].to_s })
          instance_variable_set(:@mcp_tool_results_for_view, mcp_tool_fetch_results)

          slim :tools
        end

        # GET /tools/:name - Display tool detail page (native or MCP)
        app.get '/tools/:name' do |name|
          logger.info("GET /tools/#{name} route handler entered (from ToolsUIRoutes)")
          tool_name_sym = name.to_sym
          tool_to_display = nil

          # 1. Try to find in native tools
          native_tool = ADK::GlobalToolManager.list_all_tools.find { |t| t[:name] == tool_name_sym }
          if native_tool
            parameters_array = ADK::Web::ToolsUIRoutes.format_tool_parameters(native_tool[:parameters])
            tool_to_display = native_tool.merge(parameters: parameters_array, source: :native, source_detail: 'Native')
          else
            # 2. Not native, try to find in MCP tools
            definition_store = instance_variable_get(:@definition_store)
            all_mcp_configs = ADK::Web::ToolsUIRoutes.get_mcp_configs(definition_store, logger)
            mcp_tool_fetch_results = fetch_mcp_tools(all_mcp_configs)

            mcp_tool_fetch_results.each do |result|
              next unless result[:status] == :success && result[:tools]

              tool_data = result[:tools].find { |t| t[:name].to_s == name || t[:name].to_sym == tool_name_sym }
              next unless tool_data

              parameters = ADK::Web::ToolsUIRoutes.convert_mcp_schema_to_adk(tool_data, logger)
              tool_to_display = {
                name: tool_data[:name].to_sym,
                description: tool_data[:description] || '',
                parameters: parameters,
                source: :mcp,
                source_detail: "MCP (#{result[:server]})"
              }
              break
            end
          end

          if tool_to_display
            instance_variable_set(:@tool, tool_to_display)
            logger.debug("Found tool metadata for '#{name}': #{tool_to_display.inspect}")
            slim :tool_detail
          else
            logger.warn("Tool '#{name}' not found anywhere (from ToolsUIRoutes).")
            status 404
            slim(:error_404, locals: { title: 'Tool Not Found', message: "Tool definition for '#{name}' not found." })
          end
        end

        # GET /tools/:name/download - Download native tool as Ruby file
        app.get '/tools/:name/download' do |name|
          logger.info("Received request to download tool '#{name}' as Ruby file")
          tool_name_sym = name.to_sym
          tool_class = ADK::GlobalToolManager.find_class(tool_name_sym)
          halt 400, 'Only native tools can be downloaded as Ruby files. MCP tools cannot be exported.' unless tool_class

          require 'adk/tool_code_generator'
          ruby_code = ADK::ToolCodeGenerator.generate(tool_name_sym)
          halt 404, 'Tool not found or could not generate code.' unless ruby_code

          content_type 'application/x-ruby'
          attachment "#{name.to_s.gsub(/[^a-zA-Z0-9_-]/, '_')}.rb"
          ruby_code
        end
      end

      # Helper methods
      def self.get_native_tools_metadata
        ADK::GlobalToolManager.list_all_tools.map do |tool_meta|
          parameters_array = format_tool_parameters(tool_meta[:parameters])
          tool_meta.merge(parameters: parameters_array, source: :native, source_detail: 'Native')
        end
      end

      def self.format_tool_parameters(parameters)
        return [] unless parameters.is_a?(Hash) && !parameters.empty?

        parameters.map do |param_name, details|
          {
            name: param_name,
            type: details[:type],
            description: details[:description],
            required: details[:required]
          }
        end
      end

      def self.get_mcp_configs(definition_store, logger)
        return [] unless definition_store

        begin
          agent_summaries = definition_store.list_definitions
          agent_summaries.flat_map do |summary|
            mcp_json = summary[:mcp_servers_json]
            if mcp_json && !mcp_json.empty? && mcp_json != '[]'
              JSON.parse(mcp_json)
            else
              []
            end
          end.uniq
        rescue JSON::ParserError => e
          logger.error("Error parsing MCP JSON (from ToolsUIRoutes): #{e.message}")
          []
        rescue ADK::DefinitionStore::StoreError => e
          logger.error("Store error fetching agent definitions (from ToolsUIRoutes): #{e.message}")
          []
        end
      end

      def self.process_mcp_tools(mcp_tool_fetch_results, logger)
        processed_tools = []
        mcp_tool_fetch_results.each do |result|
          next unless result[:status] == :success && result[:tools]

          result[:tools].each do |mcp_tool_schema|
            parameters = convert_mcp_schema_to_adk(mcp_tool_schema, logger)
            processed_tools << {
              name: mcp_tool_schema[:name].to_sym,
              description: mcp_tool_schema[:description] || '',
              parameters: parameters,
              source: :mcp,
              source_detail: "MCP (#{result[:server]})"
            }
          end
        end
        processed_tools
      end

      def self.convert_mcp_schema_to_adk(tool_schema, logger)
        input_schema = tool_schema[:inputSchema]
        return [] unless input_schema.is_a?(Hash)

        begin
          properties = input_schema['properties'] || {}
          required_props = input_schema['required'] || []
          ADK::Mcp::Util::SchemaConverter.json_to_adk(properties, required_props)
        rescue StandardError => e
          logger.error("Error converting MCP schema for tool '#{tool_schema[:name]}' (from ToolsUIRoutes): #{e.message}")
          []
        end
      end
    end
  end
end
