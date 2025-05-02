require 'spec_helper'
require 'adk' # Load the file under test

RSpec.describe ADK do
  # Helper to temporarily set environment variables
  def with_env(vars)
    original_values = ENV.to_h
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    ENV.replace(original_values)
  end

  # Helper to reset the logger instance between tests
  before(:each) do
    ADK.instance_variable_set(:@logger, nil)
  end

  after(:each) do
    # Ensure logger is reset even if test fails
    ADK.instance_variable_set(:@logger, nil)
    # Reset relevant ENV vars if they were modified directly without with_env
    ENV.delete('ADK_LOG_LEVEL')
    ENV.delete('RACK_ENV')
  end

  describe '.logger' do
    context 'when ADK_LOG_LEVEL is not set' do
      it 'defaults to WARN level' do
        # Need to unset RACK_ENV too, as it can influence the default
        with_env('RACK_ENV' => nil, 'ADK_LOG_LEVEL' => nil) do
          expect(ADK.logger.level).to eq(Logger::WARN)
        end
      end

      it 'defaults to DEBUG level when RACK_ENV is development' do
        with_env('RACK_ENV' => 'development', 'ADK_LOG_LEVEL' => nil) do
          expect(ADK.logger.level).to eq(Logger::DEBUG)
        end
      end
    end

    context 'when ADK_LOG_LEVEL is set' do
      it 'sets the logger level to DEBUG' do
        with_env('ADK_LOG_LEVEL' => 'DEBUG') do
          expect(ADK.logger.level).to eq(Logger::DEBUG)
        end
      end

      it 'sets the logger level to INFO' do
        with_env('ADK_LOG_LEVEL' => 'INFO') do
          expect(ADK.logger.level).to eq(Logger::INFO)
        end
      end

      it 'sets the logger level to WARN' do
        with_env('ADK_LOG_LEVEL' => 'WARN') do
          expect(ADK.logger.level).to eq(Logger::WARN)
        end
      end

      it 'sets the logger level to ERROR' do
        with_env('ADK_LOG_LEVEL' => 'ERROR') do
          expect(ADK.logger.level).to eq(Logger::ERROR)
        end
      end

      it 'sets the logger level to FATAL' do
        with_env('ADK_LOG_LEVEL' => 'FATAL') do
          expect(ADK.logger.level).to eq(Logger::FATAL)
        end
      end

      it 'defaults to WARN for unrecognized levels' do
        with_env('ADK_LOG_LEVEL' => 'SOMETHING_ELSE') do
          # Capture stdout to prevent pollution during test
          original_stdout = $stdout
          $stdout = StringIO.new
          begin
            expect(ADK.logger.level).to eq(Logger::WARN)
          ensure
            $stdout = original_stdout # Restore stdout
          end
        end
      end

      it 'does not output anything when level is NONE' do
        with_env('ADK_LOG_LEVEL' => 'NONE') do
          original_stdout = $stdout
          output_io = StringIO.new
          $stdout = output_io
          begin
            logger_instance = ADK.logger
            # Level should be higher than FATAL
            expect(logger_instance.level).to be > Logger::FATAL
            # Check that nothing is logged
            logger_instance.warn('This should not appear')
            logger_instance.error('This should not appear either')
            output_io.rewind
            expect(output_io.read).to be_empty
          ensure
            $stdout = original_stdout
          end
        end
      end

      it 'does not output anything when level is SILENT' do
        with_env('ADK_LOG_LEVEL' => 'SILENT') do
          original_stdout = $stdout
          output_io = StringIO.new
          $stdout = output_io
          begin
            logger_instance = ADK.logger
            # Level should be higher than FATAL
            expect(logger_instance.level).to be > Logger::FATAL
            # Check that nothing is logged
            logger_instance.warn('This should not appear')
            logger_instance.error('This should not appear either')
            output_io.rewind
            expect(output_io.read).to be_empty
          ensure
            $stdout = original_stdout
          end
        end
      end

      it 'uses $stdout when log level is not NONE or SILENT' do
        with_env('ADK_LOG_LEVEL' => 'DEBUG') do
          # Capture stdout to prevent pollution and check initialization message
          original_stdout = $stdout
          output_io = StringIO.new
          $stdout = output_io
          begin
            logger_instance = ADK.logger
            expect(logger_instance.instance_variable_get(:@logdev).dev).to eq($stdout) # Should be the captured $stdout
            # Check that the initialization message was printed
            output_io.rewind # Go back to the start of the captured output
            expect(output_io.read).to match(/ADK Logger initialized with level: DEBUG/)
          ensure
            $stdout = original_stdout # Restore original stdout
          end
        end
      end
    end
  end

  describe '.load_environment' do
    # Need to allow require globally as RSpec uses it internally
    before { allow(ADK).to receive(:require).and_call_original }

    it 'attempts to require bundler/setup and dotenv/load' do
      expect(ADK).to receive(:require).with('bundler/setup').ordered
      expect(ADK).to receive(:require).with('dotenv/load').ordered
      ADK.load_environment
    end

    it 'ignores LoadError when requiring bundler/setup' do
      expect(ADK).to receive(:require).with('bundler/setup').and_raise(LoadError)
      expect(ADK).to receive(:require).with('dotenv/load') # Should still attempt this
      expect { ADK.load_environment }.not_to raise_error
    end

    it 'ignores LoadError when requiring dotenv/load' do
      expect(ADK).to receive(:require).with('bundler/setup') # Assume this works
      expect(ADK).to receive(:require).with('dotenv/load').and_raise(LoadError)
      expect { ADK.load_environment }.not_to raise_error
    end
  end

  describe '.configure' do
    it 'yields self to the block' do
      expect { |b| ADK.configure(&b) }.to yield_with_args(ADK)
    end

    it 'calls configure_sidekiq after yielding' do
      # Use a flag to ensure the block runs before the check
      block_executed = false
      # Spy on configure_sidekiq
      allow(ADK).to receive(:configure_sidekiq)

      ADK.configure do |_config|
        block_executed = true
      end

      expect(block_executed).to be true
      expect(ADK).to have_received(:configure_sidekiq)
    end
  end

  describe '.redis_url=' do
    let(:new_url) { 'redis://new-host:6380/1' }
    # Keep track of original options to restore
    let!(:original_redis_options) { ADK.redis_options.dup }

    after do
      # Restore original settings to avoid side effects
      ADK.instance_variable_set(:@redis_options, original_redis_options)
      ADK.configure_sidekiq # Reconfigure with original settings
    end

    it 'updates the redis_options url' do
      allow(ADK).to receive(:configure_sidekiq) # Stub out side effect
      ADK.redis_url = new_url
      expect(ADK.redis_options[:url]).to eq(new_url)
    end

    it 'calls configure_sidekiq' do
      # Stub the method entirely for this test to isolate the call
      # triggered by the setter itself and ignore the `after` block call.
      allow(ADK).to receive(:configure_sidekiq)
      ADK.redis_url = new_url
      # Now verify it was called at least once during the assignment.
      expect(ADK).to have_received(:configure_sidekiq).at_least(:once)
    end
  end

  describe '.redis_options' do
    it 'returns the current redis options hash' do
      # Basic check, assuming default or ENV var
      expect(ADK.redis_options).to be_a(Hash)
      expect(ADK.redis_options).to have_key(:url)
    end
  end

  describe '.configure_sidekiq' do
    let(:redis_url) { ADK.redis_options[:url] } # Get current url
    let(:sidekiq_config_spy) { spy('Sidekiq::Config') }

    before do
      # Ensure logger is initialized so we can spy on it
      allow(ADK).to receive(:logger).and_call_original
      ADK.logger # Initialize logger
      # Stub the configuration block
      allow(Sidekiq).to receive(:configure_client).and_yield(sidekiq_config_spy)
      # Stub logger methods to prevent output pollution and allow spying
      allow(ADK.logger).to receive(:info)
      allow(ADK.logger).to receive(:error)
    end

    it 'configures Sidekiq client with current redis options' do
      ADK.configure_sidekiq
      expect(sidekiq_config_spy).to have_received(:redis=).with(ADK.redis_options)
      expect(ADK.logger).to have_received(:info).with(/Sidekiq client configured with Redis: #{redis_url}/)
    end

    context 'when Redis connection fails' do
      before do
        # Make the redis assignment raise the error
        allow(sidekiq_config_spy).to receive(:redis=).and_raise(Redis::CannotConnectError, 'connection refused')
      end

      it 'logs an error message' do
        ADK.configure_sidekiq
        expect(ADK.logger).to have_received(:error).with(/Sidekiq failed to configure Redis client: connection refused/)
      end

      it 'does not raise the error' do
        expect { ADK.configure_sidekiq }.not_to raise_error
      end
    end
  end
end
