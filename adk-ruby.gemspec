# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'adk-ruby'
  spec.version       = '0.1.0'
  spec.authors       = ['Taylor Weibley']
  spec.email         = ['spam@taylorw.com']

  spec.summary       = 'Agent Development Kit for Ruby'
  spec.description   = 'A framework for building and managing AI agents in Ruby'
  spec.homepage      = 'https://github.com/tweibley/adk-ruby'
  spec.license       = 'Apache-2.0'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob('{bin,lib}/**/*') + %w[README.md LICENSE CHANGELOG.md]
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'concurrent-ruby', '~> 1.2'
  spec.add_dependency 'redis', '~> 5.0'
  spec.add_dependency 'thor', '~> 1.2'
  spec.add_dependency 'logger', '~> 1.5'
  spec.add_dependency 'prometheus-client', '~> 2.1'
  
  
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
  

end 