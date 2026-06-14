# frozen_string_literal: true

require 'spec_helper'
require 'legate/agent'

# Coverage for the actionable "tool not found" warning (DX2): did-you-mean +
# available list, softened when MCP servers are configured.
RSpec.describe 'Agent unknown-tool warning' do
  before do
    Legate::GlobalToolManager.reset!
    [Legate::Tools::Echo, Legate::Tools::Calculator].each { |t| Legate::GlobalToolManager.register_tool(t) }
  end

  def build_agent(mcp: false)
    definition = Legate::AgentDefinition.new.define do |a|
      a.name :resolver
      a.instruction 'x'
      a.use_tool :echo
      a.mcp_servers({ type: :sse, url: 'http://localhost:9292/mcp' }) if mcp
    end
    Legate::Agent.new(definition: definition)
  end

  def warning_for(agent, missing)
    agent.send(:missing_tools_warning, Set.new(missing), agent.instance_variable_get(:@definition))
  end

  it 'suggests a close match and lists available tools (no MCP -> definitely a typo)' do
    msg = warning_for(build_agent, [:eco])
    expect(msg).to include('did you mean: echo')
    expect(msg).to include('Available tools:')
    expect(msg).to include('echo', 'calculator')
    expect(msg).to include('These tools will be unavailable.')
  end

  it 'softens the message when MCP servers are configured' do
    msg = warning_for(build_agent(mcp: true), [:some_remote_tool])
    expect(msg).to include('MCP tools register when the agent connects')
    expect(msg).not_to include('These tools will be unavailable.')
  end
end
