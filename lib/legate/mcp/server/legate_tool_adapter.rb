# File: lib/legate/mcp/server/legate_tool_adapter.rb
# frozen_string_literal: true

require 'fast_mcp'
require_relative '../../tool'
require_relative '../../tool_context'
require_relative '../util/schema_converter'
require_relative '../../errors'

module Legate
  module Mcp
    module Server
      # Base adapter class to expose an Legate::Tool as an MCP tool via fast-mcp.
      # Use the `wrap` class method to dynamically create subclasses for specific Legate tools.
      class LegateToolAdapter < FastMcp::Tool
        # Use standard class instance variables for inheritable attributes
        class << self
          attr_reader :legate_tool_class # Provide a reader
        end

        # Dynamically creates a new FastMcp::Tool subclass that wraps the given Legate::Tool class.
        #
        # @param legate_tool_class [Class<Legate::Tool>] The Legate::Tool class to wrap.
        # @return [Class<LegateToolAdapter>] A new anonymous class inheriting from LegateToolAdapter.
        # @raise [ArgumentError] if the provided class is not an Legate::Tool.
        def self.wrap(legate_tool_class)
          raise ArgumentError, "Provided class #{legate_tool_class} is not a valid Legate::Tool class." unless legate_tool_class.is_a?(Class) && legate_tool_class < Legate::Tool

          metadata = legate_tool_class.tool_metadata
          # Check metadata hash and required keys
          raise ArgumentError, "Legate::Tool #{legate_tool_class} has incomplete metadata (missing name or description)." unless metadata.is_a?(Hash) && metadata[:name] && metadata[:description]

          mcp_tool_name = metadata[:name].to_s
          mcp_description = metadata[:description]
          legate_params = metadata[:parameters] || {}

          # Convert Legate params to a Dry::Schema proc
          schema_proc = Legate::Mcp::Util::SchemaConverter.legate_to_dry_schema(legate_params)

          # Create the anonymous adapter class
          Class.new(LegateToolAdapter) do
            @legate_tool_class = legate_tool_class

            # Use fast-mcp DSL methods inside the class definition block
            tool_name mcp_tool_name # Use DSL method
            description mcp_description
            arguments(&schema_proc) if schema_proc

            Legate.logger.info("Created fast-mcp adapter for Legate tool: #{legate_tool_class} as '#{mcp_tool_name}'")
          end
        end

        # The `call` method executed by fast-mcp when the tool is invoked.
        # Instantiates the wrapped Legate tool, executes it with a dummy context,
        # and translates the result/error.
        #
        # @param args [Hash] Keyword arguments matching the defined schema.
        # @return [Any] The successful result payload for the MCP response.
        # @raise [StandardError] If the Legate tool returns an error status.
        # @raise [NotImplementedError] If the Legate tool returns a pending status (needs CheckJobStatusTool).
        def call(**args)
          # Access the class instance variable via the reader
          tool_class = self.class.legate_tool_class
          raise NotImplementedError, 'LegateToolAdapter cannot be used directly, use .wrap first.' unless tool_class

          legate_instance = tool_class.new

          # Convert string keys from MCP/fast-mcp back to symbols for Legate tool
          legate_params = args.transform_keys(&:to_sym)

          # Create a dummy/minimal context for the Legate tool execution
          # TODO: Can we provide more meaningful context if running within a larger MCP session?
          dummy_context = Legate::ToolContext.new(
            session_id: SecureRandom.uuid, # Generic ID
            user_id: 'mcp_user',
            app_name: 'mcp_server',
            tool_registry: Legate::ToolRegistry.new # Create a new, empty registry for this dummy context
            # No session_service available here easily
          )

          Legate.logger.info("Executing Legate tool '#{self.class.tool_name}' via MCP adapter with params: #{legate_params.inspect}")

          begin
            result_hash = legate_instance.execute(legate_params, dummy_context)
          rescue StandardError => e
            # Catch errors during the tool's execute method itself
            Mcp.logger.error("Error during underlying Legate tool execution for '#{self.class.tool_name}': #{e.class} - #{e.message}")
            # Let fast-mcp handle this standard error, it should map to an MCP error response
            raise StandardError, "Execution Error in Legate tool '#{self.class.tool_name}': #{e.message}"
          end

          Legate.logger.debug("Legate tool '#{self.class.tool_name}' returned hash: #{result_hash.inspect}")

          # Translate Legate result hash to MCP return/error
          case result_hash[:status]
          when :success
            result_hash[:result] # Return the raw result for MCP
          when :error
            error_message = result_hash[:error_message] || "Unknown error from Legate tool '#{self.class.tool_name}'"
            Legate.logger.error("Legate tool '#{self.class.tool_name}' reported error: #{error_message}")
            # Raise a standard error, fast-mcp should convert this to an MCP error response
            raise StandardError, error_message
          when :pending
            job_id = result_hash[:job_id] # Assuming the key is :job_id now
            message = result_hash[:message] || "Legate tool '#{self.class.tool_name}' started an async job."
            Legate.logger.info("Legate tool '#{self.class.tool_name}' returned pending status (Job ID: #{job_id})")
            # Return a structured hash indicating pending status (as per FR2.2 recommendation)
            # Requires CheckJobStatusTool to be exposed separately via MCP.
            { status: 'pending', job_id: job_id, message: message }
          else
            unknown_status_msg = "Legate tool '#{self.class.tool_name}' returned unknown status: #{result_hash[:status]}"
            Mcp.logger.error(unknown_status_msg)
            raise StandardError, unknown_status_msg
          end
        end
      end
    end
  end
end
