# lib/adk/global_tool_manager.rb
# frozen_string_literal: true

require 'logger'
require_relative 'tool' # Need Tool class for instance checks/metadata

module ADK
  # Manages the central registration and discovery of all defined ADK::Tool subclasses.
  # This provides a way to list all available tools without needing a specific
  # ToolRegistry instance (which is tied to an Agent).
  module GlobalToolManager
    # Store tool classes keyed by their symbolic name
    @@defined_tools = {} # { :tool_symbol => ToolClass }

    # Register a tool class globally. Called automatically.
    # @param tool_class [Class] The tool class to register.
    def self.register_tool(tool_class)
      unless tool_class < ADK::Tool
        ADK.logger.warn("GlobalToolManager: Attempted to register non-tool class: #{tool_class.inspect}")
        return
      end

      metadata = tool_class.tool_metadata
      tool_name = metadata[:name]&.to_sym

      unless tool_name
        ADK.logger.warn("GlobalToolManager: Tool class #{tool_class} has no name defined via define_metadata. Skipping registration.")
        return
      end

      if @@defined_tools.key?(tool_name) && @@defined_tools[tool_name] != tool_class
        ADK.logger.warn("GlobalToolManager: Tool name '#{tool_name}' is already registered with class #{@@defined_tools[tool_name]}. Overwriting with #{tool_class}.")
      elsif !@@defined_tools.key?(tool_name)
        ADK.logger.debug("GlobalToolManager: Registered tool '#{tool_name}' with class #{tool_class}.")
      end
      @@defined_tools[tool_name] = tool_class
    end

    # Get a list of all globally registered tools with basic info.
    # @return [Array<Hash>] An array of hashes, each with :name and :description.
    def self.list_all_tools
      @@defined_tools.map do |name_sym, klass|
        metadata = klass.tool_metadata
        {
          name: metadata[:name] || name_sym, # Fallback, though name should always be present if registered
          description: metadata[:description] || "[No description provided]",
          parameters: metadata[:parameters] || []
        }
      end.sort_by { |t| t[:name].to_s }
    end

    # Find a registered tool class by its name symbol.
    # @param name_symbol [Symbol] The symbolic name of the tool.
    # @return [Class, nil] The tool class or nil if not found.
    def self.find_class(name_symbol)
      @@defined_tools[name_symbol.to_sym]
    end

    # Get the names (symbols) of all registered tools.
    # @return [Array<Symbol>] An array of tool name symbols.
    def self.registered_tool_names
      @@defined_tools.keys
    end

    # Create an instance of a tool by its name symbol using the globally registered class.
    # @param name_symbol [Symbol] The symbolic name of the tool.
    # @return [ADK::Tool, nil] An instance of the tool or nil if instantiation fails or class not found.
    def self.create_instance(name_symbol)
      klass = find_class(name_symbol.to_sym)

      if klass
        begin
          instance = klass.new
          ADK.logger.debug("GlobalToolManager: Successfully instantiated tool '#{name_symbol}'.")
          instance
        rescue StandardError => e
          ADK.logger.error("GlobalToolManager: Failed to instantiate tool '#{name_symbol}' (Class: #{klass}): #{e.class} - #{e.message}")
          ADK.logger.error(e.backtrace.first(5).join("\n"))
          nil
        end
      else
        ADK.logger.warn("GlobalToolManager: Attempted to create instance of tool '#{name_symbol}' which is not globally registered.")
        nil
      end
    end

    # Clears all registered tools. Primarily for testing.
    def self.reset!
      @@defined_tools = {}
    end
  end # End GlobalToolManager module
end # End ADK module
