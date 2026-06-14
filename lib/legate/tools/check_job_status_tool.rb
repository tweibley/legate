# File: lib/legate/tools/check_job_status_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative '../errors'
require 'json'

module Legate
  module Tools
    # A built-in tool to check the status and retrieve results for a background job
    # initiated by a Legate async tool.
    class CheckJobStatusTool < Legate::Tool
      # --- New DSL Metadata ---
      # Name :check_job_status_tool will be inferred
      self.explicit_tool_name = :check_job_status # Keep original name

      tool_description 'Checks the status and retrieves the result of a previously started background job using its ID.'

      parameter :job_id,
                type: :string,
                description: 'The ID of the job to check status for',
                required: true
      # --- End New DSL Metadata ---

      private

      # @param params [Hash] Must contain :job_id.
      # @param _context [Legate::ToolContext, nil] The execution context (unused here).
      # @return [Hash] { status: :success/:error, ... }
      def perform_execution(params, _context)
        job_id = params[:job_id]
        return { status: :error, error_message: 'Missing job_id parameter.' } unless job_id && !job_id.strip.empty?

        result = Legate::Tools::BaseAsyncJobTool.job_results[job_id]

        if result.nil?
          { status: :success, job_id: job_id, job_status: 'unknown', message: 'Job ID not found.' }
        else
          job_status = result['status']
          response = { status: :success, job_id: job_id, job_status: job_status }
          response[:result] = result['result'] if result['result']
          response[:error_message] = result['error_message'] if result['error_message']
          response
        end
      end
    end
  end
end
