# lib/adk/global_tool_manager.rb
# frozen_string_literal: true

require 'logger'
require_relative 'tool' # Need Tool class for instance checks/metadata
require_relative 'tool/metadata_dsl'

module ADK
  # Manages the central registration and discovery of all defined ADK::Tool subclasses.
  # This provides a way to list all available tools without needing a specific
  # ToolRegistry instance (which is tied to an Agent).
  module GlobalToolManager
    # Store tool classes using a global ToolRegistry instance
    @@registry = ADK::ToolRegistry.new

    # Register a tool class globally. Called automatically via ADK::Tool.inherited
    # @param tool_class [Class] The tool class to register.
    def self.register_tool(tool_class)
      # Maintain original logging behavior for consistency if needed, but delegation is cleaner.
      # ToolRegistry handles validation and logging.
      success = @@registry.register_class(tool_class)
      if success
        metadata = tool_class.tool_metadata
        tool_name = metadata[:name]&.to_sym
        ADK.logger.debug("GlobalToolManager: Registered tool '#{tool_name}' with class #{tool_class}.")
      else
        # If registry failed (and logged its own error), we might want to log from GlobalToolManager perspective too
        # but let's trust ToolRegistry's logging.
      end
    end

    # Get a list of all globally registered tools with basic info.
    # @return [Array<Hash>] An array of hashes, each with :name and :description.
    def self.list_all_tools
      @@registry.list_tools
    end

    # Find a registered tool class by its name symbol.
    # @param name_symbol [Symbol] The symbolic name of the tool.
    # @return [Class, nil] The tool class or nil if not found.
    def self.find_class(name_symbol)
      @@registry.find_class(name_symbol)
    end

    # Get the names (symbols) of all registered tools.
    # @return [Array<Symbol>] An array of tool name symbols.
    def self.registered_tool_names
      @@registry.tools.keys
    end

    # Create an instance of a tool by its name symbol using the globally registered class.
    # @param name_symbol [Symbol] The symbolic name of the tool.
    # @return [ADK::Tool, nil] An instance of the tool or nil if instantiation fails or class not found.
    def self.create_instance(name_symbol)
      # We cannot blindly delegate because GlobalToolManager historically catches instantiation errors
      klass = find_class(name_symbol)

      unless klass
        ADK.logger.warn("GlobalToolManager: Attempted to create instance of tool '#{name_symbol}' which is not globally registered.")
        return nil
      end

      begin
        instance = klass.new
        ADK.logger.debug("GlobalToolManager: Successfully instantiated tool '#{name_symbol}'.")
        instance
      rescue StandardError => e
        ADK.logger.error("GlobalToolManager: Failed to instantiate tool '#{name_symbol}' (Class: #{klass}): #{e.class} - #{e.message}")
        ADK.logger.error(e.backtrace.first(5).join("\n"))
        nil
      end
    end

    # Clears all registered tools. Primarily for testing.
    def self.reset!
      @@registry.reset!
    end
  end # End GlobalToolManager module
end # End ADK module
