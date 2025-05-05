# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'adk-ruby'
  spec.version       = '0.5.8'
  spec.authors       = ['Taylor Weibley']
  spec.email         = ['spam@taylorw.com']

  spec.summary       = 'Agent Development Kit for Ruby'
  spec.description   = 'A framework for building and managing AI agents in Ruby'
  spec.homepage      = 'https://github.com/tweibley/adk-ruby'
  spec.license       = 'NODHHLICENSE'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob('{bin,lib,views,public}/**/*') + %w[README.md Gemfile Gemfile.lock]
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'concurrent-ruby', '~> 1.2'
  spec.add_dependency 'redis', '~> 5.0'
  spec.add_dependency 'thor', '~> 1.2'
  spec.add_dependency 'logger', '~> 1.5'
  spec.add_dependency 'prometheus-client', '~> 2.1'
  spec.add_dependency 'sidekiq'
  spec.add_dependency 'activesupport', '>= 5.0'
  spec.add_dependency 'dry-configurable', '~> 1.0'
  #spec.add_dependency 'dry-container', '~> 0.8.0'
  spec.add_dependency 'dry-struct', '~> 1.6'
  spec.add_dependency 'dry-types', '~> 1.7'
  spec.add_dependency 'excon', '~> 0.104'
  spec.add_dependency 'fast-mcp'
  spec.add_dependency 'logging', '~> 2.3'

  # Web UI dependencies
  spec.add_dependency 'sinatra', '~> 3.1'
  spec.add_dependency 'sinatra-contrib', '~> 3.1'
  spec.add_dependency 'puma', '~> 6.4'
  spec.add_dependency 'slim', '~> 5.1'
  spec.add_dependency 'sass-embedded', '~> 1.72'
  spec.add_dependency 'coffee-script', '~> 2.4'
  spec.add_dependency 'gemini-ai','~> 4.2.0'
  spec.add_dependency 'faraday'
  spec.add_dependency 'faraday-net_http'

  #CLI
  spec.add_dependency 'ostruct'
  
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "simplecov", "~> 0.21"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.add_development_dependency "timecop", "~> 0.9"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "dry-schema", "~> 1.13"

  # Prevent pushing this gem to RubyGems.org by default.
  # spec.metadata["allowed_push_host"] = "TODO: Set to your gem server host e.g. https://mygemserver.com"
end 
