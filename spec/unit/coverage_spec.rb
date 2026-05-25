# frozen_string_literal: true

require 'spec_helper'
require 'bigdecimal'

# Focused unit coverage for branches that integration tests don't exercise:
# transport error/EOF paths, serializer backend selection, body decoder
# error branches, event log eviction, lease manager edge cases, and the
# resume registry expiry timer.

RSpec.describe Arcp::Serializer do
  before { described_class.instance_variable_set(:@backend, :stdlib) }

  it 'round-trips JSON through the default stdlib backend' do
    blob = described_class.dump({ 'a' => 1 })
    expect(described_class.load(blob)).to eq({ 'a' => 1 })
  end

  it 'returns nil for empty or nil loads' do
    expect(described_class.load(nil)).to be_nil
    expect(described_class.load('')).to be_nil
  end

  it 'raises ArgumentError for unknown backends' do
    expect { described_class.backend = :gibberish }.to raise_error(ArgumentError, /unknown serializer backend/)
  end

  it 'exposes the active backend' do
    expect(described_class.backend).to eq(:stdlib)
  end
end

RSpec.describe Arcp::Transport::StdioTransport do
  let(:input_r) { StringIO.new('') }
  let(:output_w) { StringIO.new(+'') }

  it 'sends an envelope as newline-delimited JSON' do
    envelope = Arcp::Envelope.build(
      type: Arcp::MessageTypes::SESSION_PING,
      session_id: 'ses_x', payload: { 'nonce' => 'n' }
    )
    t = described_class.new(input: input_r, output: output_w)
    t.send(envelope)
    expect(output_w.string).to end_with("\n")
    parsed = JSON.parse(output_w.string.strip)
    expect(parsed['type']).to eq(Arcp::MessageTypes::SESSION_PING)
  end

  it 'returns nil and marks closed at EOF' do
    t = described_class.new(input: StringIO.new(''), output: output_w)
    expect(t.receive).to be_nil
    expect(t.closed?).to be(true)
  end

  it 'refuses to send on a closed transport' do
    t = described_class.new(input: input_r, output: output_w)
    t.close
    expect(t.closed?).to be(true)
    expect { t.send(Arcp::Envelope.build(type: 'session.ping', session_id: 's', payload: {})) }
      .to raise_error(IOError, /closed/)
  end

  it 'is idempotent on close and tolerates already-closed io' do
    output_w.close
    t = described_class.new(input: input_r, output: output_w)
    expect { t.close }.not_to raise_error
    expect { t.close }.not_to raise_error
  end

  it 'decodes a received JSON line into an envelope' do
    env = Arcp::Envelope.build(type: 'session.ping', session_id: 's', payload: {})
    input = StringIO.new("#{Arcp::Serializer.dump(env.to_h)}\n")
    t = described_class.new(input: input, output: output_w)
    decoded = t.receive
    expect(decoded.type).to eq('session.ping')
  end
end

RSpec.describe Arcp::Transport::WebSocketTransport do
  let(:fake_conn) do
    Class.new do
      attr_reader :written

      def initialize(messages: [])
        (@queue = messages.dup
         @written = []
         @closed = false)
      end

      def write(s) = @written << s
      def flush = nil

      def read
        raise EOFError if @closed
        return nil if @queue.empty?

        @queue.shift
      end

      def close = (@closed = true)
    end.new(messages: [Arcp::Serializer.dump(Arcp::Envelope.build(
      type: 'session.ping', session_id: 's', payload: {}
    ).to_h)])
  end

  it 'writes the envelope as JSON and flushes' do
    t = described_class.new(connection: fake_conn)
    env = Arcp::Envelope.build(type: 'session.ping', session_id: 's', payload: {})
    t.send(env)
    expect(fake_conn.written.size).to eq(1)
  end

  it 'returns nil at EOF and marks the transport closed' do
    conn = fake_conn
    conn.close
    t = described_class.new(connection: conn)
    expect(t.receive).to be_nil
    expect(t.closed?).to be(true)
  end

  it 'refuses to send on a closed transport' do
    t = described_class.new(connection: fake_conn)
    t.close
    expect { t.send(Arcp::Envelope.build(type: 'session.ping', session_id: 's', payload: {})) }
      .to raise_error(IOError, /closed/)
  end

  it 'is idempotent on close' do
    t = described_class.new(connection: fake_conn)
    t.close
    expect { t.close }.not_to raise_error
  end
end

RSpec.describe 'EventBody decoder error branches' do
  it 'raises InvalidRequest for unknown result_chunk encodings' do
    expect do
      Arcp::Job::EventBody::ResultChunk.from_h(
        'result_id' => 'r', 'chunk_seq' => 0, 'data' => 'x',
        'encoding' => 'rot13', 'more' => false
      )
    end.to raise_error(Arcp::Errors::InvalidRequest, /unknown encoding/)
  end

  it 'decodes a utf8 chunk' do
    body = Arcp::Job::EventBody::ResultChunk.from_h(
      'result_id' => 'r', 'chunk_seq' => 0, 'data' => 'hi',
      'encoding' => 'utf8', 'more' => false
    )
    expect(body.decoded).to eq('hi')
  end

  it 'decodes a base64 chunk' do
    body = Arcp::Job::EventBody::ResultChunk.from_h(
      'result_id' => 'r', 'chunk_seq' => 1,
      'data' => Base64.strict_encode64('abc'),
      'encoding' => 'base64', 'more' => true
    )
    expect(body.decoded).to eq('abc')
  end
end

RSpec.describe Arcp::Runtime::EventLog do
  let(:clock) { Arcp::FakeClock.new }
  let(:log) { described_class.new(window_sec: 30, clock: clock) }

  def env(seq, job: 'job_a')
    Arcp::Envelope.build(
      type: Arcp::MessageTypes::JOB_EVENT,
      session_id: 'ses_x', job_id: job, event_seq: seq, payload: {}
    )
  end

  it 'evicts envelopes up to a given seq' do
    3.times { |i| log.append('ses_x', env(i + 1)) }
    log.evict_up_to('ses_x', 2)
    expect(log.replay('ses_x').map(&:event_seq)).to eq([3])
    expect(log.floor('ses_x')).to eq(2)
  end

  it 'replays events past a from_event_seq cursor' do
    3.times { |i| log.append('ses_x', env(i + 1)) }
    expect(log.replay('ses_x', from_event_seq: 2).map(&:event_seq)).to eq([2, 3])
  end

  it 'expires entries past the window' do
    log.append('ses_x', env(1))
    clock.advance(31)
    log.expire!
    expect(log.buffer_size('ses_x')).to eq(0)
    expect(log.job_buffer_size('job_a')).to eq(0)
  end

  it 'tracks job-indexed replay independently of the producing session' do
    log.append('ses_producer', env(1, job: 'job_b'))
    log.append('ses_producer', env(2, job: 'job_b'))
    expect(log.replay_job('job_b').map(&:event_seq)).to eq([1, 2])
    expect(log.replay('ses_observer')).to be_empty
  end
end

RSpec.describe Arcp::Runtime::ResumeRegistry do
  let(:clock) { Arcp::FakeClock.new }
  let(:registry) { described_class.new(window_sec: 10, clock: clock) }

  it 'tracks a token and returns the entry on lookup' do
    registry.register(token: 'tok', session_id: 'ses_x', principal_id: 'p1')
    expect(registry.lookup('tok').session_id).to eq('ses_x')
  end

  it 'evicts disconnected entries past the window' do
    registry.register(token: 'tok', session_id: 'ses_x', principal_id: 'p1')
    registry.mark_disconnected('tok', last_processed_seq: 3)
    clock.advance(11)
    expect(registry.lookup('tok')).to be_nil
  end

  it 'leaves connected entries indefinitely' do
    registry.register(token: 'tok', session_id: 'ses_x', principal_id: 'p1')
    clock.advance(120)
    expect(registry.lookup('tok')).not_to be_nil
  end

  it 'mark_reconnected clears the disconnect timer' do
    registry.register(token: 'tok', session_id: 'ses_x', principal_id: 'p1')
    registry.mark_disconnected('tok')
    registry.mark_reconnected('tok')
    clock.advance(120)
    expect(registry.lookup('tok')).not_to be_nil
  end

  it 'forget removes the entry' do
    registry.register(token: 'tok', session_id: 'ses_x', principal_id: 'p1')
    registry.forget('tok')
    expect(registry.lookup('tok')).to be_nil
  end

  it 'expire! drops only disconnected-expired entries' do
    registry.register(token: 'a', session_id: 'sa', principal_id: 'p')
    registry.register(token: 'b', session_id: 'sb', principal_id: 'p')
    registry.mark_disconnected('a')
    clock.advance(11)
    registry.expire!
    expect(registry.lookup('a')).to be_nil
    expect(registry.lookup('b')).not_to be_nil
  end
end

RSpec.describe Arcp::Runtime::LeaseManager do
  let(:clock) { Arcp::FakeClock.new }
  let(:lm) { described_class.new(clock: clock) }

  def lease(currencies: nil, capabilities: ['cost.spend'], expires_at: nil, model_use: nil)
    budget = currencies ? Arcp::Lease::CostBudget.parse(currencies) : nil
    Arcp::Lease::Lease.new(
      id: 'lse_x', capabilities: capabilities, budget: budget,
      model_use: model_use, expires_at: expires_at,
      issued_at: clock.now.iso8601
    )
  end

  it 'returns unlimited spend when no lease is registered' do
    expect(lm.try_spend!('job_unknown', 'USD', BigDecimal('1.00'))).to be(true)
  end

  it 'allows any currency on a lease with no budget' do
    lm.register('job_a', lease)
    expect(lm.try_spend!('job_a', 'XYZ', BigDecimal('99'))).to be(true)
  end

  it 'denies an unlisted currency on a budgeted lease' do
    lm.register('job_b', lease(currencies: ['USD:1.00']))
    expect { lm.try_spend!('job_b', 'EUR', BigDecimal('0.10')) }
      .to raise_error(Arcp::Errors::BudgetExhausted, /not in budget/)
  end

  it 'spends exactly the remaining balance then raises on the next call' do
    lm.register('job_c', lease(currencies: ['USD:0.50']))
    expect(lm.try_spend!('job_c', 'USD', BigDecimal('0.50'))).to be(true)
    expect { lm.try_spend!('job_c', 'USD', BigDecimal('0.01')) }
      .to raise_error(Arcp::Errors::BudgetExhausted, /exhausted/)
  end

  it 'raises LeaseExpired for an expired lease' do
    expired = lease(expires_at: (clock.now - 1).iso8601)
    lm.register('job_d', expired)
    expect { lm.check!('job_d', capability: 'cost.spend') }
      .to raise_error(Arcp::Errors::LeaseExpired)
  end

  it 'raises PermissionDenied when capability is not in the lease' do
    lm.register('job_e', lease(capabilities: ['fs.read']))
    expect { lm.check!('job_e', capability: 'net.fetch') }
      .to raise_error(Arcp::Errors::PermissionDenied)
  end

  it 'is a no-op for jobs without leases' do
    expect { lm.check!('job_none', capability: 'fs.read') }.not_to raise_error
  end

  it 'allows model.use matches and denies misses' do
    lm.register('job_f', lease(model_use: ['gpt-4*']))
    expect(lm.check_model!('job_f', model_id: 'gpt-4-turbo')).to be(true)
    expect { lm.check_model!('job_f', model_id: 'claude-opus') }
      .to raise_error(Arcp::Errors::PermissionDenied)
  end

  it 'exposes the remaining snapshot' do
    lm.register('job_g', lease(currencies: ['USD:2.00']))
    lm.try_spend!('job_g', 'USD', BigDecimal('0.75'))
    expect(lm.remaining('job_g')['USD'].to_s('F')).to eq('1.25')
    expect(lm.remaining('job_missing')).to eq({})
  end
end

RSpec.describe Arcp::Runtime::SubscriptionManager do
  let(:sm) { described_class.new }

  it 'rejects attach by a non-owning principal' do
    sm.register_owner('job_a', 'alice', 'ses_a', Object.new)
    expect { sm.attach('job_a', 'bob', 'ses_b', Object.new) }
      .to raise_error(Arcp::Errors::PermissionDenied)
  end

  it 'detaches a subscriber and stops receiving fanout' do
    a_q = []
    b_q = []
    sm.register_owner('job_a', 'alice', 'ses_a',
                      Object.new.tap { |o| o.define_singleton_method(:enqueue) { |e| a_q << e } })
    sm.attach('job_a', 'alice', 'ses_b',
              Object.new.tap { |o| o.define_singleton_method(:enqueue) { |e| b_q << e } })

    env = Arcp::Envelope.build(type: 'job.event', session_id: 's', job_id: 'job_a', event_seq: 1, payload: {})
    sm.fanout('job_a', env)
    expect(a_q.size).to eq(1)
    expect(b_q.size).to eq(1)

    sm.detach('job_a', 'ses_b')
    sm.fanout('job_a', env)
    expect(b_q.size).to eq(1)
  end

  it 'reports the owner principal' do
    sm.register_owner('job_a', 'alice', 'ses_a', Object.new)
    expect(sm.owner_of('job_a')).to eq('alice')
  end

  it 'rebinds a session id to a new outbox across jobs' do
    old_q = []
    new_q = []
    old_outbox = Object.new.tap { |o| o.define_singleton_method(:enqueue) { |e| old_q << e } }
    new_outbox = Object.new.tap { |o| o.define_singleton_method(:enqueue) { |e| new_q << e } }

    sm.register_owner('job_a', 'alice', 'ses_a', old_outbox)
    sm.rebind_session('ses_a', new_outbox)

    env = Arcp::Envelope.build(type: 'job.event', session_id: 's', job_id: 'job_a', event_seq: 1, payload: {})
    sm.fanout('job_a', env)
    expect(new_q.size).to eq(1)
    expect(old_q).to be_empty
  end
end

RSpec.describe Arcp::Auth::Bearer do
  let(:principal) { Arcp::Auth::Principal.new(id: 'alice', name: 'alice', scopes: [].freeze) }

  it 'returns nil for missing tokens' do
    expect(described_class.new(tokens: {}).verify(nil)).to be_nil
    expect(described_class.new(tokens: {}).verify('unknown')).to be_nil
  end

  it 'accepts a Principal value' do
    verifier = described_class.new(tokens: { 'tok' => principal })
    expect(verifier.verify('tok').id).to eq('alice')
  end

  it 'accepts a String shorthand' do
    verifier = described_class.new(tokens: { 'tok' => 'alice' })
    expect(verifier.verify('tok').id).to eq('alice')
  end

  it 'accepts a Hash shape' do
    verifier = described_class.new(tokens: { 'tok' => { 'id' => 'alice', 'name' => 'A', 'scopes' => ['x'] } })
    p = verifier.verify('tok')
    expect(p.id).to eq('alice')
    expect(p.scopes).to eq(['x'])
  end

  it 'from_token builds a single-token verifier' do
    verifier = described_class.from_token('tok', principal_id: 'a')
    expect(verifier.verify('tok').id).to eq('a')
  end
end

RSpec.describe Arcp::Credentials do
  it 'translates a budget-exhausted upstream error' do
    upstream = Class.new(StandardError) do
      define_method(:code) { 'budget_exhausted' }
    end.new('upstream said no')
    translated = described_class.translate_upstream_error(upstream)
    expect(translated).to be_a(Arcp::Errors::BudgetExhausted)
  end

  it 'translates a 402-status upstream error' do
    upstream = Class.new(StandardError) do
      define_method(:status) { 402 }
    end.new('payment')
    translated = described_class.translate_upstream_error(upstream)
    expect(translated).to be_a(Arcp::Errors::BudgetExhausted)
  end

  it 'passes other errors through unchanged' do
    err = StandardError.new('other')
    expect(described_class.translate_upstream_error(err)).to be(err)
  end

  it 'InMemoryProvisioner issues and revokes credentials' do
    p = described_class::InMemoryProvisioner.new
    cred = p.issue(lease: nil, job_id: 'job_a', agent: 'echo@1', principal_id: 'alice').first
    expect(cred.id).to eq('cred_job_a_0')
    p.revoke(credential_id: cred.id)
    expect(p.revoked).to eq([cred.id])
  end

  it 'InMemoryStore records, lists, and forgets credential ids' do
    s = described_class::InMemoryStore.new
    s.record(job_id: 'job_a', credential_id: 'c1')
    s.record(job_id: 'job_a', credential_id: 'c1') # dedupe
    s.record(job_id: 'job_a', credential_id: 'c2')
    expect(s.outstanding(job_id: 'job_a').sort).to eq(%w[c1 c2])
    s.forget(job_id: 'job_a', credential_id: 'c1')
    expect(s.outstanding(job_id: 'job_a')).to eq(['c2'])
    s.forget(job_id: 'job_a', credential_id: 'c2')
    expect(s.all_outstanding).to be_empty
  end
end

RSpec.describe Arcp::Lease::LeaseConstraints do
  it 'rejects malformed max_budget values' do
    expect { described_class.new(max_budget: 42) }
      .to raise_error(Arcp::Errors::InvalidRequest, /max_budget/)
  end

  it 'accepts CostBudget directly' do
    cb = Arcp::Lease::CostBudget.parse(['USD:1.00'])
    c = described_class.new(max_budget: cb)
    expect(c.max_budget).to eq(cb)
  end

  it 'accepts an array of "CCY:amount" entries' do
    c = described_class.new(max_budget: ['USD:1.00'])
    expect(c.max_budget.remaining('USD').to_s('F')).to eq('1.0')
  end

  it 'enforce_max_budget! is a no-op when max_budget is nil' do
    expect { described_class.new.enforce_max_budget!(Arcp::Lease::CostBudget.parse(['USD:50.00'])) }
      .not_to raise_error
  end

  it 'enforce_max_budget! is a no-op when requested is nil' do
    expect { described_class.new(max_budget: ['USD:1.00']).enforce_max_budget!(nil) }.not_to raise_error
  end

  it 'rejects currencies not declared in max_budget' do
    c = described_class.new(max_budget: ['USD:1.00'])
    expect { c.enforce_max_budget!(Arcp::Lease::CostBudget.parse(['EUR:0.10'])) }
      .to raise_error(Arcp::Errors::LeaseSubsetViolation)
  end

  it 'validates UTC expires_at' do
    expect { described_class.new(expires_at: '2026-01-01T00:00:00+02:00').validate! }
      .to raise_error(Arcp::Errors::InvalidRequest, /must be UTC/)
  end
end

RSpec.describe 'JobContext#stream_result writer totals (#29)' do
  let(:sink) do
    Class.new do
      attr_reader :events, :result, :error

      def initialize
        (@events = []
         @result = nil
         @error = nil)
      end

      def runtime = nil

      def publish_event(_jid, event)
        @events << event
        @events.size
      end

      def publish_result(_jid, result) = (@result = result)
      def publish_error(_jid, err) = (@error = err)
    end.new
  end

  it 'records totals when the writer is closed before finish (non-block path)' do
    ctx = Arcp::Runtime::JobContext.new(job_id: 'job_a', agent: 'a@1', input: nil, lease: nil, sink: sink)
    writer = ctx.stream_result(encoding: 'utf8')
    writer.write('hello ', more: true)
    writer.write('world', more: false)
    writer.close
    ctx.finish

    expect(sink.result.chunked?).to be(true)
    expect(sink.result.result_size).to eq('hello world'.bytesize)
    expect(sink.events.size).to eq(2)
  end

  it 'is idempotent on double close' do
    ctx = Arcp::Runtime::JobContext.new(job_id: 'job_b', agent: 'a@1', input: nil, lease: nil, sink: sink)
    writer = ctx.stream_result
    writer.write('x', more: false)
    writer.close
    expect { writer.close }.not_to raise_error
  end

  it 'rejects inline result mixed with chunk stream' do
    ctx = Arcp::Runtime::JobContext.new(job_id: 'job_c', agent: 'a@1', input: nil, lease: nil, sink: sink)
    writer = ctx.stream_result
    writer.write('x', more: false)
    writer.close
    expect { ctx.finish(result: 'inline') }
      .to raise_error(Arcp::Errors::ProtocolViolation, /cannot mix/)
  end
end

RSpec.describe Arcp::Runtime::JobManager do
  let(:runtime) do
    Arcp::Runtime::Runtime.new(
      auth_verifier: Arcp::Auth::Bearer.from_token('tok', principal_id: 'alice'),
      heartbeat_interval_sec: nil
    )
  end
  let(:jm) { runtime.job_manager }

  it 'raises AgentNotAvailable for an unregistered agent' do
    expect { jm.resolve_agent('missing') }.to raise_error(Arcp::Errors::AgentNotAvailable)
  end

  it 'raises AgentVersionNotAvailable for a missing pinned version' do
    jm.register_agent(name: 'a', versions: ['1.0.0'], default: '1.0.0', handler: ->(_) {})
    expect { jm.resolve_agent('a@2.0.0') }.to raise_error(Arcp::Errors::AgentVersionNotAvailable)
  end

  it 'list with an empty cursor walks from the oldest job and respects limit' do
    response = jm.list(principal_id: 'alice', limit: 10)
    expect(response.next_cursor).to be_nil
    expect(response.jobs).to eq([])
  end

  it 'decode_cursor falls back to 0 for malformed strings' do
    # Public-ish behavior probe via send to keep the private helpers covered.
    expect(jm.send(:decode_cursor, 'not-an-int')).to eq(0)
    expect(jm.send(:decode_cursor, '')).to eq(0)
  end
end
