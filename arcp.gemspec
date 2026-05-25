# frozen_string_literal: true

require_relative 'lib/arcp/version'

Gem::Specification.new do |spec|
  spec.name        = 'arcp'
  spec.version     = Arcp::VERSION
  spec.authors     = ['ARCP Authors']
  spec.email       = ['arcp-authors@users.noreply.github.com']

  spec.summary     = 'Reference Ruby implementation of the Agent Runtime Control Protocol (ARCP).'
  spec.description = <<~DESC
    Ruby SDK for ARCP: envelope and message model, fiber-based runtime, client,
    WebSocket / stdio / in-memory transports, in-memory event buffering for
    replay, capability negotiation, leases with budget and expiration, streamed
    results, and OpenTelemetry trace propagation. Built on socketry/async.
  DESC
  spec.homepage    = 'https://github.com/agentruntimecontrolprotocol/ruby-sdk'
  spec.license     = 'Apache-2.0'

  spec.required_ruby_version = '>= 3.3.0'

  spec.metadata['changelog_uri']         = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['source_code_uri']       = "#{spec.homepage}.git"
  spec.metadata['bug_tracker_uri']       = "#{spec.homepage}/issues"
  spec.metadata['github_repo']           = 'ssh://github.com/agentruntimecontrolprotocol/ruby-sdk'

  spec.files = Dir[
    'lib/**/*.rb',
    'lib/**/*.sql',
    'sig/**/*.rbs',
    'README.md',
    'CONFORMANCE.md',
    'CHANGELOG.md',
    'LICENSE'
  ]
  spec.require_paths = ['lib']

  spec.add_dependency 'async', '~> 2.20'
  spec.add_dependency 'async-http', '~> 0.86'
  spec.add_dependency 'async-websocket', '~> 0.30'
  spec.add_dependency 'base64', '~> 0.3'
  spec.add_dependency 'bigdecimal', '>= 3.1', '< 5.0'
  spec.add_dependency 'logger', '~> 1.6'
  spec.add_dependency 'opentelemetry-api', '~> 1.5'
  spec.add_dependency 'sqlite3', '~> 2.0'
end
