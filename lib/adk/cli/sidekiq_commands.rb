# File: lib/adk/cli/sidekiq_commands.rb
# frozen_string_literal: true

require 'thor'
require 'open3'

module ADK
  module CLI
    # Commands for managing Sidekiq workers and jobs
    class SidekiqCommands < Thor
      desc 'start', 'Start a local Sidekiq worker process for processing ADK async jobs'
      method_option :require, type: :string,
                              desc: 'Optional: Path to require for loading your application environment (defaults to ADK environment)'
      method_option :queue, type: :string, default: 'default', desc: 'Queue to process (comma-separated for multiple)'
      method_option :concurrency, type: :numeric, default: 5, desc: 'Number of concurrent workers'
      method_option :verbose, type: :boolean, default: false, desc: 'Enable verbose output'
      def start
        require_path = options[:require]
        queues = options[:queue]
        concurrency = options[:concurrency]
        verbose = options[:verbose]

        # Build the Sidekiq command
        cmd = %w[bundle exec sidekiq]
        cmd << '-r' << require_path if require_path # Only add -r if a path is specified
        cmd << '-q' << queues
        cmd << '-c' << concurrency.to_s
        cmd << '-v' if verbose

        puts 'Starting Sidekiq worker with the following options:'
        puts "  Require path: #{require_path || 'ADK environment (default)'}"
        puts "  Queues: #{queues}"
        puts "  Concurrency: #{concurrency}"
        puts "  Verbose: #{verbose}"
        puts "\nRunning command: #{cmd.join(' ')}"
        puts "\nPress Ctrl+C to stop the worker"

        # Execute the command
        begin
          # Use Open3 to capture output and allow for Ctrl+C interruption
          Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
            # Handle stdout
            Thread.new do
              while line = stdout.gets
                puts line
              end
            end

            # Handle stderr
            Thread.new do
              while line = stderr.gets
                STDERR.puts line
              end
            end

            # Wait for the process to finish
            wait_thr.value
          end
        rescue Interrupt
          puts "\nStopping Sidekiq worker..."
        rescue => e
          puts "Error starting Sidekiq: #{e.message}"
          exit 1
        end
      end

      desc 'stop', 'Stop all Sidekiq workers gracefully'
      method_option :require, type: :string,
                              desc: 'Optional: Path to require for loading your application environment (defaults to ADK environment)'
      def stop
        require_path = options[:require]

        # Build the Sidekiq command
        cmd = %w[bundle exec sidekiqctl shutdown]
        cmd << '-r' << require_path if require_path # Only add -r if a path is specified

        puts 'Stopping Sidekiq workers gracefully...'
        puts "Running command: #{cmd.join(' ')}"

        # Execute the command
        begin
          system(*cmd)
          puts 'Sidekiq workers stopped successfully.'
        rescue => e
          puts "Error stopping Sidekiq workers: #{e.message}"
          exit 1
        end
      end

      desc 'status', 'Check the status of Sidekiq workers and queues'
      method_option :require, type: :string,
                              desc: 'Optional: Path to require for loading your application environment (defaults to ADK environment)'
      def status
        require_path = options[:require]

        # Build the Sidekiq command
        cmd = %w[bundle exec sidekiqctl status]
        cmd << '-r' << require_path if require_path # Only add -r if a path is specified

        puts 'Checking Sidekiq status...'
        puts "Running command: #{cmd.join(' ')}"

        # Execute the command
        begin
          system(*cmd)
        rescue => e
          puts "Error checking Sidekiq status: #{e.message}"
          exit 1
        end
      end

      desc 'list_jobs', 'List pending jobs in Sidekiq queues'
      method_option :require, type: :string,
                              desc: 'Optional: Path to require for loading your application environment (defaults to ADK environment)'
      method_option :queue, type: :string, default: 'default', desc: 'Queue to list jobs from'
      def list_jobs
        require_path = options[:require]
        queue = options[:queue]

        # Build the Sidekiq command
        cmd = %w[bundle exec sidekiqctl list_jobs]
        cmd << '-r' << require_path if require_path # Only add -r if a path is specified
        cmd << '-q' << queue

        puts "Listing jobs in queue '#{queue}'..."
        puts "Running command: #{cmd.join(' ')}"

        # Execute the command
        begin
          system(*cmd)
        rescue => e
          puts "Error listing Sidekiq jobs: #{e.message}"
          exit 1
        end
      end
    end
  end
end
