# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_filter '/samples/'
  enable_coverage :line
  minimum_coverage 0
end

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'arcp'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = '.rspec_status'
  config.warnings = true
  config.default_formatter = 'doc' if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed
end
