# frozen_string_literal: true

require_relative 'lib/legate/version'

Gem::Specification.new do |spec|
  spec.name          = 'legate'
  spec.version       = Legate::VERSION
  spec.authors       = ['Taylor Weibley']
  spec.email         = ['taylor@taylorw.com']

  spec.summary       = 'Legate — AI Agent Framework for Ruby'
  spec.description   = 'A framework for building and managing AI agents in Ruby, with support for tools, planning, sessions, and integrations.'
  spec.homepage      = 'https://github.com/tweibley/legate'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.4.0'

  # homepage_uri is derived from spec.homepage automatically; setting it here too
  # made RubyGems warn about the same URI under multiple keys.
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob('{lib,public,examples}/**/*') + %w[README.md LICENSE bin/legate]
  spec.bindir        = 'bin'
  spec.executables   = ['legate']
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'concurrent-ruby', '~> 1.2'
  spec.add_dependency 'dry-types', '~> 1.7'
  spec.add_dependency 'excon', '~> 0.104'
  spec.add_dependency 'fast-mcp', '~> 1.1'
  spec.add_dependency 'logger', '~> 1.5'
  # ostruct leaves Ruby's default gems in 3.5; Rack 2.2 still requires it, which
  # prints a deprecation warning on boot. Declare it explicitly to silence that
  # until the Rack 3 / Sinatra 4 upgrade.
  spec.add_dependency 'ostruct', '~> 0.6'
  # base64 is required directly (auth encryption + service-account schemes) and
  # leaves Ruby's default gems in 3.5; declare it so it's guaranteed present.
  spec.add_dependency 'base64', '~> 0.2'
  spec.add_dependency 'rackup', '~> 2.2'
  spec.add_dependency 'thor', '~> 1.2'

  # Web UI dependencies
  spec.add_dependency 'faraday', '~> 2.0'
  spec.add_dependency 'faraday-net_http', '~> 3.0'
  spec.add_dependency 'gemini-ai', '~> 4.2.0'
  spec.add_dependency 'jwt', '~> 2.7'
  spec.add_dependency 'kramdown', '~> 2.4'
  spec.add_dependency 'kramdown-parser-gfm', '~> 1.1'
  spec.add_dependency 'oauth2', '~> 2.0'
  spec.add_dependency 'puma', '~> 7.2'
  spec.add_dependency 'sass-embedded', '~> 1.72'
  spec.add_dependency 'sinatra', '~> 4.1'
  spec.add_dependency 'sinatra-contrib', '~> 4.1'
  spec.add_dependency 'slim', '~> 5.1'

  # CLI
  spec.add_dependency 'cli-ui', '~> 2.2'

  # Optional: only needed for Legate::Auth::Encryption (opt-in credential
  # encryption via LEGATE_AUTH_ENCRYPTION_KEY). rbnacl is an FFI binding that
  # needs libsodium on the host, so it is not forced on every install — the
  # module lazy-requires it with a clear error. Add `gem 'rbnacl'` to use it.
  spec.add_development_dependency 'rbnacl', '~> 7.1'

  # ActiveRecord-backed session store + Rails glue are opt-in (required
  # explicitly via 'legate/session_service/active_record' / 'legate/rails'); the
  # library never loads them by default. Dev-only so the suite can exercise the
  # AR store against an in-memory SQLite database.
  spec.add_development_dependency 'activerecord', '>= 7.0'
  spec.add_development_dependency 'dotenv', '~> 3.1'
  spec.add_development_dependency 'pry', '~> 0.14'
  spec.add_development_dependency 'railties', '>= 7.0' # Railtie + install generator
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'simplecov', '~> 0.21'
  spec.add_development_dependency 'sqlite3', '>= 1.6'
  spec.add_development_dependency 'timecop', '~> 0.9'
  spec.add_development_dependency 'webmock', '~> 3.18'
end
