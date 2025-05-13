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

      def append_event(session_id:, event:)
        raise NotImplementedError, "#{self.class.name} must implement #append_event."
      end

      # Sets a key-value pair in the state associated with the session.
      # This typically involves finding the session and then calling the session object's
      # own state management methods (e.g., session.set_state(key, value)).
      # @param session_id [String] The ID of the session.
      # @param key [Symbol] The key for the state entry (should not have service-level prefixes like user: or app:).
      # @param value [Object] The value to store.
      # @return [void]
      # @raise [NotImplementedError] If the subclass does not implement this method.
      def set_state(session_id:, key:, value:)
        raise NotImplementedError, "#{self.class.name} must implement #set_state."
      end

      # Retrieves a value from the state associated with the session.
      # This typically involves finding the session and then calling the session object's
      # own state management methods (e.g., session.get_state(key)).
      # @param session_id [String] The ID of the session.
      # @param key [Symbol] The key for the state entry (should not have service-level prefixes).
      # @return [Object, nil] The value if found, or nil.
      # @raise [NotImplementedError] If the subclass does not implement this method.
      def get_state(session_id:, key:)
        raise NotImplementedError, "#{self.class.name} must implement #get_state."
      end
    end
  end
end
