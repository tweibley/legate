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
    # Store tool classes keyed by their symbolic name
    @defined_tools = {} # { :tool_symbol => ToolClass }

    # Register a tool class globally. Called automatically via ADK::Tool.inherited
    # @param tool_class [Class] The tool class to register.
    def self.register_tool(tool_class)
      unless tool_class < ADK::Tool
        ADK.logger.warn("GlobalToolManager: Attempted to register non-tool class: #{tool_class.inspect}")
        return
      end

      metadata = tool_class.tool_metadata
      tool_name = metadata[:name]&.to_sym

      # --- Attempt name inference if not found in metadata ---
      # This handles cases where the new DSL isn't used (e.g., old define_metadata)
      # or if the DSL itself couldn't determine a name (e.g., anonymous class)
      if tool_name.nil? || tool_name == :''
        # First, check for the instance variable set by the DEPRECATED define_metadata
        if tool_class.instance_variable_defined?(:@tool_name)
          tool_name = tool_class.instance_variable_get(:@tool_name)
          ADK.logger.debug("GlobalToolManager: Tool class #{tool_class} using name from deprecated @tool_name: #{tool_name.inspect}")
        else
          # If not found via deprecated method, try inference via DSL
          begin
            # Check if the class responds to inferred_name (from MetadataDsl)
            if tool_class.respond_to?(:inferred_name)
              inferred = tool_class.inferred_name
              if inferred
                ADK.logger.debug("GlobalToolManager: Tool class #{tool_class} had no explicit name, using inferred name: #{inferred.inspect}")
                tool_name = inferred
              else
                ADK.logger.warn("GlobalToolManager: Tool class #{tool_class} has no explicit name and inference failed (maybe anonymous?). Skipping registration.")
                return
              end
            else
              # Fallback if MetadataDsl isn't included or something is wrong
              ADK.logger.warn("GlobalToolManager: Tool class #{tool_class} has no name defined via tool_metadata or @tool_name, and does not support inferred_name. Skipping registration.")
              return
            end
          rescue StandardError => e
            ADK.logger.error("GlobalToolManager: Error during name inference for #{tool_class}: #{e.message}")
            return # Don't register if inference itself fails
          end
        end
      end
      # --- End Name Inference Attempt ---

      # Ensure tool_name is a symbol before proceeding
      tool_name = tool_name&.to_sym
      if tool_name.nil? || tool_name == :''
        ADK.logger.error("GlobalToolManager: Could not determine a valid tool name for #{tool_class}. Skipping registration.")
        return
      end

      if @defined_tools.key?(tool_name) && @defined_tools[tool_name] != tool_class
        ADK.logger.warn("GlobalToolManager: Tool name '#{tool_name}' is already registered with class #{@defined_tools[tool_name]}. Overwriting with #{tool_class}.")
      elsif !@defined_tools.key?(tool_name)
        # Only log debug if it wasn't an overwrite or already logged during inference
        ADK.logger.debug("GlobalToolManager: Registered tool '#{tool_name}' with class #{tool_class}.") unless @defined_tools.key?(tool_name)
      end
      @defined_tools[tool_name] = tool_class
    end

    # Get a list of all globally registered tools with basic info.
    # @return [Array<Hash>] An array of hashes, each with :name and :description.
    def self.list_all_tools
      @defined_tools.map do |name_sym, klass|
        metadata = klass.tool_metadata
        {
          name: metadata[:name] || name_sym, # Fallback, though name should always be present if registered
          description: metadata[:description] || '[No description provided]',
          parameters: metadata[:parameters] || []
        }
      end.sort_by { |t| t[:name].to_s }
    end

    # Find a registered tool class by its name symbol.
    # @param name_symbol [Symbol] The symbolic name of the tool.
    # @return [Class, nil] The tool class or nil if not found.
    def self.find_class(name_symbol)
      @defined_tools[name_symbol.to_sym]
    end

    # Get the names (symbols) of all registered tools.
    # @return [Array<Symbol>] An array of tool name symbols.
    def self.registered_tool_names
      @defined_tools.keys
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
      @defined_tools = {}
    end
  end # End GlobalToolManager module
end # End ADK module
