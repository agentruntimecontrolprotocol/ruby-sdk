# frozen_string_literal: true

require_relative 'lib/arcp/version'

Gem::Specification.new do |spec|
  spec.name        = 'arcp'
  spec.version     = Arcp::IMPL_VERSION
  spec.authors     = ['ARCP Authors']
  spec.email       = ['arcp@example.invalid']

  spec.summary     = 'Reference Ruby implementation of the Agent Runtime Control Protocol (ARCP).'
  spec.description = <<~DESC
    A reference Ruby implementation of ARCP v#{Arcp::PROTOCOL_VERSION}: an envelope and
    message model, a fiber-based runtime, a client, WebSocket and stdio transports,
    a SQLite-backed event log, and a CLI. Built on the async gem.
  DESC
  spec.homepage    = 'https://github.com/example/arcp'
  spec.license     = 'Apache-2.0'

  spec.required_ruby_version = '>= 3.4.0'

  spec.metadata['homepage_uri']      = spec.homepage
  spec.metadata['source_code_uri']   = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir[
    'lib/**/*.rb',
    'lib/**/*.sql',
    'sig/**/*.rbs',
    'exe/*',
    'README.md',
    'CONFORMANCE.md',
    'RFC-0001-v2.md'
  ]
  spec.require_paths = ['lib']
  spec.bindir        = 'exe'
  spec.executables   = ['arcp']

  spec.add_dependency 'async', '~> 2.0'
  spec.add_dependency 'async-websocket', '~> 0.30'
  spec.add_dependency 'dry-cli', '~> 1.0'
  spec.add_dependency 'json_schemer', '~> 2.0'
  spec.add_dependency 'jwt', '~> 2.0'
  spec.add_dependency 'logger', '~> 1.6'
  spec.add_dependency 'sqlite3', '~> 2.0'
end
