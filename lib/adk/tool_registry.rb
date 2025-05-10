# File: lib/adk/tool_registry.rb
# frozen_string_literal: true

# require 'logger' # Not needed directly if only using ADK.logger

module ADK
  # Manages a collection of tool definitions for a specific agent instance.
  class ToolRegistry
    attr_reader :tools # Make tools readable

    # Initialize an empty tool registry.
    def initialize
      @tools = {} # Stores { name_symbol => tool_class } for this instance
    end

    # Register a tool class with this registry instance.
    # @param name [Symbol] The symbolic name of the tool.
    # @param klass [Class] The tool class (must inherit from ADK::Tool).
    def register(name, klass)
      logger = ADK.logger # Get the central logger instance

      unless klass < ADK::Tool
        logger.error("ToolRegistry: Attempted to register non-tool class: #{klass.inspect} for name '#{name}'.")
        return false
      end

      name_symbol = name.to_sym # Ensure it's a symbol

      if @tools.key?(name_symbol)
        # Use the local variable 'logger'
        logger.warn("ToolRegistry: Tool '#{name_symbol}' is already registered in this registry. Overwriting with class #{klass}.")
      else
        # Use the local variable 'logger'
        logger.info("ToolRegistry: Registering tool '#{name_symbol}' with class #{klass} in this registry.")
      end
      @tools[name_symbol] = klass
      true # Indicate success
    end

    # Find a tool class by its name symbol within this registry.
    # @param name_symbol [Symbol] The symbolic name of the tool.
    # @return [Class, nil] The tool class or nil if not found.
    def find_class(name_symbol)
      found_class = @tools[name_symbol.to_sym]
      ADK.logger.debug("[ToolRegistry #{@object_id}] find_class(#{name_symbol.inspect}): Found class in @tools: #{found_class.inspect}")
      found_class
    end

    # Create an instance of a tool by its name symbol using the class registered here.
    # @param name_symbol [Symbol] The symbolic name of the tool.
    # @return [ADK::Tool, nil] An instance of the tool or nil if instantiation fails or class not found.
    def create_instance(name_symbol)
      klass = find_class(name_symbol)
      ADK.logger.debug("[ToolRegistry #{@object_id}] create_instance(#{name_symbol.inspect}): Found class: #{klass.inspect}")
      klass&.new
    end

    # Get a list of available tools registered in this instance with basic info.
    # @return [Array<Hash>] An array of hashes, each with :name and :description.
    def list_tools
      @tools.values.map do |klass|
        metadata = klass.tool_metadata # Get the full { name:, description:, parameters: } hash
        metadata # Return the full hash
      end.sort_by { |t| t[:name].to_s }
    end
  end # End ToolRegistry class
end # End ADK module
