#!/usr/bin/env ruby
# frozen_string_literal: true

# Cheap-tier first; escalate to deep tier via agent.handoff.

require 'arcp'
require 'async'
require 'base64'
require 'digest'
require 'json'
require 'securerandom'

require_relative 'cheap'

CONFIDENCE_THRESHOLD = 0.65
DEEP_URL = 'wss://opus-pool.tier3.internal'
DEEP_KIND = 'arcp-opus-pool'
DEEP_FINGERPRINT = 'sha256:0a37bf7d61cca21f00...' # pinned

def package_context(client, transcript:)
  body = JSON.generate(transcript)
  artifact_id = "art_#{SecureRandom.hex(7)}"
  env = Arcp::Envelope.build(
    type: 'artifact.put',
    payload: {
      artifact_id: artifact_id,
      media_type: 'application/json',
      size: body.bytesize,
      sha256: Digest::SHA256.hexdigest(body),
      data: Base64.strict_encode64(body)
    },
    session_id: client.session_id
  )
  client.send_envelope(env)
  reply = client.receive_envelope
  raise Arcp::Error::Internal, "got #{reply.type}" unless reply.type == 'artifact.ref'

  reply.payload
end

def emit_handoff(client, artifact_ref:, trace_id:)
  env = Arcp::Envelope.build(
    type: 'agent.handoff',
    trace_id: trace_id,
    payload: {
      target_runtime: {
        url: DEEP_URL, kind: DEEP_KIND, fingerprint: DEEP_FINGERPRINT
      },
      session_id: client.session_id&.value,
      # Spec gestures at shared_memory_ref (RFC §14); we use it
      # explicitly so the deep tier knows where the transcript lives.
      shared_memory_ref: artifact_ref
    },
    session_id: client.session_id
  )
  client.send_envelope(env)
end

Sync do
  cheap = nil # ARCPClient(...) pinned to wss://haiku-pool.tier1.internal
  accepted = cheap.open
  # Pin runtime kind + fingerprint (RFC §8.3); refuse on mismatch.
  raise Arcp::Error::Unauthenticated, 'cheap kind mismatch' if accepted[:runtime][:kind] != 'arcp-haiku-pool'

  request = 'what does CRDT stand for?'
  trace_id = "trace_#{SecureRandom.hex(6)}"

  answer, confidence = Cheap.attempt(request)
  if confidence >= CONFIDENCE_THRESHOLD
    puts answer
  else
    artifact = package_context(
      cheap,
      transcript: {
        user_request: request,
        transcript: [
          { role: 'user', content: request },
          { role: 'assistant', content: answer }
        ],
        cheap_confidence: confidence
      }
    )
    emit_handoff(cheap, artifact_ref: artifact, trace_id: trace_id)
    puts "[handed off to #{DEEP_KIND} trace_id=#{trace_id}]"
  end

  cheap.close
end
