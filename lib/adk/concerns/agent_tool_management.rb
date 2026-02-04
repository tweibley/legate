# frozen_string_literal: true

module ADK
  module Concerns
    # Encapsulates tool management logic for ADK::Agent.
    # Handles registration, retrieval, and metadata extraction for tools.
    module AgentToolManagement
      # Adds a tool instance OR class to the agent's registry
      # @param tool [ADK::Tool, Class<ADK::Tool>] The tool instance or class to add
      # @return [Boolean] True if the tool was added, false otherwise
      def add_tool(tool)
        # Check if it's a valid tool instance or class
        is_tool_instance = tool.is_a?(ADK::Tool)
        is_tool_class = tool.is_a?(Class) && tool < ADK::Tool

        unless is_tool_instance || is_tool_class
          ADK.logger.error("Agent '#{name}' add_tool: Attempted to add invalid tool: #{tool.inspect}")
          return false
        end

        # Determine the actual tool class
        tool_class = is_tool_class ? tool : tool.class

        # --- Determine Tool Name with Fallbacks --- #
        tool_name = get_tool_name_from_class(tool_class) # Use the new helper
        # --- End Determine Tool Name --- #

        # Validate name was found
        unless tool_name # The helper returns nil if no valid name is found
          ADK.logger.error("Agent '#{name}' add_tool: Could not determine tool name for class #{tool_class}. Cannot add tool.")
          return false # Explicitly return false
        end

        # Check for overwrite
        ADK.logger.warn("Agent '#{name}': Tool '#{tool_name}' already added. Overwriting with class #{tool_class}.") if @tool_registry.find_class(tool_name)

        # Register the class using the determined name
        ADK.logger.debug("Agent '#{name}' add_tool: Registering tool_name=#{tool_name.inspect} with class=#{tool_class.inspect} in registry=#{@tool_registry.object_id}")
        registration_result = @tool_registry.register(tool_name, tool_class)
        ADK.logger.debug("Agent '#{name}' add_tool: Registry after registration for #{tool_name.inspect}: #{@tool_registry.tools.keys.inspect}")

        # Explicitly return the boolean result from the registry
        registration_result
      end

      # Returns the list of tools registered with this agent
      # @return [Array<ADK::Tool>] Array of tool instances
      def tools
        @tool_registry.tools.values.map do |tool_class|
          # Get name reliably using the new helper method
          tool_name = get_tool_name_from_class(tool_class)
          if tool_name
            @tool_registry.create_instance(tool_name)
          else
            # This branch should ideally not be hit frequently if registration robustly requires a name.
            ADK.logger.warn("Agent '#{name}': Skipping tool instance creation for class #{tool_class} as its name could not be determined post-registration.")
            nil
          end
        end.compact
      end

      # Finds a tool instance by name
      # @param tool_name [Symbol] The name of the tool to find
      # @return [ADK::Tool, nil] The tool instance if found, nil otherwise
      def find_tool(tool_name)
        @tool_registry.create_instance(tool_name.to_sym)
      end

      # Registers a tool class with the agent's specific registry.
      # @param tool_class [Class] The tool class to register (must inherit from ADK::Tool).
      # @return [Boolean] True if registration was successful, false otherwise.
      def register_tool_class(tool_class)
        ADK.logger.debug("[register_tool_class] Registering class: #{tool_class.inspect} (Object ID: #{tool_class.object_id})")
        # Basic validation
        unless tool_class < ADK::Tool
          ADK.logger.error("Agent '#{name}': Attempted to register invalid object (must inherit from ADK::Tool): #{tool_class.inspect}")
          return false
        end

        # Get name via metadata method
        tool_name = get_tool_name_from_class(tool_class) # Use the new helper
        ADK.logger.debug("[register_tool_class] Determined tool name: #{tool_name.inspect} for class #{tool_class.inspect}")

        unless tool_name # Helper returns nil if no valid name
          # Use logger method, not direct access
          ADK.logger.error("Agent '#{name}': Could not determine tool name for class #{tool_class}. Cannot register.") # Consistent error message
          return false
        end

        ADK.logger.warn("Agent '#{name}': Tool '#{tool_name}' already registered. Overwriting.") if @tool_registry.find_class(tool_name)

        # Register with the instance registry
        @tool_registry.register(tool_name, tool_class)
        true # Return true on success
      end

      # Returns the list of available tool metadata (names, descriptions, parameters)
      # from the agent's specific tool registry.
      def available_tools_metadata
        @tool_registry.list_tools
      end

      # Finds a tool class by name from the agent's specific tool registry.
      # @param tool_name [Symbol]
      # @return [Class<ADK::Tool>, nil]
      def find_tool_class(tool_name)
        @tool_registry.find_class(tool_name.to_sym)
      end

      private

      # Helper method to consistently determine the tool name from a tool class.
      # Uses metadata, then deprecated @tool_name, then inferred_name.
      def get_tool_name_from_class(tool_class)
        return nil unless tool_class.is_a?(Class) && tool_class < ADK::Tool

        begin
          metadata = tool_class.tool_metadata
        rescue StandardError => e
          ADK.logger.error("Error calling tool_metadata on #{tool_class}: #{e.class} - #{e.message} - Backtrace: #{e.backtrace.first(3).join(' | ')}")
          metadata = {} # Default to empty hash if metadata call fails, for diagnosis
        end
        name = metadata[:name]&.to_sym

        if name.nil? || name == :''
          # Check deprecated @tool_name (instance variable on the class itself)
          if tool_class.instance_variable_defined?(:@tool_name)
            name = tool_class.instance_variable_get(:@tool_name)&.to_sym
            # ADK.logger.debug { "get_tool_name_from_class: Using name from deprecated @tool_name for #{tool_class}: #{name.inspect}" } if name
          end

          # If still no name, try inferred_name as a primary fallback if metadata[:name] is missing
          if (name.nil? || name == '') && tool_class.respond_to?(:inferred_name)
            name = tool_class.inferred_name
            # ADK.logger.debug { "get_tool_name_from_class: Using inferred_name for #{tool_class}: #{name.inspect}" } if name
          end
        end

        name && name != :'' ? name : nil
      end
    end
  end
end
