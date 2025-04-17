# File: lib/adk/session_service/base.rb
# frozen_string_literal: true

module ADK
  module SessionService
    # Base class for session services
    class Base
      # Returns whether this service persists state
      # @return [Boolean] true if state is persisted, false otherwise
      def persistent?
        false
      end

      # Saves scoped state
      # @param scope [String] The scope of the state ('user', 'app', or 'temp')
      # @param key [String] The key to save
      # @param value [Object] The value to save
      # @raise [NotImplementedError] Must be implemented by subclasses
      def save_scoped_state(scope, key, value)
        raise NotImplementedError, "#{self.class} must implement #save_scoped_state"
      end

      # Loads scoped state
      # @param scope [String] The scope of the state ('user', 'app', or 'temp')
      # @param key [String] The key to load
      # @return [Object, nil] The loaded value or nil if not found
      # @raise [NotImplementedError] Must be implemented by subclasses
      def load_scoped_state(scope, key)
        raise NotImplementedError, "#{self.class} must implement #load_scoped_state"
      end

      # Clears scoped state
      # @param scope [String] The scope of the state ('user', 'app', or 'temp')
      # @param key [String] The key to clear
      # @raise [NotImplementedError] Must be implemented by subclasses
      def clear_scoped_state(scope, key)
        raise NotImplementedError, "#{self.class} must implement #clear_scoped_state"
      end
    end
  end
end
