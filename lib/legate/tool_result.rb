# File: lib/legate/tool_result.rb
# frozen_string_literal: true

module Legate
  # A typed, immutable result a tool's #perform_execution may return instead of
  # building the canonical `{ status:, result:/error_message:/job_id: }` hash by
  # hand (R11, additive). Tool#execute normalizes it to that hash, so everything
  # downstream is unchanged — this is purely an authoring convenience.
  #
  #   def perform_execution(params, _context)
  #     ToolResult.success("Hello, #{params[:name]}!")
  #   end
  #
  # Pairs with the Event#answer / #success? / #error? accessors.
  ToolResult = Data.define(:status, :result, :error_message, :job_id, :message) do
    # @return [ToolResult] a successful result carrying an optional value
    def self.success(value = nil)
      new(status: :success, result: value, error_message: nil, job_id: nil, message: nil)
    end

    # @return [ToolResult] an error result
    def self.error(message)
      new(status: :error, result: nil, error_message: message.to_s, job_id: nil, message: nil)
    end

    # @return [ToolResult] a pending (async) result referencing a job
    def self.pending(job_id:, message: nil)
      new(status: :pending, result: nil, error_message: nil, job_id: job_id, message: message)
    end

    def success?
      status == :success
    end

    def error?
      status == :error
    end

    def pending?
      status == :pending
    end

    # The canonical result hash the rest of Legate speaks. Only the keys relevant
    # to the status are included, matching what hand-built tool hashes produce.
    # @return [Hash]
    def to_h
      case status
      when :success
        { status: :success, result: result }
      when :error
        { status: :error, error_message: error_message }
      when :pending
        out = { status: :pending, job_id: job_id }
        out[:message] = message unless message.nil?
        out
      else
        { status: status }
      end
    end
  end
end
