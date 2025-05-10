# frozen_string_literal: true
require 'thread'

# Simple module structure to match our class hierarchy
module ADK
  module Mcp
    module Connection
      class SimpleTestSse
        attr_reader :notification_queue, :connected

        def initialize
          @notification_queue = Queue.new
          @connected = true
        end

        def connected?
          @connected
        end

        # The test method
        def read_notification(timeout = 0.1)
          return nil unless connected?

          begin
            if timeout == 0
              return @notification_queue.pop(true)
            end

            Timeout.timeout(timeout) do
              return @notification_queue.pop
            end
          rescue ThreadError
            nil
          rescue Timeout::Error
            nil
          end
        end
      end
    end
  end
end

# Create an instance
connection = ADK::Mcp::Connection::SimpleTestSse.new

# Add a test item
notification = { jsonrpc: '2.0', method: 'notify_test' }
connection.notification_queue.push(notification)

# Test it
puts "Queue empty before test? #{connection.notification_queue.empty?}"
puts "Queue size before test: #{connection.notification_queue.size}"
result = connection.read_notification(0)
puts "Result: #{result.inspect}"
puts "Queue empty after test? #{connection.notification_queue.empty?}"

if result == notification
  puts 'TEST PASSED: Notification retrieved correctly'
else
  puts "TEST FAILED: Expected #{notification.inspect}, got #{result.inspect}"
end
