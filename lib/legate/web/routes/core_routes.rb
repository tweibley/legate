# File: lib/legate/web/routes/core_routes.rb
# frozen_string_literal: true

module Legate
  module Web
    module CoreRoutes
      def self.registered(app)
        # GET / - Main welcome page with dashboard metrics.
        app.get '/' do
          logger.debug('GET / route handler entered (from CoreRoutes)')

          # Compute dashboard metrics
          definition_store = instance_variable_get(:@definition_store)
          tool_manager = instance_variable_get(:@tool_manager)

          @agent_count = 0
          @running_count = 0
          @tool_count = 0
          @auth_scheme_count = 0

          if definition_store
            definitions = begin
              definition_store.list_definitions
            rescue StandardError
              []
            end
            @agent_count = definitions.size
          end
          # Running count is based on in-memory @agents hash
          active_agents_hash = instance_variable_get(:@agents)
          @running_count = active_agents_hash&.size || 0

          if tool_manager
            @tool_count = begin
              tool_manager.tools.size
            rescue StandardError
              0
            end
          end

          # Count auth schemes (best-effort; the dashboard must never break).
          # Was checking the wrong constant (Legate::Authentication::Manager),
          # so this count never displayed.
          @auth_scheme_count = begin
            Legate::Auth::Manager.instance.schemes.size
          rescue StandardError
            0
          end

          # Fetch recent activity
          @recent_activity = if defined?(Legate::ActivityLog)
                               begin
                                 Legate::ActivityLog.recent(8)
                               rescue StandardError
                                 []
                               end
                             else
                               []
                             end

          slim :index
        end

        # GET /activity/recent - Returns recent activity HTML partial
        app.get '/activity/recent' do
          @recent_activity = if defined?(Legate::ActivityLog)
                               begin
                                 Legate::ActivityLog.recent(8)
                               rescue StandardError
                                 []
                               end
                             else
                               []
                             end

          slim :_activity_list, layout: false
        end

        # GET /healthz - Standard health check endpoint.
        app.get '/healthz' do
          current_app_instance = self
          definition_store = current_app_instance.instance_variable_get(:@definition_store)

          store_ok = if definition_store
                       definition_store.check_connection
                     else
                       true # No persistence configured (in-memory mode)
                     end

          unless store_ok
            logger.error('Health check failed: Definition Store unavailable or connection failed (from CoreRoutes).')
            status 503
            body 'Service Unavailable (Persistence)'
            return
          end

          status 200
          body 'OK'
        rescue Legate::DefinitionStore::StoreError => e
          logger.error("Health check failed (from CoreRoutes): Store error - #{e.message}")
          status 503
          body 'Service Unavailable (Persistence Error)'
        rescue StandardError => e # Catch other unexpected errors
          logger.error("Health check failed (from CoreRoutes): Unexpected error - #{e.class}: #{e.message}")
          status 503
          body 'Service Unavailable (Internal)'
        end
      end
    end
  end
end
