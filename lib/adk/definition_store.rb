# frozen_string_literal: true

require_relative 'definition_store/redis_store'

module ADK
  # Namespace and interface definition for Agent Definition persistence.
  #
  # This module serves as the namespace for different storage implementations
  # (e.g., {RedisStore}) responsible for persisting {ADK::AgentDefinition} data.
  #
  # ## Implementation Contract
  # Any class serving as a definition store must implement the following methods:
  #
  # * `save_definition(name:, description:, tools:, ...)`: Persist a definition.
  # * `get_definition(name)`: Retrieve a definition hash by name.
  # * `update_definition(name, updates)`: Update specific fields.
  # * `delete_definition(name)`: Remove a definition.
  # * `list_definitions`: Return a list of all definitions.
  # * `definition_exists?(name)`: Check for existence.
  #
  # @see ADK::DefinitionStore::RedisStore for the reference implementation.
  module DefinitionStore
    # Error raised when a requested definition cannot be found in the store.
    class NotFoundError < Error; end
  end
end
