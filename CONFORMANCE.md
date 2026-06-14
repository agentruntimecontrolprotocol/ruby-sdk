# Conformance

Spec-to-code matrix against [`../spec/docs/draft-arcp-1.1.md`](../spec/docs/draft-arcp-1.1.md).
Section numbers match the v1.1 draft. Status is `yes` (implemented and
tested) or `deferred` (explicitly out of scope per the spec's **Deferred**
list). Lease, budget, and model enforcement are provided as synchronous
guarded seams the agent/runtime applies before authority-bearing operations
(`JobContext#authorize!`, `#use_model!`, and the guarded `#tool_call`).

| Requirement | Status | Location |
| --- | --- | --- |
| §4 Transport (WebSocket / stdio / memory) | yes | `lib/arcp/transport/*.rb` |
| §5 Wire Format: envelope (arcp, id, type, session_id, trace_id, job_id, event_seq, payload) | yes | `lib/arcp/envelope.rb` |
| §5 trace_id is 32 hex chars; payload is Hash or absent | yes | `lib/arcp/envelope.rb` (`HEX32`, `from_h`) |
| §5 JSON / UTF-8 serialization | yes | `lib/arcp/serializer.rb` |
| §5 Ignore unknown top-level envelope fields; deep-freeze on receive | yes | `lib/arcp/envelope.rb` |
| §6.1 session.hello auth (bearer, pluggable scheme) | yes | `lib/arcp/session/hello.rb`, `lib/arcp/auth/*.rb` |
| §6.2 Capability negotiation (intersection); encodings default `["json"]` | yes | `lib/arcp/session/capability_set.rb` |
| §6.2 Feature names (heartbeat, ack, list_jobs, subscribe, lease_expires_at, cost.budget, model.use, provisioned_credentials, progress, result_chunk, agent_versions) | yes | `lib/arcp/session/feature.rb` |
| §6.3 session.welcome with resume_token + resume_window_sec | yes | `lib/arcp/session/welcome.rb`, `lib/arcp/runtime/session_actor.rb` |
| §6.3 Resume by last_event_seq; resume_token rotates on every welcome | yes | `lib/arcp/runtime/session_actor.rb#perform_resume`, `lib/arcp/runtime/resume_registry.rb` |
| §6.3 RESUME_WINDOW_EXPIRED when buffer no longer covers the cursor | yes | `lib/arcp/runtime/session_actor.rb#perform_resume`, `lib/arcp/runtime/event_log.rb#floor` |
| §6.4 session.ping / session.pong; HEARTBEAT_LOST never terminates jobs | yes | `lib/arcp/session/ping.rb`, `lib/arcp/session/pong.rb`, `lib/arcp/runtime/session_actor.rb` |
| §6.5 session.ack with last_processed_seq; early eviction | yes | `lib/arcp/session/ack.rb`, `lib/arcp/runtime/event_log.rb#evict_up_to` |
| §6.6 session.list_jobs filter (status, agent, created_after) + cursor | yes | `lib/arcp/runtime/job_manager.rb#list`, `lib/arcp/session/list_jobs.rb` |
| §6.7 session.error and session.bye / close | yes | `lib/arcp/session/session_error.rb`, `lib/arcp/session/bye.rb` |
| §7.1 job.submit / job.accepted (agent, input, lease_request, lease_constraints, idempotency_key, max_runtime_sec) | yes | `lib/arcp/job/submit.rb`, `lib/arcp/job/accepted.rb` |
| §7.2 Idempotency replays the original job.accepted; DUPLICATE_KEY on any conflicting parameter | yes | `lib/arcp/runtime/job_manager.rb#idempotent_replay` |
| §7.3 Terminal states success / error / cancelled / timed_out | yes | `lib/arcp/runtime/job_manager.rb`, `lib/arcp/runtime/job_context.rb` |
| §7.4 Cancellation: job.cancelled ack then job.error(code=CANCELLED); reject cancel on terminal jobs | yes | `lib/arcp/runtime/job_manager.rb#cancel`, `lib/arcp/job/cancelled.rb` |
| §7.5 Agent versioning (`name@version`); AGENT_VERSION_NOT_AVAILABLE | yes | `lib/arcp/runtime/job_manager.rb#resolve_agent`, `lib/arcp/errors.rb` |
| §7.6 job.subscribe / job.subscribed (current_status, agent, lease, parent_job_id, trace_id, subscribed_from, replayed) / job.unsubscribe | yes | `lib/arcp/job/subscribed.rb`, `lib/arcp/runtime/session_actor.rb#handle_subscribe` |
| §7.6 Same-principal subscription authorization; history replay strictly > from_event_seq | yes | `lib/arcp/runtime/subscription_manager.rb`, `lib/arcp/runtime/event_log.rb#replay_job` |
| §8.1 / §8.2 Event envelope and kinds (log, thought, tool_call, tool_result, status, metric, artifact_ref, delegate, progress, result_chunk) | yes | `lib/arcp/job/event.rb`, `lib/arcp/job/event_body/*.rb` |
| §8.2.1 progress.current MUST be non-negative | yes | `lib/arcp/job/event_body/progress.rb` |
| §8.3 event_seq is session-scoped, strictly monotonic, gap-free | yes | `lib/arcp/runtime/job_manager.rb#publish_event` |
| §8.4 result_chunk (result_id, chunk_seq, data, encoding, more); no inline/stream mixing | yes | `lib/arcp/job/event_body/result_chunk.rb`, `lib/arcp/runtime/job_context.rb` |
| §9.1–§9.2 Lease capability model and grammar | yes | `lib/arcp/lease.rb` |
| §9.3 Synchronous enforcement before an operation (PERMISSION_DENIED) | yes | `lib/arcp/runtime/job_context.rb#authorize!`, `lib/arcp/runtime/lease_manager.rb#check!` |
| §9.4 Lease subsetting on delegation (cap, expires_at, budget, model bounds) | yes | `lib/arcp/lease.rb#Subsetting.bound` |
| §9.5 expires_at UTC and in the future at submission; LEASE_EXPIRED on use after expiry | yes | `lib/arcp/lease.rb#LeaseConstraints#validate!`, `lib/arcp/runtime/lease_manager.rb#check!` |
| §9.6 cost.budget counters decremented on cost.* metrics; negative rejected; BUDGET_EXHAUSTED at the operation boundary | yes | `lib/arcp/runtime/job_context.rb#metric`, `lib/arcp/runtime/lease_manager.rb#record_cost`, `#budget_exhausted!` |
| §9.7 model.use enforcement (PERMISSION_DENIED) | yes | `lib/arcp/runtime/job_context.rb#use_model!`, `lib/arcp/runtime/lease_manager.rb#check_model!` |
| §9.8 Provisioned credential wire shape and issue/rotate/revoke lifecycle | yes | `lib/arcp/credential.rb`, `lib/arcp/runtime/credential_registry.rb` |
| §10 Delegate event kind with subset child lease; LEASE_SUBSET_VIOLATION | yes | `lib/arcp/job/event_body/delegate.rb`, `lib/arcp/lease.rb#Subsetting.bound` |
| §11 trace_id propagation (Fiber-local, OpenTelemetry bridge when present) | yes | `lib/arcp/trace.rb`, `lib/arcp/envelope.rb` |
| §12 Error taxonomy (15 codes); retryable defaults; Errors.for factory | yes | `lib/arcp/errors.rb` |
| §14 Credential value never echoed to subscribers on rotation | yes | `lib/arcp/runtime/job_context.rb#rotate_credential` |
| §14 Permanent credential-revocation failures logged and surfaced | yes | `lib/arcp/runtime/credential_registry.rb` |
| §14 result_chunk per-chunk and total size caps (INTERNAL_ERROR) | yes | `lib/arcp/runtime/job_context.rb::ChunkWriter` |
| §14 Event buffers evicted by time, not only on ack | yes | `lib/arcp/runtime/event_log.rb#expire!` |
| Deferred: job pause/unpause, priority/scheduling hints, runtime federation, LLM streaming-token surface | deferred | n/a (spec **Deferred** list) |
