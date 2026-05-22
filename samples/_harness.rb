# frozen_string_literal: true

# Shared harness for samples. Wraps the body in `Sync { }`, pairs
# memory transports, exposes a fake clock, and emits one JSON line
# describing the sample's outcomes.

require 'async'
require 'json'
require 'logger'
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'arcp'

module Harness
  module_function

  StderrLogger = Logger.new(
    $stderr, level: Logger::INFO,
             formatter: ->(sev, _, _, msg) { "[#{sev}] #{msg}\n" }
  )

  def run_or_exit(name)
    emitted = false
    yielder = lambda do |asserts|
      raise 'emit called twice' if emitted

      emitted = true
      $stdout.puts JSON.dump({ 'sample' => name, 'ok' => true, 'asserts' => asserts })
    end

    Sync do
      yield yielder
    end
    raise 'sample did not emit' unless emitted

    0
  rescue StandardError => e
    $stdout.puts JSON.dump({
                             'sample' => name, 'ok' => false,
                             'error' => { 'class' => e.class.name, 'message' => e.message }
                           })
    warn e.backtrace.first(8).join("\n")
    1
  end

  def pair_memory
    Arcp::Transport::MemoryTransport.pair
  end

  def with_timeout(seconds, task:)
    timer = task.async do |t|
      t.sleep(seconds)
      task.stop
    end
    begin
      yield timer
    ensure
      timer.stop
    end
  end

  def fake_clock(start: '2026-01-01T00:00:00Z')
    Arcp::FakeClock.new(now: Time.iso8601(start))
  end

  def runtime(agents: {}, auth_tokens: { 'demo' => 'alice' }, heartbeat_interval_sec: nil, clock: nil, **kw)
    tokens = auth_tokens.transform_values do |id|
      Arcp::Auth::Principal.new(id: id, name: id, scopes: [].freeze)
    end
    r = Arcp::Runtime::Runtime.new(
      auth_verifier: Arcp::Auth::Bearer.new(tokens: tokens),
      heartbeat_interval_sec: heartbeat_interval_sec,
      clock: clock || Arcp::SystemClock.new,
      **kw
    )
    agents.each do |name, spec|
      if spec.is_a?(Hash)
        versions = spec[:versions] || ['1.0.0']
        default  = spec[:default] || versions.first
        handler  = spec[:handler]
      else
        versions = ['1.0.0']
        default  = '1.0.0'
        handler  = spec
      end
      r.register_agent(name: name.to_s, versions: versions, default: default, handler: handler)
    end
    r
  end

  def open_client(server_t, client_t, runtime, auth: { 'token' => 'demo' }, **kw)
    task = Async { runtime.accept(server_t) }
    client = Arcp::Client.open(transport: client_t, auth: auth, **kw)
    [client, task]
  end
end
