# File: lib/legate/tools/base_async_job_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative '../errors'
require 'concurrent'
require 'securerandom'
require 'json'

module Legate
  module Tools
    # Abstract base class for tools that initiate asynchronous background tasks via threads.
    class BaseAsyncJobTool < Legate::Tool
      tool_description "Base class for tools that initiate long-running tasks via background threads. Subclasses must implement `worker_class` and `prepare_job_arguments`. Use 'check_job_status' tool to retrieve results."

      # --- In-Memory Job Results Storage ---
      class << self
        def job_results
          @job_results ||= Concurrent::Map.new
        end
      end

      # Subclasses MUST override this method to return the worker class
      # that should be executed.
      # @return [Class] The worker class (must respond to #perform).
      def worker_class
        raise NotImplementedError, "#{self.class.name} must implement #worker_class"
      end

      # Subclasses MUST override this method to prepare the arguments
      # for the worker's perform method based on the Legate tool's parameters and context.
      # Note: Arguments must be simple types serializable to JSON (strings, numbers, bools, arrays, hashes).
      # @param params [Hash] The validated parameters passed to the Legate tool.
      # @param context [Legate::ToolContext] Contextual information (session_id, etc.).
      # @return [Array] An array of arguments to be passed to the worker's perform method.
      def prepare_job_arguments(params, context)
        raise NotImplementedError, "#{self.class.name} must implement #prepare_job_arguments(params, context)"
      end

      # Overrides Legate::Tool#perform_execution to spawn a background thread.
      # @param params [Hash] The validated parameters.
      # @param context [Legate::ToolContext] The execution context.
      # @return [Hash] { status: :pending, job_id: ... } or { status: :error, ... }
      private def perform_execution(params, context)
        jid = SecureRandom.uuid
        worker = worker_class.new
        args = prepare_job_arguments(params, context)

        BaseAsyncJobTool.job_results[jid] = { 'status' => 'pending' }

        Legate.logger.info("Spawning background task for worker '#{worker_class.name}' for tool '#{name}'. Job ID: #{jid}")
        Legate.logger.debug("Job Args: #{args.inspect}")

        Concurrent::Promises.future do
          worker.perform(jid, *args)
        rescue StandardError => e
          BaseAsyncJobTool.job_results[jid] = { 'status' => 'error', 'error_message' => "#{e.class}: #{e.message}" }
        end

        { status: :pending, job_id: jid, message: "Job #{jid} has been submitted." }
      end

      # --- Static Helpers for Workers to Store Status/Results --- #

      # Helper method for workers to call at the beginning of their perform method
      # to indicate the job has started processing.
      # @param jid [String] The Job ID.
      def self.store_job_pending(jid)
        job_results[jid] = { 'status' => 'pending' }
        Legate.logger.debug("Stored pending status for job #{jid}")
      end

      # Helper method for workers to call upon completion to store their results.
      # @param jid [String] The Job ID.
      # @param result [Object] The result data.
      def self.store_job_result(jid, result)
        job_results[jid] = { 'status' => 'completed', 'result' => result.is_a?(String) ? result : result.to_json }
        Legate.logger.debug("Stored successful result for job #{jid}")
      end

      # Helper method for workers to call upon failure to store error information.
      # @param jid [String] The Job ID.
      # @param error_message [String] The error message.
      # @param _error_class [String] The class name of the error (kept for API compatibility).
      def self.store_job_error(jid, error_message, _error_class = 'StandardError')
        job_results[jid] = { 'status' => 'error', 'error_message' => error_message }
        Legate.logger.debug("Stored error result for job #{jid}")
      end
    end
  end
end
