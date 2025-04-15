# frozen_string_literal: true

require_relative '../web/app'

module ADK
  module CLI
    # CLI commands for web interface
    class WebCommands < Thor
      desc 'start', 'Start the web interface'
      method_option :port, type: :numeric, default: 4567, desc: 'Port to listen on'
      method_option :host, type: :string, default: 'localhost', desc: 'Host to bind to'
      def start
        puts "Starting ADK web interface on http://#{options[:host]}:#{options[:port]}"
        ADK::Web::App.run!(
          host: options[:host],
          port: options[:port]
        )
      end
    end
  end
end 