# # File: spec/adk/cli/sidekiq_commands_spec.rb
# # frozen_string_literal: true

# require 'spec_helper'
# require 'adk/cli/sidekiq_commands'
# require 'open3'
# require 'thor'

# RSpec.describe ADK::CLI::SidekiqCommands do
#   let(:output) { StringIO.new }
#   let(:shell) { Thor::Shell::Basic.new }
#   subject(:cli) { described_class.new }

#   before do
#     # Configure shell for output capture - Redirect global stdout/stderr
#     # allow(shell).to receive(:stdout).and_return(output)
#     # allow(shell).to receive(:stderr).and_return(output)
#     # allow(cli).to receive(:shell).and_return(shell)
#     $stdout = output
#     $stderr = output

#     # Prevent actual command execution
#     allow(Open3).to receive(:popen3)
#     allow(cli).to receive(:system) # Stub system used in stop, status, list_jobs
#     allow(Kernel).to receive(:exit) # Prevent tests from exiting
#   end

#   after do
#     # Restore original stdout/stderr
#     $stdout = STDOUT
#     $stderr = STDERR
#   end

#   describe '#start' do
#     let(:default_cmd) { ['bundle', 'exec', 'sidekiq', '-q', 'default', '-c', '5'] }

#     it 'constructs the correct default command' do
#       expect(Open3).to receive(:popen3).with(*default_cmd)
#       cli.invoke(:start, [])
#       expect(output.string).to include('Running command: bundle exec sidekiq -q default -c 5')
#       expect(output.string).to include('Require path: ADK environment (default)')
#     end

#     it 'includes require path when specified' do
#       cmd = ['bundle', 'exec', 'sidekiq', '-r', './config/environment.rb', '-q', 'default', '-c', '5']
#       expect(Open3).to receive(:popen3).with(*cmd)
#       cli.invoke(:start, [], { require: './config/environment.rb' })
#       expect(output.string).to include('Running command: bundle exec sidekiq -r ./config/environment.rb -q default -c 5')
#       expect(output.string).to include('Require path: ./config/environment.rb')
#     end

#     it 'includes specified queues' do
#       cmd = ['bundle', 'exec', 'sidekiq', '-q', 'critical,high', '-c', '5']
#       expect(Open3).to receive(:popen3).with(*cmd)
#       cli.invoke(:start, [], { queue: 'critical,high' })
#       expect(output.string).to include('Queues: critical,high')
#     end

#     it 'includes specified concurrency' do
#       cmd = ['bundle', 'exec', 'sidekiq', '-q', 'default', '-c', '10']
#       expect(Open3).to receive(:popen3).with(*cmd)
#       cli.invoke(:start, [], { concurrency: 10 })
#       expect(output.string).to include('Concurrency: 10')
#     end

#     it 'includes verbose flag' do
#       cmd = ['bundle', 'exec', 'sidekiq', '-q', 'default', '-c', '5', '-v']
#       expect(Open3).to receive(:popen3).with(*cmd)
#       cli.invoke(:start, [], { verbose: true })
#       expect(output.string).to include('Verbose: true')
#     end

#     it 'handles Interrupt correctly' do
#       allow(Open3).to receive(:popen3).and_raise(Interrupt)
#       cli.start
#       expect(output.string).to include('Stopping Sidekiq worker...')
#       expect(Kernel).not_to have_received(:exit)
#     end

#     it 'handles generic errors and exits' do
#       error = StandardError.new("Something went wrong")
#       allow(Open3).to receive(:popen3).and_raise(error)
#       cli.start
#       expect(output.string).to include('Error starting Sidekiq: Something went wrong')
#       expect(Kernel).to have_received(:exit).with(1)
#     end

#     # Basic test to ensure output streaming logic doesn't break (mocking stdout/stderr of popen3)
#     it 'attempts to stream output' do
#       mock_stdout = instance_double(IO)
#       mock_stderr = instance_double(IO)
#       mock_wait_thr = instance_double(Process::Waiter, value: 0) # Simulate successful exit
#       allow(mock_stdout).to receive(:gets).and_return("Sidekiq output line", nil)
#       allow(mock_stderr).to receive(:gets).and_return("Sidekiq error line", nil)
#       allow(Open3).to receive(:popen3).with(*default_cmd).and_yield(nil, mock_stdout, mock_stderr, mock_wait_thr)

#       cli.start

#       # Give threads a moment to run (adjust sleep if needed)
#       sleep(0.01)

#       expect(output.string).to include("Sidekiq output line")
#       expect(output.string).to include("Sidekiq error line") # Check stderr capture too
#     end
#   end

#   describe '#stop' do
#     let(:default_cmd) { ['bundle', 'exec', 'sidekiqctl', 'shutdown'] }

#     it 'constructs the correct default command' do
#       expect(cli).to receive(:system).with(*default_cmd)
#       cli.stop
#       expect(output.string).to include('Running command: bundle exec sidekiqctl shutdown')
#     end

#     it 'includes require path when specified' do
#       cmd = ['bundle', 'exec', 'sidekiqctl', 'shutdown', '-r', './config/env.rb']
#       expect(cli).to receive(:system).with(*cmd)
#       cli.invoke(:stop, [], { require: './config/env.rb' })
#       expect(output.string).to include('Running command: bundle exec sidekiqctl shutdown -r ./config/env.rb')
#     end

#     it 'handles errors during execution and exits' do
#       error = StandardError.new("Control command failed")
#       allow(cli).to receive(:system).and_raise(error)
#       cli.stop
#       expect(output.string).to include('Error stopping Sidekiq workers: Control command failed')
#       expect(Kernel).to have_received(:exit).with(1)
#     end
#   end

#   describe '#status' do
#     let(:default_cmd) { ['bundle', 'exec', 'sidekiqctl', 'status'] }

#     it 'constructs the correct default command' do
#       expect(cli).to receive(:system).with(*default_cmd)
#       cli.status
#       expect(output.string).to include('Running command: bundle exec sidekiqctl status')
#     end

#     it 'includes require path when specified' do
#       cmd = ['bundle', 'exec', 'sidekiqctl', 'status', '-r', './env.rb']
#       expect(cli).to receive(:system).with(*cmd)
#       cli.invoke(:status, [], { require: './env.rb' })
#       expect(output.string).to include('Running command: bundle exec sidekiqctl status -r ./env.rb')
#     end

#     it 'handles errors during execution and exits' do
#       error = StandardError.new("Status check failed")
#       allow(cli).to receive(:system).and_raise(error)
#       cli.status
#       expect(output.string).to include('Error checking Sidekiq status: Status check failed')
#       expect(Kernel).to have_received(:exit).with(1)
#     end
#   end

#   describe '#list_jobs' do
#     let(:default_cmd) { ['bundle', 'exec', 'sidekiqctl', 'list_jobs', '-q', 'default'] }

#     it 'constructs the correct default command' do
#       expect(cli).to receive(:system).with(*default_cmd)
#       cli.list_jobs
#       expect(output.string).to include("Listing jobs in queue 'default'...")
#       expect(output.string).to include('Running command: bundle exec sidekiqctl list_jobs -q default')
#     end

#     it 'includes require path when specified' do
#       cmd = ['bundle', 'exec', 'sidekiqctl', 'list_jobs', '-r', './req.rb', '-q', 'default']
#       expect(cli).to receive(:system).with(*cmd)
#       cli.invoke(:list_jobs, [], { require: './req.rb' })
#       expect(output.string).to include('Running command: bundle exec sidekiqctl list_jobs -r ./req.rb -q default')
#     end

#     it 'includes specified queue' do
#       cmd = ['bundle', 'exec', 'sidekiqctl', 'list_jobs', '-q', 'low_priority']
#       expect(cli).to receive(:system).with(*cmd)
#       cli.invoke(:list_jobs, [], { queue: 'low_priority' })
#       expect(output.string).to include("Listing jobs in queue 'low_priority'...")
#       expect(output.string).to include('Running command: bundle exec sidekiqctl list_jobs -q low_priority')
#     end

#     it 'handles errors during execution and exits' do
#       error = StandardError.new("Job listing failed")
#       allow(cli).to receive(:system).and_raise(error)
#       cli.list_jobs
#       expect(output.string).to include('Error listing Sidekiq jobs: Job listing failed')
#       expect(Kernel).to have_received(:exit).with(1)
#     end
#   end
# end
