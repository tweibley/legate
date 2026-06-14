# File: lib/legate/tools/read_webpage_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require_relative 'base/http_client'
require_relative 'base/safe_url'

module Legate
  module Tools
    # Fetches a web page and returns its readable text content with markup removed.
    #
    # This is the backbone of research/RAG agents: give it a URL and it returns
    # the page title and plain text (script/style stripped, entities decoded,
    # whitespace collapsed), capped to a sane size. SSRF-safe via {Base::SafeUrl}.
    class ReadWebpage < Legate::Tool
      include Legate::Tools::Base::HttpClient

      DEFAULT_MAX_CHARS = 20_000
      HARD_MAX_CHARS = 200_000
      ENTITIES = { '&amp;' => '&', '&lt;' => '<', '&gt;' => '>', '&quot;' => '"',
                   '&#39;' => "'", '&apos;' => "'", '&nbsp;' => ' ' }.freeze

      tool_name # inferred: :read_webpage
      tool_description 'Fetches a web page and returns its readable text content (HTML markup removed) and title. ' \
                       'Use this to read articles or documentation. Blocks private/loopback addresses (SSRF-safe).'

      parameter :url, type: :string, required: true,
                      description: 'The URL of the page to read (http or https).'
      parameter :max_chars, type: :integer, required: false,
                            description: "Maximum characters of text to return (default #{DEFAULT_MAX_CHARS})."

      def initialize(**options)
        super(**options)
        setup_http_client(base_url: 'https://placeholder.invalid')
      end

      private

      def perform_execution(params, _context)
        url = params.fetch(:url)
        limit = (params[:max_chars] || DEFAULT_MAX_CHARS).to_i.clamp(1, HARD_MAX_CHARS)

        uri, pinned_ip = Legate::Tools::Base::SafeUrl.resolve!(url)
        response = make_request(
          :get, url,
          headers: { 'Accept' => 'text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.8' },
          options: { resolved_ip: pinned_ip, original_host: uri.host }
        )

        html = response.body.to_s
        text = html_to_text(html)
        truncated = text.length > limit
        {
          status: :success,
          result: {
            url: url,
            title: extract_title(html),
            text: truncated ? text[0, limit] : text,
            truncated: truncated
          }
        }
      rescue Legate::ToolError => e
        { status: :error, error_message: e.message }
      end

      def extract_title(html)
        match = html.match(%r{<title[^>]*>(.*?)</title>}im)
        match ? decode_entities(match[1].strip) : nil
      end

      # Best-effort HTML → plain text without a parser dependency: drop
      # script/style/comments, turn block boundaries into newlines, strip the
      # remaining tags, decode common entities, and collapse whitespace.
      def html_to_text(html)
        text = html.dup
        text.gsub!(%r{<head[^>]*>.*?</head>}im, ' ')
        text.gsub!(%r{<(script|style)[^>]*>.*?</\1>}im, ' ')
        text.gsub!(/<!--.*?-->/m, ' ')
        text.gsub!(%r{</?(p|div|br|li|tr|h[1-6]|section|article|header|footer)[^>]*>}i, "\n")
        text.gsub!(/<[^>]+>/, ' ')
        text = decode_entities(text)
        text.gsub(/[ \t]+/, ' ').gsub(/ *\n */, "\n").gsub(/\n{3,}/, "\n\n").strip
      end

      def decode_entities(str)
        str = str.gsub(/&#(\d+);/) { [Regexp.last_match(1).to_i].pack('U') }
        ENTITIES.each { |entity, char| str = str.gsub(entity, char) }
        str
      end
    end
  end
end
