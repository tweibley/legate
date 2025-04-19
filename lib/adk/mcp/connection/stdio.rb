# File: lib/adk/mcp/connection/stdio.rb
# frozen_string_literal: true

require 'open3'
require 'json'
require 'thread' # For reading stdout/stderr concurrently
require_relative '../error'

module ADK
  module Mcp
    module Connection
      # Manages a connection to an MCP server via STDIO.
      class Stdio
        # How long to wait for process startup or initial output
        PROCESS_START_TIMEOUT = 5 # seconds
        # How long to wait when reading a response line
        READ_TIMEOUT = 10 # seconds
        # Max consecutive JSON parse errors before considering connection broken
        PARSE_ERROR_THRESHOLD = 5

        attr_reader :command, :args, :last_error

        def initialize(command:, args: [])
          @command = command
          @args = args
          @stdin = nil
          @stdout = nil
          @stderr = nil
          @wait_thr = nil
          @stderr_thread = nil
          @connected = false
          @request_id_counter = 0
          @response_queue = Queue.new # <-- Back to response_queue
          @notification_queue = Queue.new # <-- Back to notification_queue
          @stdout_reader_thread = nil
          @last_error = nil
          @pid = nil
          @consecutive_parse_errors = 0 # Initialize counter
        end

        def connected?
          @connected && @wait_thr&.alive?
        end

        # Connects to the MCP server process.
        # Launches the command and starts threads to monitor stdout/stderr.
        # @raise [ConnectionError] if the process fails to start or terminates unexpectedly.
        def connect
          return true if connected?

          Mcp.logger.info("Connecting via STDIO: #{@command} #{@args.join(' ')}")
          @last_error = nil
          stderr_pipe_read, stderr_pipe_write = IO.pipe

          begin
            # Use popen3 to capture stdin, stdout, stderr, and wait_thr
            @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(@command, *@args, err: stderr_pipe_write)
            @pid = @wait_thr.pid
            stderr_pipe_write.close # Close the write end in the parent

            Mcp.logger.debug("MCP process started with PID: #{@pid}")

            # Thread to read stderr and log/store errors
            @stderr_thread = Thread.new do
              begin
                stderr_pipe_read.each_line do |line|
                  Mcp.logger.error("[MCP Server STDERR] #{line.chomp}")
                  @last_error = line.chomp # Store last error line
                end
              rescue IOError => e
                Mcp.logger.debug("Stderr pipe closed: #{e.message}")
              ensure
                stderr_pipe_read.close unless stderr_pipe_read.closed?
              end
            end

            # Thread to continuously read stdout and parse JSON-RPC messages
            @stdout_reader_thread = Thread.new do
              Mcp.logger.debug("[Stdio Connection #{@pid}] stdout_reader_thread starting...")
              begin
                @stdout.each_line do |line|
                  line.strip! # Remove leading/trailing whitespace
                  next if line.empty? # Skip empty lines

                  ADK.logger.debug("<- [MCP Server STDOUT Raw] #{line}")

                  # Attempt to parse only if it looks like JSON
                  if line.start_with?('{') || line.start_with?('[')
                    begin
                      message = JSON.parse(line, symbolize_names: true)
                      ADK.logger.debug("[Stdio Connection #{@pid}] Received Parsed JSON:\n#{JSON.pretty_generate(message)}")
                      @consecutive_parse_errors = 0 # Reset on successful parse

                      # Route to correct queue based on ID presence/value
                      if message.key?(:id) && message[:id].nil? # MCP Notifications might have null id
                        @notification_queue << message
                      elsif message.key?(:id)
                        ADK.logger.debug("[Stdio Connection #{@pid}] Queuing response ID: #{message[:id]}")
                        @response_queue << message # Responses have non-null id
                      else # Assume notification for now
                        @notification_queue << message
                        ADK.logger.warn("Received MCP message without explicit id: #{message.inspect}")
                      end
                    rescue JSON::ParserError => e
                      ADK.logger.error("Failed to parse potential MCP JSON from stdout: #{e.message}. Line: #{line}")
                      @consecutive_parse_errors += 1
                      if @consecutive_parse_errors >= PARSE_ERROR_THRESHOLD # Use >= for clarity
                        ADK.logger.fatal("Too many consecutive JSON parse errors (#{PARSE_ERROR_THRESHOLD} reached). Assuming MCP connection broken.")
                        @connected = false # Mark connection as broken
                        @last_error = "Too many consecutive JSON parse errors."
                        break # Stop reading from stdout
                      end
                    end
                  else
                    # Log lines that don't look like JSON instead of trying to parse
                    ADK.logger.debug("Skipping non-JSON line from MCP STDOUT: #{line}")
                    # Do not increment parse error count for these lines
                  end
                end
                ADK.logger.info("MCP Server stdout stream ended.")
              rescue IOError => e
                ADK.logger.info("MCP Server stdout pipe closed: #{e.message}")
              ensure
                @connected = false # Mark as disconnected if stdout closes or loop breaks due to errors
                Mcp.logger.debug("[Stdio Connection #{@pid}] stdout_reader_thread finished.")
              end
            end

            @connected = true
            Mcp.logger.info("MCP STDIO connection established.")
            true
          rescue Errno::ENOENT => e
            @last_error = "Command not found: #{@command}"
            Mcp.logger.error("#{@last_error} - #{e.message}")
            raise ConnectionError, @last_error
          rescue StandardError => e
            @last_error = "Failed to start MCP process: #{e.message}"
            Mcp.logger.error("#{@last_error}")
            # Clean up if process started partially
            disconnect(force: true)
            raise ConnectionError, @last_error
          end
        end

        # Sends a JSON-RPC request object to the server process.
        # @param json_rpc_hash [Hash] The request hash (e.g., {jsonrpc: '2.0', method: '...', params: ..., id: ...})
        # @raise [ConnectionError] if not connected.
        def send_request(json_rpc_hash)
          raise ConnectionError, 'Not connected' unless connected?

          begin
            request_json = json_rpc_hash.to_json
            Mcp.logger.debug("-> [MCP Client STDIN] #{request_json}")
            @stdin.puts(request_json)
            @stdin.flush # Ensure data is sent immediately
          rescue Errno::EPIPE => e
            @connected = false
            @last_error = "MCP process stdin pipe broke: #{e.message}"
            Mcp.logger.error(@last_error)
            raise ConnectionError, @last_error
          rescue StandardError => e
            @connected = false
            @last_error = "Error writing to MCP process stdin: #{e.class} - #{e.message}"
            Mcp.logger.error("#{@last_error}\n#{e.backtrace.join("\n")}")
            raise ConnectionError, @last_error
          end
        end

        # Reads the next available response or notification.
        # This is a low-level method; typically use Client methods which match request/response.
        # @param timeout [Numeric, nil] Seconds to wait for a message, nil to wait indefinitely.
        # @return [Hash, nil] The parsed JSON-RPC message, or nil if timeout occurs.
        # @raise [ConnectionError] if not connected or connection lost.
        def read_message(timeout = READ_TIMEOUT)
          raise ConnectionError, 'Not connected' unless connected?

          # Check both queues, prioritize responses if available
          begin
            return @response_queue.pop(true) # non_block = true
          rescue ThreadError
            # Response queue empty, check notifications
            begin
              return @notification_queue.pop(true)
            rescue ThreadError
              # Both empty, wait with timeout if specified
              return nil if timeout == 0 # Don't wait if timeout is 0

              # We need to wait on *either* queue. This is tricky.
              # A simple approach: check status, sleep briefly, check again.
              # A better approach might use IO.select or a condition variable signaled by the reader thread.
              # For now, use Queue#pop with timeout (blocks this thread).
              # Note: This waits on the response queue first.
              begin
                # Use non-blocking pop with a short sleep loop to approximate timeout
                # while still allowing connection checks.
                start_time = Time.now
                loop do
                  begin
                    return @response_queue.pop(true)
                  rescue ThreadError # Queue empty
                    # Check notifications non-blockingly as well
                    begin
                      return @notification_queue.pop(true)
                    rescue ThreadError
                      # Both still empty
                    end

                    # Check timeout
                    if timeout && (Time.now - start_time >= timeout)
                      return nil # Timeout reached
                    end
                    # Check connection status inside loop
                    raise ConnectionError, "Connection lost while waiting for message" unless connected?

                    sleep(0.01) # Small sleep
                  end
                end
              end
            end
          end
        ensure
          # Check if connection died while waiting (important after blocking operations)
          raise ConnectionError, "Connection lost while reading message" unless connected?
        end

        # Disconnects from the server process.
        # Terminates the process and cleans up threads.
        # @param force [Boolean] If true, use SIGKILL if SIGTERM fails.
        # @param timeout [Numeric] Seconds to wait for graceful shutdown.
        def disconnect(force: false, timeout: 5)
          return unless @connected || @wait_thr # Only proceed if we have something to disconnect

          Mcp.logger.info("Disconnecting from MCP STDIO process (PID: #{@pid})...")
          @connected = false # Mark as disconnected immediately

          # Close stdin first to signal EOF to the process
          @stdin&.close unless @stdin&.closed?

          # Stop reader threads gracefully if possible
          @stdout_reader_thread&.kill
          @stderr_thread&.kill

          # Close stdout/stderr pipes
          @stdout&.close unless @stdout&.closed?
          @stderr&.close unless @stderr&.closed?

          # Terminate the process
          if @wait_thr&.pid
            pid = @wait_thr.pid
            begin
              Mcp.logger.debug("Sending SIGTERM to PID #{pid}...")
              Process.kill('TERM', pid)
              process_exited = @wait_thr.join(timeout)

              unless process_exited
                Mcp.logger.warn("MCP process PID #{pid} did not exit after SIGTERM and #{timeout}s timeout.")
                if force
                  Mcp.logger.warn("Forcing shutdown with SIGKILL for PID #{pid}.")
                  Process.kill('KILL', pid)
                  @wait_thr.join
                end
              end
              Mcp.logger.info("MCP process PID #{pid} terminated. Status: #{@wait_thr.value}")
            rescue Errno::ESRCH
              Mcp.logger.info("MCP process PID #{pid} already exited.")
            rescue StandardError => e
              Mcp.logger.debug("Caught StandardError during termination: #{e.class}")
              Mcp.logger.error("Error during process termination for PID #{pid}: #{e.message}")
            end
          end

          # Final cleanup
          @stdin = @stdout = @stderr = @wait_thr = @pid = nil
          # Clear queues
          @response_queue.clear
          @notification_queue.clear
          Mcp.logger.info("MCP STDIO connection closed.")
        end

        # Generates the next unique request ID.
        # @return [Integer]
        def next_request_id
          @request_id_counter += 1
        end
      end
    end
  end
end
