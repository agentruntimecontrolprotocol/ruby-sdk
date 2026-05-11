#!/usr/bin/env ruby
# frozen_string_literal: true

# Warehouse DB admin agent. Reads pre-granted; writes prompt operator.

require 'arcp'
require 'async'
require 'time'

require_relative 'sql' # sqlglot-equivalent classifier

PRE_GRANTED = %w[public.orders public.customers
                 warehouse.fct_revenue_daily].freeze
READ_LEASE_SECONDS = 60 * 60
WRITE_LEASE_SECONDS = 5 * 60

LeaseHandle = Data.define(:lease_id, :expires_at)

def request_lease(client, permission:, table:, operation:, seconds:, reason:)
  request = Arcp::Envelope.build(
    type: 'permission.request',
    payload: Arcp::Messages::Permissions::PermissionRequest.new(
      permission: permission, resource: "table:#{table}",
      operation: operation, reason: reason,
      requested_lease_seconds: seconds
    ),
    session_id: client.session_id
  )
  client.send_envelope(request)
  reply = client.receive_envelope
  case reply.payload
  in Arcp::Messages::Permissions::PermissionDeny
    raise Arcp::Error::PermissionDenied, "#{permission} denied on #{table}"
  in Arcp::Messages::Permissions::PermissionGrant => g
    LeaseHandle.new(lease_id: g.resource, expires_at: Time.now.utc + seconds)
  end
end

def authorize(client, sql, leases:)
  klass = SqlClassifier.classify(sql)
  raise Arcp::Error::InvalidArgument, 'no table referenced' if klass.tables.empty?

  op = klass.op # 'read' / 'write' / 'ddl'
  seconds = op == 'read' ? READ_LEASE_SECONDS : WRITE_LEASE_SECONDS
  klass.tables.each do |table|
    cached = leases[[table, op]]
    next if cached && cached.expires_at > Time.now.utc

    leases[[table, op]] = request_lease(
      client, permission: "db.#{op}", table: table, operation: op,
              seconds: seconds, reason: "#{op.upcase} on #{table}: #{sql[0, 80]}"
    )
  end
  op
end

# Wire `lease.revoked` into the cache so the next call re-prompts.
def handle_inbound(env, leases)
  return unless env.type == 'lease.revoked'

  lid = env.payload.respond_to?(:lease_id) ? env.payload.lease_id : env.payload[:lease_id]
  leases.delete_if { |_, handle| handle.lease_id == lid }
end

Sync do
  client = nil # ARCPClient(...) — transport, identity, auth elided
  client.open

  leases = {}

  drain = Async do
    loop do
      env = client.receive_envelope
      break if env.nil?

      handle_inbound(env, leases)
    end
  end

  # Pre-grant the broad reads at session open. SELECT runs free.
  PRE_GRANTED.each do |table|
    leases[[table, 'read']] = request_lease(
      client, permission: 'db.read', table: table, operation: 'read',
              seconds: READ_LEASE_SECONDS, reason: 'bootstrap'
    )
  end

  # SELECT — covered by the bootstrap lease.
  authorize(
    client,
    'SELECT count(*) FROM public.orders WHERE shipped_at::date = current_date - 1',
    leases: leases
  )
  # UPDATE — triggers permission.request; operator must approve.
  authorize(
    client,
    "UPDATE public.orders SET status='refunded' WHERE id=4812",
    leases: leases
  )

  drain.stop
  client.close
end
