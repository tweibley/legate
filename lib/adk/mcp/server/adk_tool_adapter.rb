# File: lib/adk/mcp/server/adk_tool_adapter.rb
# frozen_string_literal: true

require 'fast_mcp'
require_relative '../../tool'
require_relative '../../tool_context'
require_relative '../util/schema_converter'
require_relative '../error'

module ADK
  module Mcp
    module Server
      # Base adapter class to expose an ADK::Tool as an MCP tool via fast-mcp.
      # Use the `wrap` class method to dynamically create subclasses for specific ADK tools.
      class AdkToolAdapter < FastMcp::Tool
        # Use standard class instance variables for inheritable attributes
        class << self
          attr_reader :adk_tool_class # Provide a reader
        end

        # Dynamically creates a new FastMcp::Tool subclass that wraps the given ADK::Tool class.
        #
        # @param adk_tool_class [Class<ADK::Tool>] The ADK::Tool class to wrap.
        # @return [Class<AdkToolAdapter>] A new anonymous class inheriting from AdkToolAdapter.
        # @raise [ArgumentError] if the provided class is not an ADK::Tool.
        def self.wrap(adk_tool_class)
          unless adk_tool_class.is_a?(Class) && adk_tool_class < ADK::Tool
            raise ArgumentError, "Provided class #{adk_tool_class} is not a valid ADK::Tool class."
          end

          metadata = adk_tool_class.tool_metadata
          # Check metadata hash and required keys
          unless metadata.is_a?(Hash) && metadata[:name] && metadata[:description]
            raise ArgumentError, "ADK::Tool #{adk_tool_class} has incomplete metadata (missing name or description)."
          end

          mcp_tool_name = metadata[:name].to_s
          mcp_description = metadata[:description]
          adk_params = metadata[:parameters] || {}

          # Convert ADK params to a Dry::Schema proc
          schema_proc = ADK::Mcp::Util::SchemaConverter.adk_to_dry_schema(adk_params)

          # Create the anonymous adapter class
          adapter_class = Class.new(AdkToolAdapter) do
            @adk_tool_class = adk_tool_class

            # Use fast-mcp DSL methods inside the class definition block
            tool_name mcp_tool_name # Use DSL method
            description mcp_description
            arguments(&schema_proc) if schema_proc

            Mcp.logger.info("Created fast-mcp adapter for ADK tool: #{adk_tool_class} as '#{mcp_tool_name}'")
          end

          adapter_class
        end

        # The `call` method executed by fast-mcp when the tool is invoked.
        # Instantiates the wrapped ADK tool, executes it with a dummy context,
        # and translates the result/error.
        #
        # @param args [Hash] Keyword arguments matching the defined schema.
        # @return [Any] The successful result payload for the MCP response.
        # @raise [StandardError] If the ADK tool returns an error status.
        # @raise [NotImplementedError] If the ADK tool returns a pending status (needs CheckJobStatusTool).
        def call(**args)
          # Access the class instance variable via the reader
          tool_class = self.class.adk_tool_class
          raise NotImplementedError, "AdkToolAdapter cannot be used directly, use .wrap first." unless tool_class

          adk_instance = tool_class.new

          # Convert string keys from MCP/fast-mcp back to symbols for ADK tool
          adk_params = args.transform_keys(&:to_sym)

          # Create a dummy/minimal context for the ADK tool execution
          # TODO: Can we provide more meaningful context if running within a larger MCP session?
          dummy_context = ADK::ToolContext.new(
            session_id: SecureRandom.uuid, # Generic ID
            user_id: 'mcp_user',
            app_name: 'mcp_server',
            tool_registry: ADK::ToolRegistry.new # Create a new, empty registry for this dummy context
            # No session_service available here easily
          )

          Mcp.logger.info("Executing ADK tool '#{self.class.tool_name}' via MCP adapter with params: #{adk_params.inspect}")

          begin
            result_hash = adk_instance.execute(adk_params, dummy_context)
          rescue StandardError => e
            # Catch errors during the tool's execute method itself
            Mcp.logger.error("Error during underlying ADK tool execution for '#{self.class.tool_name}': #{e.class} - #{e.message}")
            # Let fast-mcp handle this standard error, it should map to an MCP error response
            raise StandardError, "Execution Error in ADK tool '#{self.class.tool_name}': #{e.message}"
          end

          Mcp.logger.debug("ADK tool '#{self.class.tool_name}' returned hash: #{result_hash.inspect}")

          # Translate ADK result hash to MCP return/error
          case result_hash[:status]
          when :success
            return result_hash[:result] # Return the raw result for MCP
          when :error
            error_message = result_hash[:error_message] || "Unknown error from ADK tool '#{self.class.tool_name}'"
            Mcp.logger.error("ADK tool '#{self.class.tool_name}' reported error: #{error_message}")
            # Raise a standard error, fast-mcp should convert this to an MCP error response
            raise StandardError, error_message
          when :pending
            job_id = result_hash[:job_id] # Assuming the key is :job_id now
            message = result_hash[:message] || "ADK tool '#{self.class.tool_name}' started an async job."
            Mcp.logger.info("ADK tool '#{self.class.tool_name}' returned pending status (Job ID: #{job_id})")
            # Return a structured hash indicating pending status (as per FR2.2 recommendation)
            # Requires CheckJobStatusTool to be exposed separately via MCP.
            return { status: 'pending', job_id: job_id, message: message }
          else
            unknown_status_msg = "ADK tool '#{self.class.tool_name}' returned unknown status: #{result_hash[:status]}"
            Mcp.logger.error(unknown_status_msg)
            raise StandardError, unknown_status_msg
          end
        end
      end
    end
  end
end
