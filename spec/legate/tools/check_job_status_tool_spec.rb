# frozen_string_literal: true

# File: spec/legate/tools/check_job_status_tool_spec.rb
require 'spec_helper'
require 'json'

RSpec.describe Legate::Tools::CheckJobStatusTool do
  let(:tool_class) { described_class }
  let(:metadata) { tool_class.tool_metadata }
  let(:job_id) { 'jid_test_456' }
  let(:params) { { job_id: job_id } }
  let(:dummy_registry) { Legate::ToolRegistry.new } # Dummy registry
  let(:context) { Legate::ToolContext.new(session_id: 's', user_id: 'u', app_name: 'a', tool_registry: dummy_registry) }

  before do
    # Clear job results between tests
    Legate::Tools::BaseAsyncJobTool.job_results.clear
  end

  # Test Class Metadata directly
  describe 'Class Metadata' do
    it 'has the correct explicit name' do
      expect(metadata[:name]).to eq(:check_job_status)
    end

    it 'has the correct description' do
      expect(metadata[:description]).to include('Checks the status and retrieves the result')
    end

    it 'defines the job_id parameter correctly' do
      expect(metadata[:parameters].keys).to eq([:job_id])
      expect(metadata[:parameters][:job_id][:required]).to be true
      expect(metadata[:parameters][:job_id][:type]).to eq(:string)
    end
  end

  describe '#perform_execution' do
    subject(:tool) { tool_class.new } # Create instance for execution tests

    context 'when job_id is missing' do
      it 'returns an error status' do
        result = tool.send(:perform_execution, { wrong_param: 'x' }, context)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include('Missing job_id')
      end
    end

    context 'when job_id is blank' do
      it 'returns an error status' do
        result = tool.send(:perform_execution, { job_id: '   ' }, context)
        expect(result[:status]).to eq(:error)
        expect(result[:error_message]).to include('Missing job_id')
      end
    end

    context 'when job result is found (completed)' do
      before do
        Legate::Tools::BaseAsyncJobTool.job_results[job_id] = {
          'status' => 'completed',
          'result' => 'Job Complete!'
        }
      end

      it 'returns the stored success result' do
        result = tool.send(:perform_execution, params, context)
        expect(result[:status]).to eq(:success)
        expect(result[:job_status]).to eq('completed')
        expect(result[:result]).to eq('Job Complete!')
      end
    end

    context 'when job result is found (error)' do
      before do
        Legate::Tools::BaseAsyncJobTool.job_results[job_id] = {
          'status' => 'error',
          'error_message' => 'WorkerError: Failed internally'
        }
      end

      it 'returns the stored error result' do
        result = tool.send(:perform_execution, params, context)
        expect(result[:status]).to eq(:success)
        expect(result[:job_status]).to eq('error')
        expect(result[:error_message]).to eq('WorkerError: Failed internally')
      end
    end

    context 'when job result is pending' do
      before do
        Legate::Tools::BaseAsyncJobTool.job_results[job_id] = {
          'status' => 'pending'
        }
      end

      it 'returns a pending status' do
        result = tool.send(:perform_execution, params, context)
        expect(result[:status]).to eq(:success)
        expect(result[:job_status]).to eq('pending')
      end
    end

    context 'when job ID is not found' do
      it 'returns unknown status' do
        result = tool.send(:perform_execution, params, context)
        expect(result[:status]).to eq(:success)
        expect(result[:job_status]).to eq('unknown')
        expect(result[:message]).to include('Job ID not found')
      end
    end
  end
end
