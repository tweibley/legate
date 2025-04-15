# File: lib/adk/tool_registry.rb
# frozen_string_literal: true

require 'logger'

module ADK
  module ToolRegistry
    @tools = {}
    @logger = Logger.new($stdout)

    class << self
      attr_reader :tools

      # Register a tool class
      def register(name, klass)
        # ... (registration logic remains the same) ...
         if @tools.key?(name)
           @logger.warn("ToolRegistry: Tool '#{name}' is already registered. Overwriting with class #{klass}.")
         else
           @logger.info("ToolRegistry: Registering tool '#{name}' with class #{klass}")
         end
         @tools[name] = klass
      end

      # Find class (remains the same)
      def find_class(name_symbol)
        @tools[name_symbol]
      end

      # Create instance (remains the same)
      def create_instance(name_symbol)
        # ... (existing instantiation logic) ...
         klass = find_class(name_symbol)
         if klass
           begin
             klass.new
           rescue StandardError => e
             @logger.error("ToolRegistry: Failed to instantiate tool '#{name_symbol}' (Class: #{klass}): #{e.message}")
             nil
           end
         else
           @logger.warn("ToolRegistry: Attempted to create instance of unregistered tool '#{name_symbol}'")
           nil
         end
      end

      # Get list - NOW USES CLASS METADATA
      # @return [Array<Hash>] Like [{ name: :echo, description: "..." }, ...]
      def list_tools
        @tools.map do |name, klass|
          # Access metadata directly from the class
          {
            name: klass.tool_name || name, # Use registered name as fallback
            description: klass.description || "[No description provided]"
          }
          # Ensure the class has the methods before calling:
          # if klass.respond_to?(:tool_name) && klass.respond_to?(:description)
          #   { name: klass.tool_name, description: klass.description }
          # else
          #   @logger.warn("ToolRegistry: Tool class #{klass} for name '#{name}' doesn't define metadata methods.")
          #   { name: name, description: "[Metadata unavailable]" }
          # end
        end.sort_by { |t| t[:name].to_s } # Sort alphabetically by name
      end
    end
  end
end