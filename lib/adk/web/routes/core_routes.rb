# File: lib/adk/web/routes/core_routes.rb
# frozen_string_literal: true

module ADK
  module Web
    module CoreRoutes
      def self.registered(app)
        # GET / - Main welcome page.
        app.get '/' do
          logger.debug("GET / route handler entered (from CoreRoutes)")
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
              logger.error("Health check failed: Definition Store unavailable or connection failed (from CoreRoutes).")
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
