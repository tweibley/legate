# File: lib/adk/tool_registry.rb
# frozen_string_literal: true

# require 'logger' # Not needed directly if only using ADK.logger

module ADK
  module ToolRegistry
    @tools = {} # Stores { name_symbol => tool_class }

    class << self
      attr_reader :tools

      # Register a tool class
      def register(name, klass)
        logger = ADK.logger # Get the central logger instance

        if @tools.key?(name)
          # Use the local variable 'logger'
          logger.warn("ToolRegistry: Tool '#{name}' is already registered. Overwriting with class #{klass}.")
        else
          # Use the local variable 'logger'
          logger.info("ToolRegistry: Registering tool '#{name}' with class #{klass}")
        end
        @tools[name] = klass
      end

      # Find a tool class by its name symbol.
      def find_class(name_symbol)
        @tools[name_symbol]
      end

      # Create an instance of a tool by its name symbol.
      def create_instance(name_symbol)
        logger = ADK.logger # Get logger instance
        klass = find_class(name_symbol)

        if klass
          begin
            instance = klass.new
            logger.debug("ToolRegistry: Successfully instantiated tool '#{name_symbol}'")
            instance
          rescue StandardError => e
            logger.error("ToolRegistry: Failed to instantiate tool '#{name_symbol}' (Class: #{klass}): #{e.class} - #{e.message}")
            logger.error(e.backtrace.first(5).join("\n"))
            nil
          end
        else
          logger.warn("ToolRegistry: Attempted to create instance of unregistered tool '#{name_symbol}'")
          nil
        end
      end

      # Get a list of available tools with basic info using class metadata.
      def list_tools
        # No need to get logger instance if not logging within this method currently
        @tools.map do |name, klass|
          {
            name: klass.tool_name || name,
            description: klass.description || "[No description provided]"
          }
        end.sort_by { |t| t[:name].to_s }
      end
    end # End class << self
  end # End ToolRegistry module
end # End ADK module
