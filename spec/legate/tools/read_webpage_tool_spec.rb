# File: spec/legate/tools/read_webpage_tool_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'legate/tools/read_webpage_tool'
require 'webmock/rspec'

Legate.logger.level = Logger::FATAL

RSpec.describe Legate::Tools::ReadWebpage do
  let(:tool) { described_class.new }

  around do |example|
    WebMock.enable!
    WebMock.disable_net_connect!
    example.run
    WebMock.reset!
    WebMock.disable!
  end

  it 'has the inferred tool name :read_webpage' do
    expect(described_class.tool_metadata[:name]).to eq(:read_webpage)
  end

  describe 'HTML to text' do
    let(:html) do
      <<~HTML
        <html><head><title>Hi &amp; Bye</title><style>p{color:red}</style></head>
        <body><script>evil()</script><h1>Header</h1><p>Para one.</p><p>Two &lt;b&gt;.</p></body></html>
      HTML
    end

    it 'strips head, script, and style and decodes entities' do
      text = tool.send(:html_to_text, html)
      expect(text).to include('Header', 'Para one.', 'Two <b>.')
      expect(text).not_to include('evil()', 'color:red', 'Hi & Bye')
    end

    it 'extracts and decodes the title from the raw HTML' do
      expect(tool.send(:extract_title, html)).to eq('Hi & Bye')
    end
  end

  describe 'fetching' do
    it 'returns title and readable text' do
      stub_request(:get, 'http://8.8.8.8/page')
        .to_return(status: 200, body: '<html><head><title>T</title></head><body><p>Body text.</p></body></html>')
      result = tool.execute({ url: 'http://8.8.8.8/page' }, nil)
      expect(result[:status]).to eq(:success)
      expect(result[:result][:title]).to eq('T')
      expect(result[:result][:text]).to include('Body text.')
      expect(result[:result][:truncated]).to be(false)
    end

    it 'truncates to max_chars' do
      stub_request(:get, 'http://8.8.8.8/long').to_return(status: 200, body: "<p>#{'x' * 100}</p>")
      result = tool.execute({ url: 'http://8.8.8.8/long', max_chars: 10 }, nil)
      expect(result[:result][:text].length).to eq(10)
      expect(result[:result][:truncated]).to be(true)
    end

    it 'returns an error for a restricted address' do
      result = tool.execute({ url: 'http://10.0.0.1/internal' }, nil)
      expect(result[:status]).to eq(:error)
    end

    it 'returns an error for a failed fetch' do
      stub_request(:get, 'http://8.8.8.8/gone').to_return(status: 500, body: 'err')
      result = tool.execute({ url: 'http://8.8.8.8/gone' }, nil)
      expect(result[:status]).to eq(:error)
    end
  end
end
