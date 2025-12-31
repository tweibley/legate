# frozen_string_literal: true

require 'logger'

module ADK
  # Handles the injection of data from previous steps into the current step's parameters.
  class ParameterInjector
    def initialize(logger: ADK.logger)
      @logger = logger
    end

    # Injects values from the previous step result into the current parameters.
    # @param params [Hash] The original parameters for the current step.
    # @param previous_result [Hash, nil] The result hash from the previous step.
    # @return [Hash] The parameters with injected values.
    def inject(params, previous_result)
      return params if params.nil?

      current_params = params.dup
      current_params.transform_values! do |value|
        process_value(value, previous_result)
      end
      current_params
    end

    private

    def process_value(value, previous_result)
      return value unless value.is_a?(String) && placeholder?(value)

      if valid_previous_result?(previous_result)
        extract_injection_value(previous_result) || value
      else
        @logger.warn("Cannot inject: Previous step failed or absent. Prev Hash: #{previous_result.inspect}")
        value
      end
    end

    def placeholder?(value)
      value.match?(/\[Result from step \d+\]|\[Result from previous step\]/i)
    end

    def valid_previous_result?(result)
      result && %i[success pending].include?(result[:status])
    end

    def extract_injection_value(result_hash)
      if result_hash.key?(:result)
        result_val = result_hash[:result]
        if result_val.is_a?(Hash) && result_val.key?(:status) && result_val.key?(:result)
          @logger.debug('Injecting nested result...')
          result_val[:result]
        else
          @logger.debug('Injecting direct result...')
          result_val
        end
      elsif result_hash.key?(:job_id)
        @logger.debug('Injecting job_id from previous step...')
        result_hash[:job_id]
      elsif result_hash.key?(:message)
        @logger.debug('Injecting message from previous step...')
        result_hash[:message]
      else
        @logger.warn("Cannot inject: Previous successful/pending step missing usable key (:result, :job_id, :message). Prev Hash: #{result_hash.inspect}")
        nil
      end
    end
  end
end
