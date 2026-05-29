# frozen_string_literal: true

require 'bundler/gem_tasks'

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
  RSpec::Core::RakeTask.new(:conformance) do |t|
    t.pattern = 'spec/conformance/**/*_spec.rb'
  end
rescue LoadError
  # rspec not yet available
end

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new(:rubocop)
rescue LoadError
  # rubocop not yet available
end

desc 'Render docs/diagrams/*.dot to .svg'
task :diagrams do
  sh 'bin/render-diagrams.sh'
end

namespace :docs do
  desc 'Generate Markdown API reference into docs/api/'
  task :api do
    sh 'ruby scripts/gen-api-docs.rb'
  end
end

desc 'Alias for docs:api'
task docs: 'docs:api'

task default: %i[spec rubocop]
