# frozen_string_literal: true

require 'spec_helper'

# Extra unit coverage targeted at the branches that the integration suite
# does not naturally exercise: tiny serializers (event-body round trips),
# envelope validation, transport edge cases, error payload helpers, and
# trace context inheritance.

RSpec.describe 'Event body decoders' do
  it 'Metric round-trips with and without a unit' do
    bare = Arcp::Job::EventBody::Metric.from_h('name' => 'lat', 'value' => 1)
    expect(bare.to_h).to eq({ 'name' => 'lat', 'value' => 1 })
    with_unit = Arcp::Job::EventBody::Metric.from_h('name' => 'lat', 'value' => 1, 'unit' => 'ms')
    expect(with_unit.to_h['unit']).to eq('ms')
  end

  it 'Log round-trips with and without fields' do
    bare = Arcp::Job::EventBody::Log.from_h('level' => 'info', 'message' => 'm')
    expect(bare.to_h).to eq({ 'level' => 'info', 'message' => 'm' })
    payload = Arcp::Job::EventBody::Log.from_h(
      'level' => 'info', 'message' => 'm', 'fields' => { 'a' => 1 }
    ).to_h
    expect(payload['fields']).to eq({ 'a' => 1 })
  end

  it 'Delegate round-trips with and without a lease' do
    bare = Arcp::Job::EventBody::Delegate.from_h('child_job_id' => 'job_c', 'agent' => 'a@1')
    expect(bare.to_h.key?('lease')).to be(false)
    leased = Arcp::Job::EventBody::Delegate.from_h(
      'child_job_id' => 'job_c', 'agent' => 'a@1',
      'lease' => {
        'id' => 'lse_1', 'capabilities' => ['fs.read'],
        'issued_at' => '2026-01-01T00:00:00Z'
      }
    )
    expect(leased.to_h['lease']['id']).to eq('lse_1')
  end

  it 'ToolResult ok? reflects presence of error and serializes accordingly' do
    r = Arcp::Job::EventBody::ToolResult.from_h('call_id' => 'c', 'result' => { 'x' => 1 })
    expect(r.ok?).to be(true)
    expect(r.to_h.key?('error')).to be(false)
    e = Arcp::Job::EventBody::ToolResult.from_h('call_id' => 'c', 'error' => 'boom')
    expect(e.ok?).to be(false)
    expect(e.to_h.key?('result')).to be(false)
  end

  it 'TraceSpan round-trips with and without optional fields' do
    bare = Arcp::Job::EventBody::TraceSpan.from_h('span_id' => 's', 'name' => 'n')
    expect(bare.to_h).to eq({ 'span_id' => 's', 'name' => 'n' })
    full = Arcp::Job::EventBody::TraceSpan.from_h(
      'span_id' => 's', 'name' => 'n', 'parent_span_id' => 'p',
      'start_at' => 't1', 'end_at' => 't2', 'attributes' => { 'k' => 'v' }
    )
    h = full.to_h
    expect(h['parent_span_id']).to eq('p')
    expect(h['attributes']).to eq({ 'k' => 'v' })
  end

  it 'Status round-trips with and without optional fields' do
    bare = Arcp::Job::EventBody::Status.from_h('phase' => 'starting')
    expect(bare.to_h).to eq({ 'phase' => 'starting' })
    full = Arcp::Job::EventBody::Status.from_h(
      'phase' => 'starting', 'message' => 'go', 'fields' => { 'k' => 'v' }
    )
    expect(full.to_h['message']).to eq('go')
  end

  it 'Progress round-trips with all optional fields' do
    full = Arcp::Job::EventBody::Progress.from_h(
      'current' => 5, 'total' => 10, 'units' => 'rows', 'message' => 'half'
    )
    h = full.to_h
    expect(h['total']).to eq(10)
    expect(h['units']).to eq('rows')
  end
end

RSpec.describe 'Job request shapes' do
  it 'Cancel round-trips with and without a reason' do
    expect(Arcp::Job::Cancel.from_h('job_id' => 'j').to_h).to eq({ 'job_id' => 'j' })
    expect(Arcp::Job::Cancel.from_h('job_id' => 'j', 'reason' => 'x').to_h['reason']).to eq('x')
  end

  it 'Subscribe round-trips with and without from_event_seq' do
    bare = Arcp::Job::Subscribe.from_h('job_id' => 'j')
    expect(bare.history).to be(false)
    full = Arcp::Job::Subscribe.from_h('job_id' => 'j', 'from_event_seq' => 3, 'history' => true)
    expect(full.to_h['from_event_seq']).to eq(3)
  end

  it 'Summary round-trips with and without lease and budget' do
    bare = Arcp::Job::Summary.from_h(
      'job_id' => 'j', 'agent' => 'a@1', 'status' => 'pending', 'created_at' => 't'
    )
    expect(bare.to_h).not_to include('lease_expires_at')
    full = Arcp::Job::Summary.from_h(
      'job_id' => 'j', 'agent' => 'a@1', 'status' => 'pending', 'created_at' => 't',
      'lease_expires_at' => 'x', 'budget_remaining' => { 'USD' => '1.0' }
    )
    expect(full.to_h['budget_remaining']).to eq({ 'USD' => '1.0' })
  end
end

RSpec.describe Arcp::Error do
  it 'to_payload includes details when present and omits otherwise' do
    base = Arcp::Errors::InvalidRequest.new('bad', details: { 'k' => 'v' })
    expect(base.to_payload).to include(:details, :code, :message)
    bare = Arcp::Errors::InvalidRequest.new('bare')
    expect(bare.to_payload.key?(:details)).to be(false)
  end

  it 'to_payload includes trace_id when supplied' do
    err = Arcp::Errors::InvalidRequest.new('bad')
    expect(err.to_payload(trace_id: 'tid')).to include(trace_id: 'tid')
  end

  it 'Errors.for falls back to Internal for unknown codes' do
    expect(Arcp::Errors.for('NOT_A_CODE')).to be_a(Arcp::Errors::Internal)
  end

  it 'classifies retryable and non-retryable codes' do
    expect(Arcp::Errors::RETRYABLE_BY_DEFAULT).to include('AGENT_NOT_AVAILABLE')
    expect(Arcp::Errors::NON_RETRYABLE_BY_DEFAULT).to include('PERMISSION_DENIED')
  end
end

RSpec.describe Arcp::Trace do
  it 'returns a default Context when nothing is set' do
    ctx = described_class.current
    expect(ctx.trace_id).to be_nil
  end

  it 'with(...) inherits trace_id and merges attributes' do
    described_class.with(trace_id: 'a' * 32, attributes: { 'k' => 'v' }) do
      inner = described_class.current
      expect(inner.attributes).to include('k' => 'v')
      expect(inner.trace_id).to eq('a' * 32)
    end
    expect(described_class.current.trace_id).to be_nil
  end

  it 'in_span runs the supplied block and yields a span value' do
    seen = nil
    described_class.in_span('op', attributes: { 'a' => 1 }) do |c|
      seen = c
    end
    expect(seen).not_to be_nil
  end
end

RSpec.describe Arcp::Session::Welcome do
  it 'omits the agent inventory when absent' do
    payload = {
      'runtime_name' => 'r', 'runtime_version' => '1.0',
      'capabilities' => { 'features' => ['heartbeat'], 'encodings' => ['utf8'] },
      'heartbeat_interval_sec' => 30,
      'resume_token' => 'tok', 'resume_window_sec' => 300
    }
    w = described_class.from_h(payload)
    expect(w.capabilities.agents).to be_nil
  end

  it 'parses the agent inventory when present' do
    payload = {
      'runtime_name' => 'r', 'runtime_version' => '1.0',
      'capabilities' => {
        'features' => ['heartbeat'], 'encodings' => ['utf8'],
        'agents' => [{ 'name' => 'a', 'versions' => ['1.0.0'], 'default' => '1.0.0' }]
      },
      'heartbeat_interval_sec' => nil, 'resume_token' => nil, 'resume_window_sec' => 300
    }
    w = described_class.from_h(payload)
    expect(w.capabilities.agents.entries.first.name).to eq('a')
  end
end

RSpec.describe Arcp::Transport::MemoryTransport do
  it 'pairs two transports and round-trips an envelope' do
    a, b = described_class.pair
    env = Arcp::Envelope.build(type: 'session.ping', session_id: 's', payload: {})
    a.send(env)
    received = b.receive
    expect(received.type).to eq('session.ping')
  end

  it 'closes are idempotent' do
    a, _b = described_class.pair
    a.close
    expect(a.closed?).to be(true)
    a.close
    expect(a.closed?).to be(true)
  end

  it 'receive returns nil after the queue drains post-close' do
    a, b = described_class.pair
    a.close
    expect(b.receive).to be_nil
  end

  it 'send on a closed transport raises IOError' do
    a, _b = described_class.pair
    a.close
    expect { a.send(Arcp::Envelope.build(type: 'x', session_id: 's', payload: {})) }
      .to raise_error(IOError)
  end
end

RSpec.describe Arcp::Credential do
  it 'redacts the value field' do
    cred = described_class.new(
      id: 'c1', scheme: 'bearer', value: 'sk-secret', endpoint: 'https://x'
    )
    expect(cred.to_redacted_h['value']).to eq('[REDACTED]')
  end

  it 'round-trips through the wire shape including profile and constraints' do
    h = {
      'id' => 'c1', 'scheme' => 'bearer', 'value' => 'sk',
      'endpoint' => 'https://x', 'profile' => 'openai',
      'constraints' => { 'k' => 'v' }
    }
    cred = described_class.from_h(h)
    expect(cred.to_h).to eq(h)
  end

  it 'omits profile and empty constraints from to_h' do
    cred = described_class.new(id: 'c', scheme: 'bearer', value: 'sk', endpoint: 'https://x')
    h = cred.to_h
    expect(h.key?('profile')).to be(false)
    expect(h.key?('constraints')).to be(false)
  end
end

RSpec.describe Arcp::Session::AgentInventory do
  let(:inventory) do
    described_class.from_array([
                                 { 'name' => 'echo', 'versions' => ['1.0.0', '1.1.0'], 'default' => '1.1.0' },
                                 { 'name' => 'bare', 'versions' => [], 'default' => nil }
                               ])
  end

  it 'finds entries and lists names and versions' do
    expect(inventory.find('echo').default).to eq('1.1.0')
    expect(inventory.find('missing')).to be_nil
    expect(inventory.names).to eq(%w[echo bare])
    expect(inventory.default_for('echo')).to eq('1.1.0')
    expect(inventory.versions_for('echo')).to include('1.0.0')
    expect(inventory.versions_for('missing')).to eq([])
  end

  it 'resolves agent refs against the declared versions' do
    expect(inventory.resolve('echo')).to eq('echo@1.1.0')
    expect(inventory.resolve('echo@1.0.0')).to eq('echo@1.0.0')
    expect(inventory.resolve('echo@9.9.9')).to be_nil
    expect(inventory.resolve('bare')).to be_nil
    expect(inventory.resolve('missing@1')).to be_nil
  end
end

RSpec.describe Arcp::Job::AgentRef do
  it 'parses a bare agent name' do
    ref = described_class.parse('echo')
    expect(ref.name).to eq('echo')
    expect(ref.version).to be_nil
    expect(ref.to_s).to eq('echo')
  end

  it 'parses a versioned agent ref' do
    ref = described_class.parse('echo@1.2.3')
    expect(ref.to_s).to eq('echo@1.2.3')
  end

  it 'rejects nil and empty names' do
    expect(described_class.parse(nil)).to be_nil
    expect { described_class.parse('') }.to raise_error(Arcp::Errors::InvalidRequest)
    expect { described_class.parse('@1') }.to raise_error(Arcp::Errors::InvalidRequest)
  end
end

RSpec.describe Arcp::Job::Event do
  it 'falls back to a frozen hash body for unknown kinds' do
    e = described_class.from_h('kind' => 'mystery', 'body' => { 'a' => 1 })
    expect(e.body).to eq({ 'a' => 1 })
    expect(e.known?).to be(false)
    expect(e.body).to be_frozen
  end

  it 'serializes through to_h symmetrically' do
    e = described_class.from_h('kind' => 'log', 'body' => { 'level' => 'info', 'message' => 'm' })
    expect(e.known?).to be(true)
    expect(e.to_h).to include('kind' => 'log')
  end
end

RSpec.describe Arcp::Runtime::CredentialRegistry do
  let(:store) { Arcp::Credentials::InMemoryStore.new }
  let(:provisioner) { Arcp::Credentials::InMemoryProvisioner.new }
  let(:registry) { described_class.new(provisioner: provisioner, store: store) }

  it 'issues credentials and records them in the store' do
    cred = registry.issue_for(
      job_id: 'job_a', lease: nil, agent: 'a@1', principal_id: 'alice'
    ).first
    expect(store.outstanding(job_id: 'job_a')).to eq([cred.id])
  end

  it 'rotate records a new credential id and revokes the old' do
    issued = registry.issue_for(job_id: 'job_b', lease: nil, agent: 'a@1', principal_id: 'p').first
    new_id = registry.rotate(job_id: 'job_b', credential_id: issued.id, new_value: 'sk-new')
    expect(new_id).to match(/_rotated_/)
    expect(store.outstanding(job_id: 'job_b')).to include(new_id)
  end

  it 'revoke_all revokes every credential and forgets them on success' do
    registry.issue_for(job_id: 'job_c', lease: nil, agent: 'a@1', principal_id: 'p')
    revoked_count = registry.revoke_all(job_id: 'job_c')
    expect(revoked_count).to be >= 1
    expect(store.outstanding(job_id: 'job_c')).to be_empty
  end

  it 'reconcile_on_startup! revokes outstanding credentials from the store' do
    store.record(job_id: 'job_d', credential_id: 'left_over_c1')
    expect { registry.reconcile_on_startup! }.not_to raise_error
    expect(store.outstanding(job_id: 'job_d')).to be_empty
  end

  it 'retries a transient revoke failure once' do
    flaky = Class.new do
      attr_reader :calls

      def initialize = (@calls = 0)
      def issue(**_) = []

      def revoke(credential_id:)
        @calls += 1
        raise 'transient' if @calls == 1

        nil
      end
    end.new
    r = described_class.new(provisioner: flaky, store: store)
    store.record(job_id: 'job_e', credential_id: 'c-e')
    count = r.revoke_all(job_id: 'job_e')
    expect(flaky.calls).to eq(2)
    expect(count).to eq(1)
  end
end

RSpec.describe 'Trace.current=' do
  it 'sets a custom trace context for the current fiber' do
    ctx = Arcp::Trace::Context.new(trace_id: 'a' * 32, span_id: 'b' * 16, attributes: { 'k' => 'v' }.freeze)
    Arcp::Trace.current = ctx
    expect(Arcp::Trace.current.trace_id).to eq('a' * 32)
  ensure
    Arcp::Trace.current = nil
  end
end

RSpec.describe Arcp::Job::EventBody::Progress do
  it 'omits all optional fields when not supplied' do
    p = described_class.from_h('current' => 1)
    expect(p.to_h).to eq({ 'current' => 1 })
  end
end

RSpec.describe Arcp::Job::EventBody::ResultChunk do
  it 'serializes a base64 chunk through to_h' do
    body = described_class.new(
      result_id: 'r', chunk_seq: 0, data: 'abcd', encoding: 'base64', more: true
    )
    expect(body.to_h['encoding']).to eq('base64')
  end
end

RSpec.describe Arcp::Envelope do
  it 'rejects payloads of the wrong shape' do
    expect do
      described_class.from_h('arcp' => Arcp::PROTOCOL_VERSION, 'id' => 'i',
                             'type' => 't', 'session_id' => 's', 'payload' => 'no')
    end.to raise_error(Arcp::Errors::InvalidRequest, /payload must be/)
  end

  it 'rejects an envelope that is not a Hash' do
    expect { described_class.from_h([]) }.to raise_error(Arcp::Errors::InvalidRequest, /Hash/)
  end

  it 'rejects an envelope with a non-string type' do
    payload = { 'arcp' => Arcp::PROTOCOL_VERSION, 'id' => 'i', 'type' => 1,
                'session_id' => 's', 'payload' => {} }
    expect { described_class.from_h(payload) }.to raise_error(Arcp::Errors::InvalidRequest, /String/)
  end

  it 'rejects an envelope with a non-string session_id' do
    payload = { 'arcp' => Arcp::PROTOCOL_VERSION, 'id' => 'i', 'type' => 't',
                'session_id' => 1, 'payload' => {} }
    expect { described_class.from_h(payload) }.to raise_error(Arcp::Errors::InvalidRequest, /session_id/)
  end

  it 'known? reports whether the wire type is registered' do
    env = described_class.build(type: 'session.ping', session_id: 's', payload: {})
    expect(env.known?).to be(true)
    other = described_class.build(type: 'something.unknown', session_id: 's', payload: {})
    expect(other.known?).to be(false)
  end
end
