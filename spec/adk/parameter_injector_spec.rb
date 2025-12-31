# frozen_string_literal: true

require 'spec_helper'
require 'adk/parameter_injector'

RSpec.describe ADK::ParameterInjector do
  let(:logger) { instance_double(Logger, debug: nil, warn: nil, info: nil, error: nil) }
  subject { described_class.new(logger: logger) }

  describe '#inject' do
    let(:previous_result_success) { { status: :success, result: 'injected_value' } }
    let(:previous_result_failed) { { status: :error, error_message: 'failed' } }

    context 'when params contain no placeholders' do
      it 'returns original params' do
        params = { key: 'value', number: 123 }
        result = subject.inject(params, previous_result_success)
        expect(result).to eq(params)
      end
    end

    context 'when params contain placeholders' do
      let(:params) { { input: '[Result from previous step]' } }

      context 'and previous result is successful' do
        it 'injects the result' do
          result = subject.inject(params, previous_result_success)
          expect(result[:input]).to eq('injected_value')
        end

        it 'injects nested result if present' do
          nested_result = { status: :success, result: { status: :success, result: 'nested_value' } }
          result = subject.inject(params, nested_result)
          expect(result[:input]).to eq('nested_value')
        end

        it 'injects job_id if result is missing but job_id is present' do
          job_result = { status: :success, job_id: 'job_123' }
          result = subject.inject(params, job_result)
          expect(result[:input]).to eq('job_123')
        end

        it 'injects message if result/job_id are missing but message is present' do
          msg_result = { status: :success, message: 'done' }
          result = subject.inject(params, msg_result)
          expect(result[:input]).to eq('done')
        end

        it 'warns and keeps placeholder if no usable key is found' do
          empty_result = { status: :success }
          result = subject.inject(params, empty_result)
          expect(result[:input]).to eq('[Result from previous step]')
          expect(logger).to have_received(:warn).with(/Cannot inject: Previous successful\/pending step missing usable key/)
        end
      end

      context 'and previous result is failed or missing' do
        it 'warns and keeps placeholder if previous result is failed' do
          result = subject.inject(params, previous_result_failed)
          expect(result[:input]).to eq('[Result from previous step]')
          expect(logger).to have_received(:warn).with(/Cannot inject: Previous step failed or absent/)
        end

        it 'warns and keeps placeholder if previous result is nil' do
          result = subject.inject(params, nil)
          expect(result[:input]).to eq('[Result from previous step]')
          expect(logger).to have_received(:warn).with(/Cannot inject: Previous step failed or absent/)
        end
      end

      context 'with regex variations' do
        it 'matches [Result from step N]' do
          params = { input: '[Result from step 1]' }
          result = subject.inject(params, previous_result_success)
          expect(result[:input]).to eq('injected_value')
        end

        it 'is case insensitive' do
          params = { input: '[result from PREVIOUS STEP]' }
          result = subject.inject(params, previous_result_success)
          expect(result[:input]).to eq('injected_value')
        end
      end
    end
  end
end
