# resumability

Five-step research job (plan → gather → synthesize → critique →
finalize) that checkpoints after every step. Crash mid-flight,
resume on next invocation, no work lost.

## Before ARCP

Long jobs survive crashes only if the team built their own
checkpoint store, retry contract, and dedupe layer. Most don't.
Crash means restart; restart means re-spending tokens; "did this
already run?" turns into a SQL detective story.

## With ARCP

```ruby
# every step ends with two envelopes
emit_progress(client, job_id: job_id, step: 'synthesize')
emit_checkpoint(client, job_id: job_id, step: 'synthesize')

# resume picks up at the step *after* the last checkpoint
last = issue_resume(client, job_id: job_id, after_message_id: ..., checkpoint_id: ...)
next_idx = STEPS.index(last) + 1
```

Per-step `idempotency_key` keeps execution single across retries:
the runtime returns the prior outcome if the same step is re-issued.

## Try it

```bash
# crash after `synthesize`. Prints the resume token.
CRASH_AFTER_STEP=synthesize ruby samples/resumability/main.rb

# resume — runtime replays up to the last checkpoint, we run from
# the next step.
RESUME_JOB_ID=... RESUME_AFTER_MSG_ID=... RESUME_CHECKPOINT_ID=... \
  ruby samples/resumability/main.rb
```

## ARCP primitives

- Resumability — RFC §19, `after_message_id` + `checkpoint_id`.
- Job lifecycle + checkpoints — §10.
- `idempotency_key` semantics — §6.4.
- `DATA_LOSS` on retention expiry — §19, §18.2.

## File tour

- `main.rb` — `start_fresh` vs `resume`. `Process.exit!` on the crash
  step to demonstrate process death.
- `steps.rb` — actual step body stub.

## Variations

- Plug a SQLite-backed checkpointer that doubles to a local store so
  checkpoints survive ARCP retention expiry too.
- Branch on critique severity: low → finalize; high → loop back to
  synthesize with the critique appended.
- Emit `kind: thought` between steps for
  [reasoning_streams](../reasoning_streams) to consume.
