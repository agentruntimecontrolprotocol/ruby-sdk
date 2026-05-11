#!/usr/bin/env ruby
# frozen_string_literal: true

# Sandboxed on-call agent. Lease-gated shell, reasoning streamed.

require 'arcp'
require 'async'

require_relative 'agent' # one-shot generator: thought + tool_call

READ_BINARIES = %w[/usr/bin/journalctl /usr/bin/cat /usr/bin/ss
                   /usr/bin/ps].to_set.freeze
WRITE_BINARIES = %w[/usr/bin/systemctl /usr/bin/kill].to_set.freeze
READ_LEASE_SECONDS = 30 * 60
WRITE_LEASE_SECONDS = 60

# Returns [permission, resource, operation, lease_seconds].
def classify(argv, host)
  binary = argv.first
  if READ_BINARIES.include?(binary)
    ['host.read', "host:#{host}", 'read', READ_LEASE_SECONDS]
  elsif WRITE_BINARIES.include?(binary)
    target = binary == '/usr/bin/systemctl' ? argv[2] : argv[1]
    ['host.write', "host:#{host}/#{binary}/#{target}", 'write', WRITE_LEASE_SECONDS]
  else
    raise Arcp::Error::PermissionDenied, "binary not allowed: #{binary}"
  end
end

def acquire_lease(client, permission:, resource:, operation:, seconds:, reason:)
  request = Arcp::Envelope.build(
    type: 'permission.request',
    payload: Arcp::Messages::Permissions::PermissionRequest.new(
      permission: permission, resource: resource, operation: operation,
      reason: reason, requested_lease_seconds: seconds
    ),
    session_id: client.session_id
  )
  client.send_envelope(request)
  reply = client.receive_envelope
  case reply.payload
  in Arcp::Messages::Permissions::PermissionDeny => d
    raise Arcp::Error::PermissionDenied, (d.reason || 'denied')
  in Arcp::Messages::Permissions::PermissionGrant => g
    g.resource # lease handle is keyed by resource in this sample
  end
end

def run_command(client, argv, reason:, host:)
  permission, resource, operation, seconds = classify(argv, host)
  lease = acquire_lease(
    client, permission: permission, resource: resource,
            operation: operation, seconds: seconds, reason: reason
  )
  # The lease is the only guard. Spawn the subprocess elsewhere.
  "<would run #{argv.inspect} under lease #{lease}>"
end

def emit_thought(client, stream_id:, sequence:, text:)
  env = Arcp::Envelope.build(
    type: 'stream.chunk',
    payload: Arcp::Messages::Streaming::StreamChunk.new(
      sequence: sequence, kind: 'thought',
      role: 'assistant_thought', content: text
    ),
    stream_id: stream_id,
    session_id: client.session_id
  )
  client.send_envelope(env)
end

Sync do
  client = nil # ARCPClient(...) — transport, identity (constrained), auth elided
  client.open

  stream_id = "str_#{Time.now.to_i}"
  open_env = Arcp::Envelope.build(
    type: 'stream.open',
    payload: Arcp::Messages::Streaming::StreamOpen.new(kind: 'thought'),
    stream_id: stream_id,
    session_id: client.session_id
  )
  client.send_envelope(open_env)

  seq = 0
  Agent.llm_loop('api-gateway pod is OOMing every 4 minutes') do |step|
    emit_thought(client, stream_id: stream_id, sequence: seq, text: step.thought)
    seq += 1

    if step.tool_call
      begin
        run_command(client, step.tool_call.argv, reason: step.tool_call.reason, host: 'edge-pod-04')
      rescue Arcp::Error::PermissionDenied
        next # feeds back into the next prompt
      end
    end
    if step.final
      puts step.final
      break
    end
  end

  client.close
end
