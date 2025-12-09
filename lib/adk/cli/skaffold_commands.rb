# File: lib/adk/cli/skaffold_commands.rb
# frozen_string_literal: true

require 'thor'
require 'fileutils'

module ADK
  module CLI
    class SkaffoldCommands < Thor
      default_task :generate

      desc 'generate [PROJECT_NAME]', 'Generate a new ADK project structure'
      method_option :dir, type: :string, desc: 'Target directory (defaults to current or project_name)'

      def generate(project_name = nil)
        target_dir = options[:dir] || project_name || '.'
        target_dir = File.expand_path(target_dir)

        say "Skaffolding new ADK project in '#{target_dir}'...", :green

        unless Dir.exist?(target_dir)
          FileUtils.mkdir_p(target_dir)
          say "Created directory: #{target_dir}", :cyan
        end

        # 1. Gemfile
        create_file(File.join(target_dir, 'Gemfile'), <<~GEMFILE)
          source 'https://rubygems.org'

          gem 'adk-ruby'
          gem 'dotenv' # For loading .env files
          gem 'puma'   # App server for the Web UI

          group :test do
            gem 'rspec'
          end
        GEMFILE

        # 2. config.ru
        create_file(File.join(target_dir, 'config.ru'), <<~CONFIGRU)
          # frozen_string_literal: true

          require 'rubygems'
          require 'bundler/setup'

          # Load environment variables early
          require 'dotenv/load' if File.exist?('.env')

          require 'adk'

          # Configure ADK
          ADK.configure do |config|
            # Set your global configuration here
            # config.default_model_name = 'gemini-2.0-flash'
          #{'  '}
            # config.session_service = ADK::SessionService::InMemory.new
            # Or use Redis:
            # config.session_service = ADK::SessionService::Redis.new
          end

          # Helper to recursively require files in specific directories
          def recursive_require(base_dir, sub_dirs)
            sub_dirs.each do |dir|
              full_path = File.join(base_dir, dir)
              next unless Dir.exist?(full_path)

              Dir.glob(File.join(full_path, '**', '*.rb')).sort.each do |file|
                 # Skip tests/specs and tools inside agent directories if loading agents
                 next if file.include?('_spec.rb') || file.include?('_test.rb')
                 next if dir.include?('agents') && file.include?('/tools/')

                 begin
                   require file
                 rescue LoadError => e
                   puts "WARN: Failed to load \#{file}: \#{e.message}"
                 end
              end
            end
          end

          # Load Agents
          recursive_require(__dir__, ['lib/agents', 'agents/lib/agents', 'agents'])

          # Load Tools
          recursive_require(__dir__, ['lib/tools', 'agents/lib/tools', 'tools'])

          # Check for ADK configuration for webhooks
          if ADK.config.respond_to?(:webhooks) && ADK.config.webhooks.listener_enabled
            require 'adk/web/webhook_listener'
            # Mount the webhook listener if enabled
            map ADK.config.webhooks.base_path do
              run ADK::Web::WebhookListener.new
            end
          end

          # Run the ADK Web UI
          require 'adk/web/app'
          run ADK::Web::App.new
        CONFIGRU

        # 3. Agents Directory & Sample Agent
        agents_dir = File.join(target_dir, 'agents')
        FileUtils.mkdir_p(agents_dir)
        create_file(File.join(agents_dir, 'hello_world_agent.rb'), <<~RUBY)
          require 'adk'

          ADK::Agent.define do |a|
            a.name :hello_world
            a.description "A friendly agent that helps you verify your setup."
            a.instruction "You are a helpful assistant. When asked to say hello, you should reply enthusiastically."
          #{'  '}
            # Use built-in tools
            a.use_tool :echo#{' '}
            a.use_tool :sample_tool
          #{'  '}
            # a.model_name 'gemini-1.5-pro'
          end
        RUBY

        # 4. Tools Directory
        tools_dir = File.join(target_dir, 'tools')
        FileUtils.mkdir_p(tools_dir)
        create_file(File.join(tools_dir, '.keep'), '')
        create_file(File.join(tools_dir, 'sample_tool.rb'), <<~RUBY)
          require 'adk/tool'

          class SampleTool < ADK::Tool
            tool_description "Greets a user by name."
          #{'  '}
            parameter :name,#{' '}
                      type: :string,#{' '}
                      description: "The name of the user to greet",#{' '}
                      required: true

            private

            def perform_execution(params, _context)
              name = params[:name] || params['name']
              { status: :success, result: "Hello, \#{name}! This is a custom tool." }
            end
          end

          ADK::GlobalToolManager.register_tool(SampleTool)
        RUBY

        # 5. .env.example
        create_file(File.join(target_dir, '.env.example'), <<~ENV)
          # Copy this to .env and set your values
          GOOGLE_API_KEY=your_api_key_here
          REDIS_URL=redis://localhost:6379
          ADK_LOG_LEVEL=INFO
        ENV

        # 6. bin/console (Optional helper)
        bin_dir = File.join(target_dir, 'bin')
        FileUtils.mkdir_p(bin_dir)
        console_path = File.join(bin_dir, 'console')
        create_file(console_path, <<~RUBY)
          #!/usr/bin/env ruby
          require 'bundler/setup'
          require 'irb'
          require 'dotenv/load'
          require 'adk'

          # Load agents/tools
          Dir[File.join(__dir__, '..', 'agents', '*.rb')].each { |file| require file }
          Dir[File.join(__dir__, '..', 'tools', '*.rb')].each { |file| require file }

          puts "ADK Console loaded."
          IRB.start
        RUBY
        FileUtils.chmod(0o755, console_path)

        say "\nSkaffolding complete!", :green
        say 'Next steps:', :yellow
        say "  1. cd #{target_dir}", :cyan
        say '  2. cp .env.example .env (and configure it)', :cyan
        say '  3. bundle install', :cyan
        say '  4. bundle exec rackup (to start the Web UI)', :cyan
      end

      private

      def create_file(path, content)
        if File.exist?(path)
          say "Skipping existing file: #{path}", :yellow
        else
          File.write(path, content)
          say "Created file: #{path}", :green
        end
      end
    end
  end
end
