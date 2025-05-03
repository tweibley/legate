# File: lib/adk/global_definition_registry.rb
# frozen_string_literal: true

module ADK
  # Simple in-memory registry for AgentDefinition instances.
  # This allows components like the WebhookListener to access the non-serializable
  # parts of a definition (like transformer/extractor Procs) that are lost
  # when retrieving the definition hash from a persistent store (like Redis).
  module GlobalDefinitionRegistry
    @registry = {}

    # Registers an AgentDefinition instance.
    # @param definition [ADK::AgentDefinition] The definition object to register.
    def self.register(definition)
      unless definition.is_a?(ADK::AgentDefinition) && definition.name.is_a?(Symbol)
        ADK.logger.error("GlobalDefinitionRegistry: Invalid object passed to register: #{definition.inspect}")
        return false
      end

      name = definition.name
      if @registry.key?(name)
        ADK.logger.warn("GlobalDefinitionRegistry: Overwriting existing definition for agent :#{name}")
      end
      @registry[name] = definition
      ADK.logger.debug("GlobalDefinitionRegistry: Registered definition for :#{name}")
      true
    end

    # Finds an AgentDefinition instance by name.
    # @param name [Symbol] The name of the agent definition.
    # @return [ADK::AgentDefinition, nil] The definition object or nil if not found.
    def self.find(name)
      unless name.is_a?(Symbol)
        ADK.logger.warn("GlobalDefinitionRegistry: Find called with non-symbol key: #{name.inspect}")
        return nil
      end
      @registry[name]
    end

    # Clears the registry (primarily for testing).
    def self.clear!
      @registry = {}
      ADK.logger.debug("GlobalDefinitionRegistry: Cleared.")
    end

    # Returns the current registry hash (primarily for debugging/inspection).
    # @return [Hash{Symbol => ADK::AgentDefinition}]
    def self.all
      @registry.dup # Return a copy
    end
  end
end
