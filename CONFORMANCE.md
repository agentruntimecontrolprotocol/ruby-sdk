# Conformance

Spec-to-code matrix against `../spec/docs/draft-arcp-1.1.md`. Status is
either "yes" (implemented and tested) or "deferred" (out of scope for
v1.0.0). No spec MUST/SHOULD in §4–§16 is unimplemented.

| Requirement | Status | Location |
| --- | --- | --- |
| §4 Terminology and conventions | yes | `lib/arcp/version.rb`, `lib/arcp/message_types.rb` |
| §5.1 Envelope (arcp, id, type, session_id, trace_id, job_id, event_seq, payload) | yes | `lib/arcp/envelope.rb` |
| §5.1 trace_id must be 32 hex chars | yes | `lib/arcp/envelope.rb` (`HEX32`) |
| §5.1 payload MUST be Hash or absent | yes | `lib/arcp/envelope.rb#from_h` |
| §5.2 Serialization (JSON, UTF-8) | yes | `lib/arcp/serializer.rb` |
| §5.3 Deep-freeze payload on receive | yes | `lib/arcp/envelope.rb#deep_freeze` |
| §6.1 session.hello with auth + capabilities | yes | `lib/arcp/session/hello.rb`, `lib/arcp/client.rb#handshake!` |
| §6.1 Bearer auth scheme | yes | `lib/arcp/auth/bearer.rb` |
| §6.1 Pluggable AuthScheme | yes | `lib/arcp/auth/auth_scheme.rb` |
| §6.2 Capability negotiation (intersection) | yes | `lib/arcp/session/capability_set.rb#intersect` |
| §6.2 Feature names: heartbeat, ack, list_jobs, subscribe, lease_expires_at, cost.budget, progress, result_chunk, agent_versions | yes | `lib/arcp/session/feature.rb` |
| §6.3 session.welcome with resume_token + resume_window_sec | yes | `lib/arcp/session/welcome.rb`, `lib/arcp/runtime/session_actor.rb` |
| §6.3 Resume by last_event_seq | yes | `lib/arcp/runtime/event_log.rb` |
| §6.4 session.ping / session.pong heartbeats | yes | `lib/arcp/session/ping.rb`, `lib/arcp/session/pong.rb`, `lib/arcp/client.rb#start_heartbeat!` |
| §6.4 HEARTBEAT_LOST MUST NOT terminate jobs | yes | `lib/arcp/runtime/session_actor.rb` |
| §6.5 session.ack with last_processed_seq | yes | `lib/arcp/session/ack.rb`, `lib/arcp/client.rb#ack` |
| §6.6 session.list_jobs with cursor and filter | yes | `lib/arcp/session/list_jobs.rb`, `lib/arcp/client.rb#list_jobs` |
| §6.6 session.jobs response with next_cursor | yes | `lib/arcp/session/jobs_response.rb` |
| §6.7 session.error and session.bye | yes | `lib/arcp/session/session_error.rb`, `lib/arcp/session/bye.rb` |
| §7.1 job.submit (agent, input, lease_request, lease_constraints, idempotency_key, max_runtime_sec) | yes | `lib/arcp/job/submit.rb` |
| §7.2 job.accepted with job_id + lease | yes | `lib/arcp/job/accepted.rb` |
| §7.3 job.event stream with monotonic event_seq | yes | `lib/arcp/job/event.rb`, `lib/arcp/runtime/event_log.rb` |
| §7.4 job.result (terminal success) | yes | `lib/arcp/job/result.rb` |
| §7.4 job.error (terminal failure with code) | yes | `lib/arcp/job/job_error.rb` |
| §7.5 Agent versioning with `name@version` refs | yes | `lib/arcp/session/agent_inventory.rb#resolve` |
| §7.5 AGENT_VERSION_NOT_AVAILABLE error | yes | `lib/arcp/errors.rb` |
| §7.6 job.subscribe / job.subscribed / job.unsubscribe | yes | `lib/arcp/job/subscribe.rb`, `lib/arcp/job/subscribed.rb`, `lib/arcp/job/unsubscribe.rb`, `lib/arcp/runtime/subscription_manager.rb` |
| §7.6 Subscriber MUST NOT cancel | yes | `lib/arcp/runtime/subscription_manager.rb` |
| §7.6 history=true replays from event_log | yes | `lib/arcp/runtime/event_log.rb` |
| §7 job.cancel with reason | yes | `lib/arcp/job/cancel.rb`, `lib/arcp/client.rb#cancel_job` |
| §8.1 Event ordering per job | yes | `lib/arcp/runtime/event_log.rb` |
| §8.2 EventKind: progress, result_chunk, log, thought, tool_call, tool_result, status, metric, trace_span, delegate | yes | `lib/arcp/job/event.rb#EventKind` |
| §8.2 Body shape per kind | yes | `lib/arcp/job/event_body/*.rb` |
| §8.3 progress event body (current, total, units, message) | yes | `lib/arcp/job/event_body/progress.rb` |
| §8.4 result_chunk with result_id, chunk_seq, data, encoding, more | yes | `lib/arcp/job/event_body/result_chunk.rb` |
| §8.4 job.result references result_id + result_size | yes | `lib/arcp/runtime/job_context.rb#finish` |
| §8.4 MUST NOT mix inline result with chunk stream | yes | `lib/arcp/runtime/job_context.rb#finish` |
| §9.1 Lease record (id, capabilities, budget, expires_at, issued_at) | yes | `lib/arcp/lease.rb` |
| §9.2 LeaseRequest at submit | yes | `lib/arcp/lease.rb#LeaseRequest`, `lib/arcp/job/submit.rb` |
| §9.3 lease_constraints.expires_at (UTC `Z` required) | yes | `lib/arcp/lease.rb#LeaseConstraints#validate!` |
| §9.4 Subsetting on delegate (cap, expires_at, budget bounds) | yes | `lib/arcp/lease.rb#Subsetting.bound` |
| §9.5 LEASE_EXPIRED on use after expiry | yes | `lib/arcp/lease.rb#Lease#expired?`, `lib/arcp/runtime/lease_manager.rb` |
| §9.6 cost.budget capability (BigDecimal per currency) | yes | `lib/arcp/lease.rb#CostBudget` |
| §9.6 BudgetCounter try_decrement | yes | `lib/arcp/lease.rb#BudgetCounter` |
| §9.6 BUDGET_EXHAUSTED on overspend | yes | `lib/arcp/runtime/lease_manager.rb` |
| §10 Delegate event kind with child lease | yes | `lib/arcp/job/event_body/delegate.rb` |
| §10 LEASE_SUBSET_VIOLATION on excess | yes | `lib/arcp/lease.rb#Subsetting.bound` |
| §11 trace_id propagation on envelope | yes | `lib/arcp/envelope.rb`, `lib/arcp/client.rb#send_envelope` |
| §11 Trace context Fiber-local | yes | `lib/arcp/trace.rb` |
| §11 OpenTelemetry bridge when present | yes | `lib/arcp/trace.rb#in_span` |
| §12 15 wire error codes | yes | `lib/arcp/errors.rb` (`WIRE_CODES`) |
| §12 retryable? defaults | yes | `lib/arcp/errors.rb` |
| §12 Errors.for(code) factory | yes | `lib/arcp/errors.rb#Errors.for` |
| §13 Idempotency key on submit | yes | `lib/arcp/job/submit.rb`, `lib/arcp/runtime/job_manager.rb` |
| §13 DUPLICATE_KEY on idempotency collision | yes | `lib/arcp/runtime/job_manager.rb` |
| §14 Backpressure signal | yes | `lib/arcp/errors.rb#Backpressure` |
| §15 Vendor extensions via `x-vendor.*` event kinds | yes | `lib/arcp/job/event.rb#Event.from_h` (unknown kinds pass through frozen) |
| §16 Subprotocol identifier `arcp.v1` | yes | `lib/arcp/version.rb` |
| §A.1 Multi-tenant routing | deferred | n/a |
| §A.2 Wire compression | deferred | n/a |
