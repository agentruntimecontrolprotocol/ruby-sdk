# frozen_string_literal: true

require 'bundler/gem_tasks'

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  # rspec not yet available; rake build still works
end

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new(:rubocop)
rescue LoadError
  # rubocop not yet available
end

task default: %i[spec rubocop]
