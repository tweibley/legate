# File: lib/legate/web/routes/api_routes.rb
# frozen_string_literal: true

module Legate
  module Web
    module ApiRoutes
      def self.registered(app)
        # GET /api/agents - List all defined agents and their status.
        app.get '/api/agents' do
          content_type :json
          agents_data = []
          current_app_instance = self # Get current app instance
          definition_store = current_app_instance.instance_variable_get(:@definition_store)
          active_agents_hash = current_app_instance.instance_variable_get(:@agents)

          if definition_store
            begin
              agent_summaries = definition_store.list_definitions
              agents_data = agent_summaries.map do |summary|
                agent_name = summary[:name]
                # @agents is keyed by the agent's STRING name; summary[:name] is a Symbol.
                running_key = agent_name.to_s
                is_running = active_agents_hash.key?(running_key)
                current_model = if is_running && active_agents_hash[running_key]
                                  active_agents_hash[running_key].model_name
                                else
                                  summary[:model]
                                end
                {
                  name: agent_name,
                  description: summary[:description] || 'N/A',
                  running: is_running,
                  model: current_model
                }
              end
            rescue Legate::DefinitionStore::StoreError => e
              logger.error("Store error fetching agent list for API (from ApiRoutes): #{e.message}")
              agents_data = []
            end
          else
            logger.error('Definition Store unavailable during GET /api/agents (from ApiRoutes)')
          end
          json agents: agents_data.sort_by { |a| a[:name] }
        end

        # GET /api/tools - List all available *native* tools known to the GlobalToolManager.
        # Does not include MCP tools.
        # Returns JSON: `{"tools": [{"name": ..., "description": ..., "parameters": [...]}, ...]}`
        app.get '/api/tools' do
          content_type :json
          json tools: Legate::GlobalToolManager.list_all_tools
        end
      end
    end
  end
end
