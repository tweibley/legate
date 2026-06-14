# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require_relative 'lib/legate/web/sass_compiler'

RSpec::Core::RakeTask.new(:spec)

desc 'Compile Sass files'
task :sass do
  Legate::Web::SassCompiler.compile_all
end

desc 'Run tests and compile Sass'
task default: %i[spec sass]

desc 'Run RuboCop'
task :rubocop do
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new
end

desc 'Generate YARD documentation'
task :yard do
  require 'yard'
  YARD::Rake::YARDTask.new do |t|
    t.files = ['lib/**/*.rb']
    t.options = ['--output-dir', 'doc']
  end
end

desc 'Setup development environment'
task :setup do
  sh 'bundle install'
  sh 'bundle exec rake spec'
  sh 'bundle exec rake rubocop'
  sh 'bundle exec rake yard'
end
