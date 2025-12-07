# File: lib/adk/web/routes/core_routes.rb
# frozen_string_literal: true

module ADK
  module Web
    module CoreRoutes
      def self.registered(app)
        # GET / - Main welcome page with dashboard metrics.
        app.get '/' do
          logger.debug('GET / route handler entered (from CoreRoutes)')
          
          # Compute dashboard metrics
          definition_store = self.instance_variable_get(:@definition_store)
          tool_manager = self.instance_variable_get(:@tool_manager)
          
          @agent_count = 0
          @running_count = 0
          @tool_count = 0
          @auth_scheme_count = 0
          
          if definition_store
            definitions = definition_store.list_definitions rescue []
            @agent_count = definitions.size
            @running_count = definitions.count { |d| d[:running] == true }
          end
          
          if tool_manager
            @tool_count = tool_manager.tools.size rescue 0
          end
          
          # Count auth schemes if available
          if defined?(ADK::Authentication::Manager) && ADK::Authentication::Manager.respond_to?(:instance)
            auth_manager = ADK::Authentication::Manager.instance rescue nil
            @auth_scheme_count = auth_manager&.available_schemes&.size || 0
          end
          
          slim :index
        end

        # GET /healthz - Standard health check endpoint.
        app.get '/healthz' do
          begin
            current_app_instance = self
            definition_store = current_app_instance.instance_variable_get(:@definition_store)

            store_ok = if definition_store
                         definition_store.check_connection
                       else
                         false # Store not initialized
                       end

            unless store_ok
              logger.error('Health check failed: Definition Store unavailable or connection failed (from CoreRoutes).')
              status 503
              body 'Service Unavailable (Persistence)'
              return
            end

            status 200
            body 'OK'
          rescue ADK::DefinitionStore::StoreError => e
            logger.error("Health check failed (from CoreRoutes): Store error - #{e.message}")
            status 503
            body 'Service Unavailable (Persistence Error)'
          rescue => e # Catch other unexpected errors
            logger.error("Health check failed (from CoreRoutes): Unexpected error - #{e.class}: #{e.message}")
            status 503
            body 'Service Unavailable (Internal)'
          end
        end
      end
    end
  end
end
