# File: lib/legate/cli/skaffold_commands.rb
# frozen_string_literal: true

require 'thor'
require_relative 'base_command'
require 'fileutils'

module Legate
  module CLI
    class SkaffoldCommands < BaseCommand
      default_task :generate

      desc 'generate [PROJECT_NAME]', 'Generate a new Legate project structure'
      method_option :dir, type: :string, desc: 'Target directory (defaults to current or project_name)'

      def generate(project_name = nil)
        target_dir = options[:dir] || project_name || '.'
        target_dir = File.expand_path(target_dir)

        say "Skaffolding new Legate project in '#{target_dir}'...", :green

        unless Dir.exist?(target_dir)
          FileUtils.mkdir_p(target_dir)
          say "Created directory: #{target_dir}", :cyan
        end

        # 1. Gemfile
        create_file(File.join(target_dir, 'Gemfile'), <<~GEMFILE)
          source 'https://rubygems.org'

          gem 'legate'
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

          require 'legate'

          # Configure Legate
          Legate.configure do |config|
            # Set your global configuration here
            # config.default_model_name = 'gemini-3.5-flash'
          #{'  '}
            # config.session_service = Legate::SessionService::InMemory.new
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

          # Check for Legate configuration for webhooks
          if Legate.config.respond_to?(:webhooks) && Legate.config.webhooks.listener_enabled
            require 'legate/web/webhook_listener'
            # Mount the webhook listener if enabled
            map Legate.config.webhooks.base_path do
              run Legate::Web::WebhookListener.new
            end
          end

          # Run the Legate Web UI
          require 'legate/web/app'
          run Legate::Web::App.new
        CONFIGRU

        # 3. Agents Directory & Sample Agent
        agents_dir = File.join(target_dir, 'agents')
        FileUtils.mkdir_p(agents_dir)
        create_file(File.join(agents_dir, 'hello_world_agent.rb'), <<~RUBY)
          require 'legate'

          Legate::Agent.define do |a|
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

        # A real, useful starter agent built on the SSRF-safe HTTP tools.
        create_file(File.join(agents_dir, 'research_assistant_agent.rb'), <<~RUBY)
          require 'legate'

          # A research assistant that can look things up on the web and reason about
          # what it finds. It uses Legate's built-in, SSRF-safe HTTP tools — no extra
          # setup required beyond a GOOGLE_API_KEY for the LLM.
          Legate::Agent.define do |a|
            a.name :research_assistant
            a.description "Researches a question by fetching and reading web pages, then summarizes the findings."
            a.instruction <<~INSTRUCTION
              You are a thorough research assistant.

              When given a question or topic:
              1. Use read_webpage to fetch and read relevant pages the user provides
                 or that you can construct URLs for (e.g. documentation or APIs).
              2. Use http_request when you need a raw API response (JSON, status checks).
              3. Use current_time when the answer depends on today's date.

              Always cite the URLs you read, distinguish facts from inference, and say
              clearly when a source could not be reached or did not answer the question.
            INSTRUCTION

            a.use_tool :read_webpage
            a.use_tool :http_request
            a.use_tool :current_time

            # a.model_name 'gemini-1.5-pro'
          end
        RUBY

        # 4. Tools Directory
        tools_dir = File.join(target_dir, 'tools')
        FileUtils.mkdir_p(tools_dir)
        create_file(File.join(tools_dir, '.keep'), '')
        create_file(File.join(tools_dir, 'sample_tool.rb'), <<~RUBY)
          require 'legate/tool'

          class SampleTool < Legate::Tool
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

          Legate::GlobalToolManager.register_tool(SampleTool)
        RUBY

        # 5. .env.example
        create_file(File.join(target_dir, '.env.example'), <<~ENV)
          # Copy this to .env and set your values
          GOOGLE_API_KEY=your_api_key_here
          LEGATE_LOG_LEVEL=INFO
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
          require 'legate'

          # Load agents/tools
          Dir[File.join(__dir__, '..', 'agents', '*.rb')].each { |file| require file }
          Dir[File.join(__dir__, '..', 'tools', '*.rb')].each { |file| require file }

          puts "Legate Console loaded."
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
