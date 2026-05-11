#!/usr/bin/env ruby
# frozen_string_literal: true

# Generator proposes; reviewer holds veto via permission.request.

require 'arcp'
require 'async'
require 'digest'

require_relative 'agents'

MAX_REVISIONS = 4

def fingerprint(diff)
  Digest::SHA256.hexdigest(diff)[0, 16]
end

def request_apply(client, ticket_id:, patch:)
  fp = fingerprint(patch.diff)
  request = Arcp::Envelope.build(
    type: 'permission.request',
    # Same key per (ticket, diff): identical patch dedupes at runtime.
    idempotency_key: "review:#{ticket_id}:#{fp}",
    payload: Arcp::Messages::Permissions::PermissionRequest.new(
      permission: 'repo.write',
      resource: "ticket:#{ticket_id}/#{fp}",
      operation: 'apply_patch',
      reason: 'apply patch',
      requested_lease_seconds: 90
    ),
    session_id: client.session_id
  )
  client.send_envelope(request)
  reply = client.receive_envelope
  case reply.payload
  in Arcp::Messages::Permissions::PermissionDeny => d
    raise Arcp::Error::PermissionDenied, (d.reason || 'denied')
  in Arcp::Messages::Permissions::PermissionGrant => g
    g.resource
  end
end

def respond(client, request:, verdict:)
  payload =
    if verdict.grant
      Arcp::Messages::Permissions::PermissionGrant.new(
        permission: request.payload.permission,
        resource: request.payload.resource,
        operation: request.payload.operation,
        lease_seconds: 90, attestation: nil
      )
    else
      Arcp::Messages::Permissions::PermissionDeny.new(
        permission: request.payload.permission,
        resource: request.payload.resource,
        operation: request.payload.operation,
        reason: verdict.reason
      )
    end
  type = payload.is_a?(Arcp::Messages::Permissions::PermissionGrant) ? 'permission.grant' : 'permission.deny'
  env = Arcp::Envelope.build(
    type: type, payload: payload,
    correlation_id: request.id, session_id: client.session_id
  )
  client.send_envelope(env)
end

def reviewer_loop(reviewer, ticket)
  loop do
    env = reviewer.receive_envelope
    break if env.nil?
    next unless env.type == 'permission.request'

    verdict = Agents.review(ticket: ticket, request: env)
    respond(reviewer, request: env, verdict: verdict)
  end
end

Sync do
  # Two sessions, one per agent. In production they'd be on different
  # runtimes; the contract is identical.
  generator = nil # ARCPClient(...)
  reviewer  = nil # ARCPClient(...)
  generator.open
  reviewer.open

  ticket_id = 'JIRA-4812'
  ticket = 'Reject JWTs whose `aud` does not match the configured audience. Add a unit test.'
  rev_task = Async { reviewer_loop(reviewer, ticket) }

  prior_denial = nil
  begin
    applied = false
    MAX_REVISIONS.times do
      patch = Agents.propose(ticket: ticket, prior_denial: prior_denial)
      begin
        lease = request_apply(generator, ticket_id: ticket_id, patch: patch)
      rescue Arcp::Error::PermissionDenied => e
        prior_denial = e.message
        next
      end
      puts "applied #{fingerprint(patch.diff)} lease=#{lease}"
      applied = true
      break
    end
    puts 'abandoned after max_revisions' unless applied
  ensure
    rev_task.stop
    generator.close
    reviewer.close
  end
end
