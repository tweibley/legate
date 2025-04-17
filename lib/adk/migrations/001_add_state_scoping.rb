# File: lib/adk/migrations/001_add_state_scoping.rb
# frozen_string_literal: true

module ADK
  module Migrations
    # Migration to add state scoping support
    module AddStateScoping
      class << self
        def migrate(session_service)
          ADK.logger.info("Starting state scoping migration...")

          case session_service
          when SessionService::Redis
            migrate_redis(session_service)
          when SessionService::InMemory
            migrate_in_memory(session_service)
          else
            ADK.logger.warn("Unknown session service type: #{session_service.class}")
          end

          ADK.logger.info("Completed state scoping migration")
        end

        private

        def migrate_redis(service)
          # Get all session IDs
          session_ids = service.redis_client.smembers(ADK::SessionService::Redis::REDIS_SESSIONS_SET_KEY)

          session_ids.each do |session_id|
            session_key = service.send(:redis_session_key, session_id)

            # Get current state
            state_json = service.redis_client.hget(session_key, 'state')
            next unless state_json

            begin
              state = JSON.parse(state_json, symbolize_names: true)

              # Convert any user: or app: prefixed keys to scoped state
              state.each do |key, value|
                if key.to_s.include?(':')
                  prefix, real_key = key.to_s.split(':', 2)
                  if %w[user app].include?(prefix)
                    # Save to scoped state
                    service.save_scoped_state(prefix, real_key, value)
                    # Remove from session state
                    state.delete(key)
                  end
                end
              end

              # Update session state if any keys were moved
              if state != JSON.parse(state_json, symbolize_names: true)
                service.redis_client.hset(session_key, 'state', JSON.generate(state))
              end
            rescue JSON::ParserError => e
              ADK.logger.error("Failed to parse state JSON for session #{session_id}: #{e.message}")
            end
          end
        end

        def migrate_in_memory(service)
          service.sessions.each do |session|
            state = session.state_to_h

            # Convert any user: or app: prefixed keys to scoped state
            state.each do |key, value|
              if key.to_s.include?(':')
                prefix, real_key = key.to_s.split(':', 2)
                if %w[user app].include?(prefix)
                  # Save to scoped state
                  service.save_scoped_state(prefix, real_key, value)
                  # Remove from session state
                  session.delete_state(key)
                end
              end
            end
          end
        end
      end
    end
  end
end
