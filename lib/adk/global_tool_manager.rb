# lib/adk/global_tool_manager.rb
# frozen_string_literal: true

require 'logger'
require_relative 'tool' # Need Tool class for instance checks/metadata
require_relative 'tool/metadata_dsl'
require_relative 'tool_registry'

module ADK
  # Manages the central registration and discovery of all defined ADK::Tool subclasses.
  # This provides a way to list all available tools without needing a specific
  # ToolRegistry instance (which is tied to an Agent).
  module GlobalToolManager
    # Singleton registry instance stored as module instance variable
    @registry = ADK::ToolRegistry.new

    class << self
      # Helper to access the registry (useful for testing if needed, though mostly internal)
      attr_reader :registry
    end

    # Register a tool class globally. Called automatically via ADK::Tool.inherited
    # @param tool_class [Class] The tool class to register.
    def self.register_tool(tool_class)
      unless tool_class < ADK::Tool
        ADK.logger.warn("GlobalToolManager: Attempted to register non-tool class: #{tool_class.inspect}")
        return
      end

      tool_name = infer_tool_name(tool_class)
      return unless tool_name

      # Delegate to registry
      @registry.register(tool_name, tool_class)
    end

    # Helper method to infer tool name from class metadata or fallbacks
    # @param tool_class [Class]
    # @return [Symbol, nil] The inferred tool name or nil if failed
    def self.infer_tool_name(tool_class)
      metadata = tool_class.tool_metadata
      tool_name = metadata[:name]&.to_sym

      tool_name = attempt_name_inference_fallback(tool_class) if tool_name.nil? || tool_name == :''

      tool_name = tool_name&.to_sym
      if tool_name.nil? || tool_name == :''
        # Only log if we haven't already logged a warning in attempt_name_inference_fallback
        # (Though attempt_name_inference_fallback returns nil on failure, so we might duplicate logs slightly
        # if we aren't careful, but here we just check final result)
        ADK.logger.error("GlobalToolManager: Could not determine a valid tool name for #{tool_class}. Skipping registration.") unless tool_class.respond_to?(:inferred_name) && tool_class.inferred_name.nil?
        return nil
      end

      tool_name
    end

    # Separate fallback logic for complexity reduction
    def self.attempt_name_inference_fallback(tool_class)
      # First, check for the instance variable set by the DEPRECATED define_metadata
      if tool_class.instance_variable_defined?(:@tool_name)
        name = tool_class.instance_variable_get(:@tool_name)
        ADK.logger.debug("GlobalToolManager: Tool class #{tool_class} using name from deprecated @tool_name: #{name.inspect}")
        return name
      end

      # If not found via deprecated method, try inference via DSL
      begin
        # Check if the class responds to inferred_name (from MetadataDsl)
        if tool_class.respond_to?(:inferred_name)
          inferred = tool_class.inferred_name
          if inferred
            ADK.logger.debug("GlobalToolManager: Tool class #{tool_class} had no explicit name, using inferred name: #{inferred.inspect}")
            inferred
          else
            ADK.logger.warn("GlobalToolManager: Tool class #{tool_class} has no explicit name and inference failed (maybe anonymous?). Skipping registration.")
            nil
          end
        else
          # Fallback if MetadataDsl isn't included or something is wrong
          ADK.logger.warn("GlobalToolManager: Tool class #{tool_class} has no name defined via tool_metadata or @tool_name, and does not support inferred_name. Skipping registration.")
          nil
        end
      rescue StandardError => e
        ADK.logger.error("GlobalToolManager: Error during name inference for #{tool_class}: #{e.message}")
        nil
      end
    end

    # Get a list of all globally registered tools with basic info.
    # @return [Array<Hash>] An array of hashes, each with :name and :description.
    def self.list_all_tools
      tools_list = @registry.tools.map do |name_sym, klass|
        metadata = klass.tool_metadata
        {
          name: metadata[:name] || name_sym, # Fallback
          description: metadata[:description] || '[No description provided]',
          parameters: metadata[:parameters] || []
        }
      end
      tools_list.sort_by { |t| t[:name].to_s }
    end

    # Find a registered tool class by its name symbol.
    # @param name_symbol [Symbol] The symbolic name of the tool.
    # @return [Class, nil] The tool class or nil if not found.
    def self.find_class(name_symbol)
      @registry.find_class(name_symbol)
    end

    # Get the names (symbols) of all registered tools.
    # @return [Array<Symbol>] An array of tool name symbols.
    def self.registered_tool_names
      @registry.tools.keys
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
      @registry = ADK::ToolRegistry.new
    end
  end
  # End GlobalToolManager module
end
# End ADK module
