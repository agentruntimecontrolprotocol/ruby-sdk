#!/usr/bin/env ruby
# frozen_string_literal: true

# ARCP runtime fronting an MCP server (RFC §20).
#
# MCP describes capabilities; ARCP operationalizes them. This bridge
# translates inbound ARCP `tool.invoke` envelopes into MCP `call_tool`
# calls against an upstream MCP server, and emits the ARCP job
# lifecycle back to the calling client.
#
#   ARCP client --tool.invoke--> bridge --call_tool--> MCP server
#   ARCP client <--job.{accepted,started,completed,failed}-- bridge

require 'arcp'
require 'async'

# TODO: replace with vendored MCP bridge once a stable mcp-rb gem ships.
require 'mcp'

require_relative 'upstream'

# Per RFC §20:
#   MCP tool schema -> ARCP capability  (advertised at session.accepted)
#   MCP tool call   -> ARCP job
#   MCP resource    -> ARCP stream of kind: event  (delegated to MCP)

# MCP `tools/list` -> namespaced ARCP capability extensions. Each
# upstream tool surfaces as `arcpx.mcp.tool.<name>.v1` so clients can
# negotiate which tools they require at session open.
def advertise_from_mcp(mcp)
  mcp.list_tools.tools.map { |t| "arcpx.mcp.tool.#{t.name}.v1" }
end

# Translate ARCP `tool.invoke.payload` into MCP `call_tool`.
# MCP returns typed content blocks; flatten to a JSON-serializable
# Hash for the ARCP `tool.result` / `job.completed` payload. MCP
# errors become canonical ARCP error codes.
def call_via_mcp(mcp, tool:, arguments:)
  result = mcp.call_tool(tool, arguments: arguments)
rescue StandardError => e
  raise Arcp::Error::Internal, e.message
else
  if result.is_error
    text = result.content.map { |c| c.respond_to?(:text) ? c.text : '' }.join("\n")
    # MCP doesn't carry a typed error code; FAILED_PRECONDITION is
    # the right canonical mapping for "tool ran, said no".
    raise Arcp::Error::FailedPrecondition, (text.empty? ? 'tool error' : text)
  end

  { content: result.content.map(&:to_h) }
end

# One inbound ARCP `tool.invoke` -> MCP call -> ARCP job lifecycle.
def handle_invoke(send_envelope, mcp:, request:)
  job_id = "job_#{Arcp::Ids.new_message_id[-10..]}"

  send_envelope.call(Arcp::Envelope.build(
                       type: 'job.accepted', correlation_id: request.id, job_id: job_id,
                       payload: { job_id: job_id, state: 'accepted' }
                     ))
  send_envelope.call(Arcp::Envelope.build(
                       type: 'job.started', job_id: job_id, payload: { job_id: job_id }
                     ))

  begin
    payload = request.payload
    result = call_via_mcp(
      mcp,
      tool: payload.respond_to?(:tool) ? payload.tool : payload[:tool].to_s,
      arguments: payload.respond_to?(:arguments) ? payload.arguments : (payload[:arguments] || {})
    )
  rescue Arcp::Error => e
    send_envelope.call(Arcp::Envelope.build(
                         type: 'job.failed', job_id: job_id, payload: e.to_payload
                       ))
    return
  end

  send_envelope.call(Arcp::Envelope.build(
                       type: 'job.completed', job_id: job_id, payload: { result: result }
                     ))
end

# Wire one MCP session as the upstream for one ARCP runtime.
def run_bridge(send_envelope, inbound)
  MCP::Client.stdio(Upstream.params) do |mcp|
    mcp.initialize!
    extensions = advertise_from_mcp(mcp)
    # In production this list would feed `Capabilities.extensions`
    # at the runtime's `session.accepted` so clients negotiate
    # exactly the MCP tools they expect to use.
    puts "bridged: #{extensions.inspect}"

    inbound.each do |envelope|
      handle_invoke(send_envelope, mcp: mcp, request: envelope) if envelope.type == 'tool.invoke'
    end
  end
end

Sync do
  # Production version: instantiate an `Arcp::Runtime::Runtime`, point
  # its tool-invoke handler at `handle_invoke`, and let the WebSocket
  # transport carry inbound envelopes from real ARCP clients. We elide
  # the runtime wiring (symmetric with the helpers in
  # arcp/runtime/runtime.rb) so this file stays focused on the §20
  # translation between protocols.
  send_envelope = nil # bound to the runtime's outbound channel
  inbound = nil       # enumerable of inbound envelopes
  run_bridge(send_envelope, inbound)
end
