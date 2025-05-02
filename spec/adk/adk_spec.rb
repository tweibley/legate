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

  # TODO: Add tests for .configure, .redis_url=, .redis_options, .configure_sidekiq, .load_environment
end
