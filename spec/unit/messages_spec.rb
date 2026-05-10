# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp::MessageTypeRegistry do
  let(:samples) do
    {
      'session.open' => Arcp::Messages::Session::Open.new(
        auth: { scheme: 'bearer', token: 'tok' },
        client: { kind: 'cli', version: '1.0', fingerprint: 'sha256:x' },
        capabilities: { streaming: true }
      ),
      'session.accepted' => Arcp::Messages::Session::Accepted.new(
        session_id: 'sess_1',
        runtime: { kind: 'arcp-ruby', version: '0.1.0' },
        capabilities: { streaming: true },
        lease: nil
      ),
      'session.rejected' => Arcp::Messages::Session::Rejected.new(
        code: 'UNAUTHENTICATED', message: 'nope', details: nil
      ),
      'session.close' => Arcp::Messages::Session::Close.new(reason: nil, detach: false),
      'ping' => Arcp::Messages::Control::Ping.new(sent_at: nil),
      'pong' => Arcp::Messages::Control::Pong.new(received_at: '2026-05-09T13:00:00Z'),
      'ack' => Arcp::Messages::Control::Ack.new(detail: 'ok'),
      'nack' => Arcp::Messages::Control::Nack.new(code: 'INVALID_ARGUMENT', message: 'bad', details: nil, retryable: false),
      'cancel' => Arcp::Messages::Control::Cancel.new(target: 'job', target_id: 'job_x', reason: 'user', deadline_ms: 5_000),
      'tool.invoke' => Arcp::Messages::Execution::ToolInvoke.new(tool: 'fs.search', arguments: { glob: '*.rb' }),
      'tool.result' => Arcp::Messages::Execution::ToolResult.new(value: { ok: 1 }, result_ref: nil),
      'tool.error' => Arcp::Messages::Execution::ToolError.new(
        code: 'INTERNAL', message: 'boom', retryable: false, details: nil, cause: nil, trace_id: nil
      ),
      'job.progress' => Arcp::Messages::Execution::JobProgress.new(percent: 50, message: 'half', detail: nil),
      'job.heartbeat' => Arcp::Messages::Execution::JobHeartbeat.new(sequence: 3, deadline_ms: 60_000, state: 'running'),
      'stream.open' => Arcp::Messages::Streaming::StreamOpen.new(
        kind: 'text', content_type: 'text/plain', encoding: 'utf-8', sidecar: false
      ),
      'stream.chunk' => Arcp::Messages::Streaming::StreamChunk.new(
        sequence: 1, content: 'hi', data: nil, content_type: nil, sha256: nil, role: nil, redacted: false
      ),
      'human.input.request' => Arcp::Messages::Human::InputRequest.new(
        prompt: 'pick a branch',
        response_schema: { type: 'object' },
        default: { branch: 'main' },
        expires_at: '2026-05-09T14:00:00Z',
        destinations: nil
      ),
      'human.input.response' => Arcp::Messages::Human::InputResponse.new(
        value: { branch: 'feat' }, responded_by: 'me', responded_at: '2026-05-09T13:30:00Z'
      ),
      'permission.request' => Arcp::Messages::Permissions::PermissionRequest.new(
        permission: 'fs.write', resource: 'tmp', operation: 'write',
        reason: 'edit', requested_lease_seconds: 60
      ),
      'lease.granted' => Arcp::Messages::Permissions::LeaseGranted.new(
        lease_id: 'lease_x', permission: 'fs.write', resource: 'tmp',
        operation: 'write', expires_at: '2026-05-09T14:00:00Z'
      ),
      'subscribe' => Arcp::Messages::Subscriptions::Subscribe.new(
        filter: { session_id: ['sess_x'] }, since: nil
      ),
      'subscribe.event' => Arcp::Messages::Subscriptions::SubscribeEvent.new(
        event: { type: 'log', payload: { message: 'hi' } }, sequence: 7
      ),
      'artifact.put' => Arcp::Messages::Artifacts::ArtifactPut.new(
        artifact_id: 'art_x', media_type: 'application/json', size: 4,
        data: 'eyJhIjoxfQ==', sha256: nil, expires_at: nil
      ),
      'artifact.ref' => Arcp::Messages::Artifacts::ArtifactRef.new(
        artifact_id: 'art_x', media_type: 'application/json', size: 4,
        uri: 'arcp://session/sess_x/artifact/art_x', sha256: nil, expires_at: nil, data: nil
      ),
      'log' => Arcp::Messages::Telemetry::Log.new(level: 'info', message: 'hi', attributes: { a: 1 }),
      'metric' => Arcp::Messages::Telemetry::Metric.new(
        name: 'tokens.used', value: 1432, unit: 'tokens', dims: { kind: 'input' }
      ),
      'trace.span' => Arcp::Messages::Telemetry::TraceSpan.new(
        trace_id: 't', span_id: 's', name: 'op', parent_span_id: nil,
        start_time: '2026-05-09T13:00:00Z', end_time: '2026-05-09T13:00:01Z',
        attributes: {}, status: 'ok'
      )
    }
  end

  it 'registers all sample types' do
    samples.each_key do |type|
      expect(described_class.class_for(type)).not_to be_nil, "missing #{type}"
    end
  end

  it 'round-trips every sample envelope' do
    samples.each do |type_name, payload|
      env = Arcp::Envelope.build(type: type_name, payload: payload)
      decoded = Arcp::Json.decode_envelope(Arcp::Json.encode_envelope(env))
      expect(decoded.type).to eq(type_name)
      expect(decoded.payload.class).to eq(payload.class)
      expect(decoded.payload).to eq(payload), "mismatch on #{type_name}"
    end
  end

  it 'raises ParseError when a required field is missing' do
    bad_hash = {
      arcp: '1.0', id: 'msg_1', type: 'tool.invoke',
      timestamp: '2026-05-09T13:00:00Z',
      payload: {}
    }
    expect { Arcp::Json.decode_envelope_hash(bad_hash) }.to raise_error(Arcp::Error::ParseError, /tool/)
  end
end
