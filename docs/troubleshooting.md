---
title: Troubleshooting
sdk: ruby
kind: guide
order: 90
---

# Troubleshooting

## `Arcp::Errors::UnnegotiatedFeature` on `list_jobs` / `ack`

The feature was filtered out during capability negotiation. The
intersection of your `CapabilitySet` and the runtime's must contain
`list_jobs` (or `ack`). Check `client.session.capabilities.features`.

## Puma worker hangs after one request

Don't deploy under Puma or any request-per-thread server. The runtime
expects the `socketry/async` reactor and multiplexes sessions on
fibers. Use `falcon` for hosting.

## `IOError: transport closed` after `client.close`

Expected. After `close`, all client methods raise. Open a new client
to reconnect; if you need missed events, resubscribe with
`history: true` and `from_event_seq: 0` while the runtime's event-log
window still retains them.

## `Arcp::Errors::ResumeWindowExpired` on reconnect

The runtime's event-log retention window elapsed before you asked for a
replay. Submit a fresh subscription with `history: true, from_event_seq:
0` if the job is still live.

## `Arcp::Errors::LeaseSubsetViolation` on `Subsetting.bound`

The child `LeaseRequest` asks for capabilities, an `expires_at`, or a
per-currency budget that exceeds the parent's. Constrain the child
request to a strict subset of the parent lease.

## Handler hangs and never produces a result

A handler MUST call `ctx.finish` or `ctx.fail!` exactly once. If
`stream_result` was used, `ctx.finish(result: nil)` is the terminator
(passing `result:` after `stream_result` is a protocol violation and
raises).

## `Arcp::Errors::Unauthenticated` immediately on `Client.open`

The bearer verifier returned `nil` for the token. With
`Arcp::Auth::Bearer.from_token`, the token string in `auth:` must match
the one registered. With a custom `AuthScheme`, ensure `verify` returns
an `Arcp::Auth::Principal`.

## `Arcp::Errors::AgentVersionNotAvailable`

The `name@version` ref doesn't match any version in the registered
agent's `versions:` array. Either register that version or drop the
`@version` suffix to fall back to `default:`.

## Events drop on the floor between `submit_job` and `subscribe`

Subscribe before awaiting the result. `handle.subscribe(client: client)`
queues events from the moment the job is accepted; if the job
completes before you subscribe, the queue terminates with the buffered
events still present.
