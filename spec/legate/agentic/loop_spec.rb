# frozen_string_literal: true

require 'spec_helper'
require 'legate/agentic/loop'

RSpec.describe Legate::Agentic::Loop do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:planner) { instance_double(Legate::Planner) }
  let(:executor) { instance_double(Legate::PlanExecutor) }
  let(:session) { instance_double(Legate::Session) }
  let(:session_service) { instance_double(Legate::SessionService::InMemory) }

  subject(:loop) { described_class.new(planner: planner, executor: executor, logger: logger) }

  def run
    loop.run(user_input: 'do the thing', session: session, session_service: session_service, invocation_id: 'inv-1')
  end

  def tool_decision(name, params = {})
    Legate::Agentic::Decision.tool(tool: name, params: params)
  end

  def final_decision(answer)
    Legate::Agentic::Decision.final(answer: answer)
  end

  it 'returns the final answer immediately when the model finishes' do
    allow(planner).to receive(:reason_next_action).and_return(final_decision('42'))
    expect(executor).not_to receive(:execute_step)

    result = run
    expect(result[:last_result]).to eq(status: :success, result: '42')
  end

  it 'runs tools, feeds results back, and finishes (multi-step)' do
    allow(planner).to receive(:reason_next_action).and_return(
      tool_decision(:search, { q: 'ruby' }),
      tool_decision(:fetch, { url: 'u' }),
      final_decision('found it')
    )
    allow(executor).to receive(:execute_step).and_return(
      { status: :success, result: 'a link' },
      { status: :success, result: 'page body' }
    )

    result = run

    expect(executor).to have_received(:execute_step).twice
    expect(result[:last_result]).to eq(status: :success, result: 'found it')
    # Observations accumulated and sanitized.
    expect(result[:details].map { |o| o[:tool] }).to eq(%i[search fetch])
  end

  it 'passes accumulated observations back to the planner each turn' do
    seen = []
    allow(planner).to receive(:reason_next_action) do |_input, observations, _id|
      seen << observations.length
      observations.empty? ? tool_decision(:search) : final_decision('done')
    end
    allow(executor).to receive(:execute_step).and_return({ status: :success, result: 'x' })

    run
    expect(seen).to eq([0, 1]) # first turn no observations, second turn one
  end

  it 'recovers from a tool error instead of aborting' do
    allow(planner).to receive(:reason_next_action).and_return(
      tool_decision(:flaky),
      final_decision('recovered')
    )
    allow(executor).to receive(:execute_step).and_return({ status: :error, error_message: 'boom' })

    result = run
    expect(result[:last_result]).to eq(status: :success, result: 'recovered')
    expect(result[:details].first[:result][:status]).to eq(:error)
  end

  it 'treats a tool that raises as an error observation (loop continues)' do
    allow(planner).to receive(:reason_next_action).and_return(
      tool_decision(:explodes),
      final_decision('ok')
    )
    allow(executor).to receive(:execute_step).and_raise(StandardError, 'kaboom')

    result = run
    expect(result[:last_result]).to eq(status: :success, result: 'ok')
    expect(result[:details].first[:result][:error_message]).to include('kaboom')
  end

  it 'stops with an error when the model returns an unusable decision' do
    allow(planner).to receive(:reason_next_action).and_return(Legate::Agentic::Decision.invalid)
    result = run
    expect(result[:last_result][:status]).to eq(:error)
  end

  it 'stops at the iteration cap without a final answer' do
    capped = described_class.new(planner: planner, executor: executor, logger: logger, max_iterations: 3)
    allow(planner).to receive(:reason_next_action).and_return(tool_decision(:search))
    # Distinct results each turn -> the agent is "making progress" but never
    # finalizes, so it runs to the cap (vs. the loop-breaker case below).
    allow(executor).to receive(:execute_step).and_return(
      { status: :success, result: 'a' }, { status: :success, result: 'b' }, { status: :success, result: 'c' }
    )
    allow(planner).to receive(:summarize_final).and_return(nil) # no best-effort summary available

    result = capped.run(user_input: 'x', session: session, session_service: session_service, invocation_id: 'i')
    expect(executor).to have_received(:execute_step).exactly(3).times
    expect(result[:last_result][:status]).to eq(:error)
    expect(result[:last_result][:error_message]).to include('3 steps')
  end

  it 'returns a best-effort summary when it stops without a final answer' do
    capped = described_class.new(planner: planner, executor: executor, logger: logger, max_iterations: 2)
    allow(planner).to receive(:reason_next_action).and_return(tool_decision(:search))
    allow(executor).to receive(:execute_step).and_return({ status: :success, result: 'a' }, { status: :success, result: 'b' })
    allow(planner).to receive(:summarize_final).and_return('Best effort from what I found.')

    result = capped.run(user_input: 'x', session: session, session_service: session_service, invocation_id: 'i')
    expect(result[:last_result]).to eq(status: :success, result: 'Best effort from what I found.')
  end

  it 'breaks the loop when the model repeats the same action with the same result' do
    allow(planner).to receive(:reason_next_action).and_return(tool_decision(:search, { q: 'x' }))
    allow(executor).to receive(:execute_step).and_return({ status: :success, result: 'same' })
    allow(planner).to receive(:summarize_final).and_return(nil)

    result = run
    # Two identical observations is enough to detect spinning — it stops well
    # before the default 8-iteration cap.
    expect(executor).to have_received(:execute_step).twice
    expect(result[:last_result][:status]).to eq(:error)
    expect(result[:last_result][:error_message]).to include('repeating the same action')
  end

  it 'truncates complex tool results in observations' do
    allow(planner).to receive(:reason_next_action).and_return(tool_decision(:big), final_decision('done'))
    allow(executor).to receive(:execute_step).and_return({ status: :success, result: { nested: { a: 1 } } })

    result = run
    expect(result[:details].first[:result][:result]).to eq('[Complex Result Structure]')
  end

  it 'truncates very long string results fed back as observations' do
    long = 'z' * 5_000
    allow(planner).to receive(:reason_next_action).and_return(tool_decision(:big), final_decision('done'))
    allow(executor).to receive(:execute_step).and_return({ status: :success, result: long })

    result = run
    fed_back = result[:details].first[:result][:result]
    expect(fed_back.length).to be < long.length
    expect(fed_back).to include('truncated 3000 chars')
  end
end
