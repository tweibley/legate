# File: lib/adk/web/routes/tools_ui_routes.rb
# frozen_string_literal: true

module ADK
  module Web
    module ToolsUIRoutes
      def self.registered(app)
        # GET /tools - Display available native and MCP tools
        app.get '/tools' do
          logger.info("GET /tools route handler entered (from ToolsUIRoutes)")
          
          current_app_instance = self
          definition_store = current_app_instance.instance_variable_get(:@definition_store)

          # 1. Get Native Tools (already formatted)
          native_tools_metadata = ADK::GlobalToolManager.list_all_tools.map do |tool_meta|
            parameters_array = []
            if tool_meta[:parameters].is_a?(Hash) && !tool_meta[:parameters].empty?
              tool_meta[:parameters].each do |param_name, details|
                parameters_array << {
                  name: param_name,
                  type: details[:type],
                  description: details[:description],
                  required: details[:required]
                }
              end
            end
            tool_meta.merge(parameters: parameters_array, source: :native, source_detail: "Native")
          end

          # 2. Get MCP Tools
          all_mcp_configs = []
          if definition_store
            begin
              agent_summaries = definition_store.list_definitions
              all_mcp_configs = agent_summaries.flat_map do |summary|
                mcp_json = summary[:mcp_servers_json]
                if mcp_json && !mcp_json.empty? && mcp_json != '[]'
                  JSON.parse(mcp_json)
                else
                  []
                end
              end.uniq
            rescue JSON::ParserError => e
              logger.error("Error parsing MCP JSON for /tools (from ToolsUIRoutes): #{e.message}")
            rescue ADK::DefinitionStore::StoreError => e
              logger.error("Store error fetching agent definitions for /tools (from ToolsUIRoutes): #{e.message}")
            end
          else
            logger.warn("Definition store not available for MCP tool discovery in /tools (from ToolsUIRoutes)")
          end
          
          mcp_tool_fetch_results = fetch_mcp_tools(all_mcp_configs || [])

          processed_mcp_tools_metadata = []
          mcp_tool_fetch_results.each do |result|
            if result[:status] == :success && result[:tools]
              result[:tools].each do |mcp_tool_schema|
                parameters = []
                begin
                  input_schema = mcp_tool_schema[:inputSchema]
                  if input_schema && input_schema.is_a?(Hash)
                    properties = input_schema['properties'] || {}
                    required_props = input_schema['required'] || []
                    parameters = ADK::Mcp::Util::SchemaConverter.json_to_adk(properties, required_props)
                  end
                rescue => e
                  logger.error("Error converting MCP schema for tool '#{mcp_tool_schema[:name]}' in /tools (from ToolsUIRoutes): #{e.message}")
                end
                processed_mcp_tools_metadata << { 
                  name: mcp_tool_schema[:name].to_sym,
                  description: mcp_tool_schema[:description] || "",
                  parameters: parameters,
                  source: :mcp,
                  source_detail: "MCP (#{result[:server]})" 
                }
              end
            end
          end

          # 3. Set @native_tools for the current view requirements
          self.instance_variable_set(:@native_tools, native_tools_metadata.sort_by { |t| t[:name].to_s })
          
          # For future enhancement of tools.slim to show all tools:
          combined_tools_map = {}
          native_tools_metadata.each { |tool| combined_tools_map[tool[:name]] = tool }
          processed_mcp_tools_metadata.each { |tool| combined_tools_map[tool[:name]] ||= tool } 
          self.instance_variable_set(:@all_tools_list, combined_tools_map.values.sort_by { |t| t[:name].to_s })
          self.instance_variable_set(:@mcp_tool_results_for_view, mcp_tool_fetch_results) # For displaying fetch errors

          slim :tools
        end

        # GET /tools/:name - Display tool detail page (native or MCP)
        app.get '/tools/:name' do |name|
          logger.info("GET /tools/#{name} route handler entered (from ToolsUIRoutes)")
          tool_name_sym = name.to_sym
          
          current_app_instance = self
          definition_store = current_app_instance.instance_variable_get(:@definition_store)

          # 1. Try to find in native tools
          native_tool_metadata = ADK::GlobalToolManager.list_all_tools.find { |t| t[:name] == tool_name_sym }
          tool_to_display = nil

          if native_tool_metadata
            parameters_array = []
            if native_tool_metadata[:parameters].is_a?(Hash) && !native_tool_metadata[:parameters].empty?
              native_tool_metadata[:parameters].each do |param_name, details|
                parameters_array << {
                  name: param_name,
                  type: details[:type],
                  description: details[:description],
                  required: details[:required]
                }
              end
            end
            tool_to_display = native_tool_metadata.merge(parameters: parameters_array, source: :native, source_detail: "Native")
          else
            # 2. Not native, try to find in MCP tools
            all_mcp_configs = []
            if definition_store
              begin
                agent_summaries = definition_store.list_definitions
                all_mcp_configs = agent_summaries.flat_map do |summary|
                  mcp_json = summary[:mcp_servers_json]
                  if mcp_json && !mcp_json.empty? && mcp_json != '[]'
                    JSON.parse(mcp_json)
                  else
                    []
                  end
                end.uniq
              rescue JSON::ParserError => e
                logger.error("Error parsing MCP JSON for /tools/#{name} (from ToolsUIRoutes): #{e.message}")
              rescue ADK::DefinitionStore::StoreError => e
                logger.error("Store error fetching agent definitions for /tools/#{name} (from ToolsUIRoutes): #{e.message}")
              end
            else
              logger.warn("Definition store not available for MCP tool discovery in /tools/#{name} (from ToolsUIRoutes)")
            end

            mcp_tool_fetch_results = fetch_mcp_tools(all_mcp_configs || [])
            
            mcp_tool_fetch_results.each do |result|
              if result[:status] == :success && result[:tools]
                tool_data = result[:tools].find { |t| t[:name].to_s == name || t[:name].to_sym == tool_name_sym }
                if tool_data
                  parameters = []
                  begin
                    input_schema = tool_data[:inputSchema]
                    if input_schema && input_schema.is_a?(Hash)
                      properties = input_schema['properties'] || {}
                      required_props = input_schema['required'] || []
                      parameters = ADK::Mcp::Util::SchemaConverter.json_to_adk(properties, required_props)
                    end
                  rescue => e
                    logger.error("Error converting MCP schema for tool '#{tool_data[:name]}' in /tools/#{name} (from ToolsUIRoutes): #{e.message}")
                  end
                  tool_to_display = {
                    name: tool_data[:name].to_sym,
                    description: tool_data[:description] || "",
                    parameters: parameters,
                    source: :mcp,
                    source_detail: "MCP (#{result[:server]})"
                  }
                  break 
                end
              end
            end
          end

          if tool_to_display
            self.instance_variable_set(:@tool, tool_to_display)
            logger.debug("Found tool metadata for '#{name}': #{tool_to_display.inspect}")
            slim :tool 
          else
            logger.warn("Tool '#{name}' not found anywhere (from ToolsUIRoutes).")
            status 404
            slim(:error_404,
                 locals: { title: "Tool Not Found", message: "Tool definition for '#{name}' not found." })
          end
        end
      end
    end
  end
end 