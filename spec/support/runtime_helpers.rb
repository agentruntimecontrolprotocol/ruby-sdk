# frozen_string_literal: true

module RuntimeHelpers
  def build_runtime(agents: {}, heartbeat_interval_sec: nil, tokens: { 'demo' => 'alice' }, **kw)
    tokens_map = tokens.transform_values { |id| Arcp::Auth::Principal.new(id: id, name: id, scopes: [].freeze) }
    runtime = Arcp::Runtime::Runtime.new(
      auth_verifier: Arcp::Auth::Bearer.new(tokens: tokens_map),
      heartbeat_interval_sec: heartbeat_interval_sec,
      **kw
    )
    agents.each do |name, handler|
      runtime.register_agent(name: name.to_s, versions: ['1.0.0'], default: '1.0.0', handler: handler)
    end
    runtime
  end

  def open_pair(runtime, auth: { 'token' => 'demo' }, client_name: 'spec', clock: Arcp::SystemClock.new)
    server_t, client_t = Arcp::Transport::MemoryTransport.pair
    server_task = Async { runtime.accept(server_t) }
    client = Arcp::Client.open(transport: client_t, auth: auth, client_name: client_name, clock: clock)
    [client, server_task]
  end
end

module SyncExample
  def run_sync(&)
    Sync(&)
  end
end

RSpec.configure do |c|
  c.include RuntimeHelpers, type: :integration
  c.include SyncExample, type: :integration
end
