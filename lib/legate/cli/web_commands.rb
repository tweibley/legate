# frozen_string_literal: true

require 'rack' # Required for Rack::Builder
require 'rack/handler/puma' # Use Rack::Handler for Rack 2.x compatibility
require_relative '../web' # Loads the web UI (and core, if not already loaded)
require_relative 'base_command'
# Webhook listener required conditionally below

module Legate
  module CLI
    # CLI commands for web interface
    class WebCommands < BaseCommand
      # Conventional directories to scan for custom tools and agents
      TOOL_DIRECTORIES = [
        'lib/tools',
        'agents/lib/tools',
        'tools'
      ].freeze

      AGENT_DIRECTORIES = [
        'lib/agents',
        'agents/lib/agents',
        'agents'
      ].freeze

      # Optional initializer file that runs before auto-loading
      INIT_FILES = [
        'legate_init.rb',
        'config/legate_init.rb',
        'agents/legate_init.rb'
      ].freeze

      desc 'start', 'Start the web interface'
      method_option :port, type: :numeric, default: 4567, desc: 'Port to listen on'
      method_option :host, type: :string, default: 'localhost', desc: 'Host to bind to'
      method_option :no_autoload, type: :boolean, default: false, desc: 'Disable auto-loading of custom tools and agents'
      def start
        # Auto-load custom tools and agents unless disabled
        unless options[:no_autoload]
          load_custom_initializer
          load_custom_tools
          load_custom_agents
        end

        # Access config early
        webhook_config = Legate.config.webhooks
        listener_enabled = webhook_config.listener_enabled
        listener_base_path = webhook_config.base_path

        # Build the Rack application stack
        app = Rack::Builder.new do
          # Conditionally mount the Webhook Listener
          if listener_enabled
            Legate.logger.info "Webhook listener enabled, mounting at #{listener_base_path}"
            begin
              require_relative '../web/webhook_listener'
              map listener_base_path do
                run Legate::Web::WebhookListener.new
              end
            rescue LoadError => e
              Legate.logger.error "Failed to load WebhookListener: #{e.message}. Listener will not be mounted."
            rescue StandardError => e
              Legate.logger.error "Error initializing WebhookListener: #{e.message}. Listener will not be mounted."
            end
          else
            Legate.logger.debug 'Webhook listener is disabled.'
          end

          # Mount the main Legate Web App at the root
          run Legate::Web::App.new
        end.to_app # Convert builder block to a Rack app

        # Start the server using Rack::Handler::Puma (Rack 2.x compatible)
        say "Starting Legate web interface on http://#{options[:host]}:#{options[:port]}"
        Rack::Handler::Puma.run(
          app,
          Host: options[:host],
          Port: options[:port],
          Silent: false
        )
      end

      private

      # Load optional initializer file if present
      def load_custom_initializer
        INIT_FILES.each do |init_file|
          full_path = File.expand_path(init_file, Dir.pwd)
          next unless File.exist?(full_path)

          Legate.logger.info "Loading custom initializer: #{full_path}"
          begin
            require full_path
            Legate.logger.info "Successfully loaded initializer: #{init_file}"
            break # Only load the first one found
          rescue LoadError, StandardError => e
            Legate.logger.error "Error loading initializer #{init_file}: #{e.class} - #{e.message}"
            Legate.logger.debug e.backtrace.first(5).join("\n") if e.backtrace
          end
        end
      end

      # Auto-discover and load custom tools from conventional directories
      def load_custom_tools
        tools_loaded = 0
        base_dir = Dir.pwd

        TOOL_DIRECTORIES.each do |tool_dir|
          full_dir = File.join(base_dir, tool_dir)
          next unless Dir.exist?(full_dir)

          # Find all .rb files in the directory (and subdirectories)
          Dir.glob(File.join(full_dir, '**', '*.rb')).sort.each do |tool_file|
            # Skip files that look like tests or specs
            next if tool_file.include?('_spec.rb') || tool_file.include?('_test.rb')

            begin
              require tool_file
              tools_loaded += 1
              Legate.logger.debug "Loaded custom tool file: #{tool_file}"
            rescue LoadError, StandardError => e
              Legate.logger.warn "Failed to load tool file #{tool_file}: #{e.class} - #{e.message}"
              Legate.logger.debug e.backtrace.first(3).join("\n") if e.backtrace
            end
          end
        end

        return unless tools_loaded.positive?

        Legate.logger.info "Auto-loaded #{tools_loaded} custom tool file(s). " \
                        "Registered tools: #{Legate::GlobalToolManager.registered_tool_names.inspect}"
      end

      # Auto-discover and load custom agent definitions from conventional directories
      def load_custom_agents
        agents_loaded = 0
        base_dir = Dir.pwd

        AGENT_DIRECTORIES.each do |agent_dir|
          full_dir = File.join(base_dir, agent_dir)
          next unless Dir.exist?(full_dir)

          # Find all .rb files in the directory (and subdirectories)
          Dir.glob(File.join(full_dir, '**', '*.rb')).sort.each do |agent_file|
            # Skip files that look like tests, specs, or tools
            next if agent_file.include?('_spec.rb') || agent_file.include?('_test.rb')
            next if agent_file.include?('/tools/') # Don't load tools from agent directories

            begin
              require agent_file
              agents_loaded += 1
              Legate.logger.debug "Loaded custom agent file: #{agent_file}"
            rescue LoadError, StandardError => e
              Legate.logger.warn "Failed to load agent file #{agent_file}: #{e.class} - #{e.message}"
              Legate.logger.debug e.backtrace.first(3).join("\n") if e.backtrace
            end
          end
        end

        return unless agents_loaded.positive?

        registered_agents = begin
          Legate::GlobalDefinitionRegistry.all.keys
        rescue StandardError
          []
        end
        Legate.logger.info "Auto-loaded #{agents_loaded} custom agent file(s). " \
                        "Registered agents: #{registered_agents.inspect}"

        # Sync loaded agents to the definition store so they appear in the Web UI
        sync_agents_to_definition_store
      end

      # Agents auto-loaded from files are already in GlobalDefinitionRegistry,
      # which serves as the definition store. No sync needed.
      def sync_agents_to_definition_store
        # No-op: GlobalDefinitionRegistry is the sole definition store.
        Legate.logger.debug 'Agents are already in GlobalDefinitionRegistry (in-memory definition store).'
      end
    end
  end
end
