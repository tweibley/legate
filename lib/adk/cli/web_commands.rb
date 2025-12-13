# frozen_string_literal: true

require 'rack' # Required for Rack::Builder and Rack::Server
require 'adk' # Load ADK core for config access
require_relative '../web/app'
# Webhook listener required conditionally below

module ADK
  module CLI
    # CLI commands for web interface
    class WebCommands < Thor
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
        'adk_init.rb',
        'config/adk_init.rb',
        'agents/adk_init.rb'
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
        webhook_config = ADK.config.webhooks
        listener_enabled = webhook_config.listener_enabled
        listener_base_path = webhook_config.base_path

        # Build the Rack application stack
        app = Rack::Builder.new do
          # Conditionally mount the Webhook Listener
          if listener_enabled
            ADK.logger.info "Webhook listener enabled, mounting at #{listener_base_path}"
            begin
              require_relative '../web/webhook_listener'
              map listener_base_path do
                run ADK::Web::WebhookListener.new
              end
            rescue LoadError => e
              ADK.logger.error "Failed to load WebhookListener: #{e.message}. Listener will not be mounted."
            rescue StandardError => e
              ADK.logger.error "Error initializing WebhookListener: #{e.message}. Listener will not be mounted."
            end
          else
            ADK.logger.debug 'Webhook listener is disabled.'
          end

          # Mount the main ADK Web App at the root
          run ADK::Web::App.new
        end.to_app # Convert builder block to a Rack app

        # Start the server using Rack::Server
        say "Starting ADK web interface on http://#{options[:host]}:#{options[:port]}"
        Rack::Server.start(
          app: app,
          Host: options[:host],
          Port: options[:port],
          server: 'puma' # Or thin, webrick etc. Puma is common.
        )
      end

      private

      # Load optional initializer file if present
      def load_custom_initializer
        INIT_FILES.each do |init_file|
          full_path = File.expand_path(init_file, Dir.pwd)
          next unless File.exist?(full_path)

          ADK.logger.info "Loading custom initializer: #{full_path}"
          begin
            require full_path
            ADK.logger.info "Successfully loaded initializer: #{init_file}"
            return # Only load the first one found
          rescue LoadError, StandardError => e
            ADK.logger.error "Error loading initializer #{init_file}: #{e.class} - #{e.message}"
            ADK.logger.debug e.backtrace.first(5).join("\n") if e.backtrace
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
              ADK.logger.debug "Loaded custom tool file: #{tool_file}"
            rescue LoadError, StandardError => e
              ADK.logger.warn "Failed to load tool file #{tool_file}: #{e.class} - #{e.message}"
              ADK.logger.debug e.backtrace.first(3).join("\n") if e.backtrace
            end
          end
        end

        if tools_loaded.positive?
          ADK.logger.info "Auto-loaded #{tools_loaded} custom tool file(s). " \
                          "Registered tools: #{ADK::GlobalToolManager.registered_tool_names.inspect}"
        end
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
              ADK.logger.debug "Loaded custom agent file: #{agent_file}"
            rescue LoadError, StandardError => e
              ADK.logger.warn "Failed to load agent file #{agent_file}: #{e.class} - #{e.message}"
              ADK.logger.debug e.backtrace.first(3).join("\n") if e.backtrace
            end
          end
        end

        if agents_loaded.positive?
          registered_agents = ADK::GlobalDefinitionRegistry.all.keys rescue []
          ADK.logger.info "Auto-loaded #{agents_loaded} custom agent file(s). " \
                          "Registered agents: #{registered_agents.inspect}"

          # Sync loaded agents to the definition store so they appear in the Web UI
          sync_agents_to_definition_store
        end
      end

      # Sync agents from GlobalDefinitionRegistry to the persistent definition store
      def sync_agents_to_definition_store
        begin
          require 'redis'
          require_relative '../definition_store'
          
          redis_url = ENV['REDIS_URL'] || 'redis://localhost:6379/0'
          redis_client = Redis.new(url: redis_url)
          definition_store = ADK::DefinitionStore::RedisStore.new(redis_client: redis_client)

          ADK::GlobalDefinitionRegistry.all.each do |name, definition|
            begin
              # Check if agent already exists in store
              existing = definition_store.get_definition(name.to_s) rescue nil
              next if existing # Don't overwrite existing agents

              # Save definition to store using keyword arguments
              definition_store.save_definition(
                name: definition.name.to_s,
                description: definition.description || '',
                instruction: definition.instruction || '',
                model: definition.model_name || 'gemini-2.0-flash',
                tools: definition.tool_names.to_a.map(&:to_s),
                fallback_mode: (definition.fallback_mode || :error).to_s,
                mcp_servers_json: '[]'
              )
              ADK.logger.info "Synced agent '#{name}' to definition store for Web UI"
            rescue StandardError => e
              ADK.logger.warn "Failed to sync agent '#{name}' to store: #{e.message}"
            end
          end
        rescue StandardError => e
          ADK.logger.debug "Could not sync agents to definition store: #{e.message}"
        end
      end
    end
  end
end
