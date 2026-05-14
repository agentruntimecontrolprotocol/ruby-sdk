# 05 — Host adapter gems

Mirrors `../typescript-sdk/packages/middleware/{node,express,fastify,hono,bun,otel}`.
Ruby's web hosting situation does not fan out the same way — the
relevant axes are Rack-vs-Falcon (concurrency model) and
ActionCable-vs-not (Rails coupling), not "one per framework." This
phase ships **four** adapter gems and explicitly rejects six other
candidates.

| TS package                  | Ruby gem        | Why the asymmetry                                                                                                                |
| --------------------------- | --------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `@arcp/middleware-node`     | `arcp-rack`     | Rack is the Ruby equivalent of "the host abstraction every web server implements." One gem covers the surface.                   |
| `@arcp/middleware-express`  | (folded)        | Express-specific adapter has no Ruby analogue: Sinatra/Roda/Hanami all mount Rack middleware identically. See rejection §5.1.    |
| `@arcp/middleware-fastify`  | (folded)        | Same — Fastify's Ruby analogue would be Roda, which is Rack-mountable; the control-plane endpoints belong in `arcp-rack`.       |
| `@arcp/middleware-hono`     | (folded)        | Hono is an Edge/Node hybrid; closest Ruby equivalent is Falcon (Fiber-scheduled). Covered by `arcp-falcon`.                      |
| `@arcp/middleware-bun`      | (folded)        | Bun is a runtime, not a framework; Ruby's runtime is `async`+Falcon — see `arcp-falcon`.                                         |
| `@arcp/middleware-otel`     | `arcp-otel`     | Direct port.                                                                                                                     |
| —                           | `arcp-rails`    | No TS analogue. Rails has its own WS protocol (ActionCable) and process model that nothing in Node lines up with.                 |

Per `02-current-audit.md` §7, the ARCP runtime is a **long-lived
`Async::Reactor` process**, not a per-request Puma worker. That
constraint drives the entire gem split below — `arcp-rack` is the
control-plane adapter, `arcp-falcon` is the only first-party WS
host, `arcp-rails` is a bridge, `arcp-otel` is a transport wrapper.

---

## 1. `arcp-rack`

### Why this adapter

Ships the §6.6 `session.list_jobs` HTTP bridge endpoint, the
`/healthz` and `/readyz` probes Falcon and Puma both consume, and a
`Rack::Auth::Bearer`-shaped helper that decodes the bearer token
the same way `Arcp::Session::Hello` does (`auth.scheme = "bearer"`
per spec §6.1). This rules **in** every Rack-compatible host
(Puma, Falcon, Unicorn, Passenger) for the control plane and rules
**out** any attempt to terminate WebSocket upgrades through this
gem — Puma's `rack.hijack` protocol cannot deliver frames to an
`Async::Task` inside the SDK without a thread-to-fiber bridge that
defeats the Fiber-scheduler advantage `03-libraries.md` selected
`async-websocket` for. Documentation states the limit in one line
and points readers at `arcp-falcon`.

### WS upgrade attachment

None. This adapter explicitly does not handle Sec-WebSocket-Key /
Sec-WebSocket-Accept; it returns HTTP `426 Upgrade Required` with a
`Sec-WebSocket-Protocol: arcp.v1` advisory header from
`/v1/session` GETs, on the theory that surfacing the mismatch is
more useful than silently failing. The Rack adapter only accepts
JSON POSTs for the `session.list_jobs` bridge, JSON GETs for
health, and emits `text/event-stream` only if a future plan
re-introduces SSE (out of scope for v1.1).

### Host / DNS-rebind check

Per `draft-arcp-02.1.md` §14 (security considerations carry from
v1.0 unchanged), every Rack middleware in the stack validates the
`Host` header against a configured allowlist before any decode work
runs. The check is a `frozen_string_literal` `Set` lookup; a miss
returns `421 Misdirected Request` with no body. WS upgrade
attempts that arrive with a `Sec-WebSocket-Protocol` other than
`arcp.v1` (or no subprotocol at all) get `400` with body
`{"error":"INVALID_REQUEST"}` keyed to spec §12. This matches
RFC 6455 §4.1.9 origin-check guidance and shuts down the
DNS-rebind class of attack at the earliest stack frame.

### Public API sketch

```
module Arcp
  module Rack
    class Middleware
      # @param app           [#call]                    downstream Rack app
      # @param runtime       [Arcp::Runtime::Runtime]   in-process runtime
      # @param mount_at      [String]                   default '/arcp'
      # @param allowed_hosts [Array<String>]            DNS-rebind allowlist
      def initialize(app, runtime:, mount_at: '/arcp', allowed_hosts:); end

      # Rack contract.
      def call(env); end
    end

    # Bearer extraction; mirrors Arcp::Session::Hello#auth.
    module Bearer
      def self.from_env(env) = ... # → String | nil
    end
  end
end
```

Mount in any `config.ru`:

```
use Arcp::Rack::Middleware, runtime: runtime, allowed_hosts: %w[arcp.example.com]
```

---

## 2. `arcp-falcon`

### Why this adapter

`02-current-audit.md` §7 names Falcon as the primary runtime host:
it shares the `Async` reactor the SDK already runs on, so a
`Job::Event` emitted by `JobManager` reaches a WebSocket frame
without crossing a thread boundary, and `Async::Task#stop`
propagates from a `session.bye` into the per-connection task with
no extra plumbing. Falcon is also the only mainstream Rack server
that ships first-class HTTP/2 plus WebSocket plus Fiber-scheduler
integration — Puma's HTTP/2 is gated on `rack.hijack` and Unicorn
has neither. Anything ARCP runtime-side that needs to host network
WS lives here.

### WS upgrade attachment

`Async::WebSocket::Adapters::Rack.open(env, protocols: ['arcp.v1'])`
inside a Rack `call`. Falcon's `Async::HTTP::Server` invokes the
Rack app inside an `Async::Task`, so the adapter's
`open` returns a connected `Async::WebSocket::Connection` and the
ARCP `Transport` implementation wraps it directly — no `rack.hijack`,
no `EM.run`, no thread pool. Each WS frame is decoded inside an
`Async::Queue#dequeue` loop on the same task; cancellation flows
via `task.stop` when the session ends (per `04-architecture.md`'s
concurrency seam — `Async { ... }` at the I/O boundary, cancel via
`stop`). Heartbeat per §6.4 attaches as a child `Async::Task` of
the connection task so it cancels with the parent.

### Host / DNS-rebind check

Same allowlist primitive as `arcp-rack` (the validation helper
lives in `arcp-rack` and `arcp-falcon` depends on it). On WS
upgrade specifically, the adapter inspects three headers before
returning the 101: `Host` against allowlist, `Sec-WebSocket-Protocol`
must include `arcp.v1` exactly (no version-tolerant fuzzy match —
v1.1 is wire-compatible with v1.0 within the same `arcp.v1`
subprotocol per spec §5), and `Origin` is logged but not enforced
(WS clients are often non-browser per spec §4). A failure returns
`HTTP/1.1 400 Bad Request` before the upgrade completes so the
client surfaces it as `INVALID_REQUEST` per §12.

### Public API sketch

```
module Arcp
  module Falcon
    class App
      # @param runtime       [Arcp::Runtime::Runtime]
      # @param mount_at      [String]              default '/v1/session'
      # @param allowed_hosts [Array<String>]
      def initialize(runtime:, mount_at: '/v1/session', allowed_hosts:); end

      def call(env); end  # Rack contract, Falcon-hosted
    end
  end
end

# falcon.rb (Falcon's config file)
require 'arcp/falcon'
run Arcp::Falcon::App.new(runtime: Arcp::Runtime::Runtime.new, allowed_hosts: %w[...])
```

A `bin/arcp-falcon` is intentionally **not** shipped — `falcon
serve` reading `falcon.rb` is the documented entry point. Adding a
wrapper binary would diverge from Falcon's own conventions.

---

## 3. `arcp-rails`

### Why this adapter

A Rails app's process model is **Puma serving HTTP requests**; the
ARCP runtime needs a long-lived `Async` reactor. These are
incompatible inside one process unless ActionCable is the
bridge — and ActionCable speaks its own subprotocol
`actioncable-v1-json`, not ARCP's `arcp.v1`. Stating that honestly
is the whole point of this adapter's README: ActionCable is **not**
an ARCP transport. The gem therefore ships two **separate**
integration modes, named, with their tradeoffs spelled out.

#### Mode A — sidecar Falcon engine (recommended)

A `Rails::Engine` that mounts `arcp-falcon` on a dedicated Falcon
process on a separate port. The Rails app's Puma keeps serving
HTTP on `:3000`; Falcon serves WS on `:9292` (or whatever
`Arcp.configuration.falcon_port` resolves to). `bin/rails
arcp:serve` is the rake task that spawns it; the Rails app reuses
its own DB connection pool and `Rails.application.credentials` via
a thin shim so the ARCP runtime's auth and job-store layers share
configuration without sharing a process. This is what
`02-current-audit.md` §7 calls "the daemon-style deployment."

#### Mode B — ActionCable channel (tunneled)

An `ActionCable::Channel::Base` subclass that runs an ARCP
`Session` inside a single ActionCable connection by **tunneling
ARCP envelopes inside ActionCable's `message` field**. Tradeoffs:

- **Win:** reuses Rails app's `ActionCable::Connection#connect`
  authentication (cookies, Devise, JWT-via-middleware) and
  `current_user` identification. No second auth stack.
- **Loss:** every frame is double-decoded — ActionCable's
  `{ "command": "message", "identifier": "...", "data": "<arcp
  envelope JSON>" }` wraps the ARCP envelope as a JSON-string-in-a-
  JSON-string. That is an extra `JSON.parse` per frame on both
  sides; document it as the cost of in-Rails embedding.
- **Constraint:** ActionCable's pubsub adapter (Redis, Postgres,
  inline) becomes part of the ARCP transport's reliability story;
  if the Rails app uses the `inline` adapter, cross-process WS
  fanout doesn't work and `job.subscribe` from another worker
  silently fails. README states this explicitly.

### WS upgrade attachment

Mode A delegates to `arcp-falcon` (already covered §2). Mode B
attaches **inside** ActionCable's existing upgrade path —
ActionCable's `Connection#process` has already negotiated the
`actioncable-v1-json` subprotocol, so the ARCP channel doesn't
touch upgrade at all. Outbound ARCP envelopes call
`transmit(envelope.to_h)` and ActionCable serializes; inbound
`receive(data)` decodes the ActionCable wrapper and feeds the
inner envelope into `Arcp::Session::Dispatch`.

### Host / DNS-rebind check

Mode A inherits `arcp-falcon`'s allowlist. Mode B inherits Rails'
`config.hosts` allowlist (`ActionDispatch::HostAuthorization`) —
that's the canonical Rails seam for DNS-rebind defense, and
duplicating it in the channel would diverge from the rest of the
Rails app's hardening. The channel additionally rejects connections
whose `request.headers['Sec-WebSocket-Protocol']` does not include
`actioncable-v1-json` (ActionCable's contract) and emits a
`Arcp::Errors::UnnegotiatedFeature` if the inner envelope claims
`features` the session never negotiated.

### Public API sketch

```
# Mode A — Engine.
module Arcp
  module Rails
    class Engine < ::Rails::Engine
      isolate_namespace Arcp::Rails
    end

    # bin/rails arcp:serve invokes this.
    module Tasks
      def self.serve(port: 9292); end
    end
  end
end

# Mode B — Channel (tunneled).
module Arcp
  module Rails
    class SessionChannel < ::ActionCable::Channel::Base
      # Bound to current_user via ActionCable::Connection#connect.
      def subscribed; end
      def unsubscribed; end
      # Receives ActionCable's data hash; inner envelope is data['envelope'].
      def receive(data); end
    end
  end
end
```

`config/routes.rb` mounts the Mode-A engine:

```
mount Arcp::Rails::Engine => '/arcp'
```

Mode B subscribes via the standard ActionCable JS client (or any
client that speaks the ActionCable subprotocol) and rides ARCP
envelopes inside.

---

## 4. `arcp-otel`

### Why this adapter

Parity with `@arcp/middleware-otel` at
`../typescript-sdk/packages/middleware/otel/src/index.ts`. The
seam ARCP exposes is `Arcp::Transport` (per
`04-architecture.md`'s `Arcp::Transport` interface — abstract base
with `MemoryTransport`, `WebSocketTransport`, `StdioTransport`); a
tracing decorator wraps any of them so the SDK never reaches into
client or runtime code to instrument. `03-libraries.md` pins this
to `opentelemetry-api` only — the consumer wires the SDK and
exporter; the adapter is API-only so it can be a hard dep without
forcing an exporter on consumers.

### WS upgrade attachment

None. This is a transport decorator, not a host adapter. The
`traceparent` HTTP header on the initial WS handshake is consumed
by `arcp-falcon` / `arcp-rack` and stuffed into the `Session`'s
fiber-local context via `Arcp::Trace.with_remote(headers)` at
upgrade time; the `arcp-otel` decorator then picks it up via
`OpenTelemetry::Context.current` for the first emitted span.
Per-envelope spans live inside `Transport#send` / `Transport#receive`
wrapping, mirroring the TS `withTracing` shape exactly.

### Host / DNS-rebind check

Not applicable — no network surface of its own. The decorator
runs after `arcp-falcon` / `arcp-rack` have already accepted the
connection, so allowlist checks are upstream. The one thing it
guards is **not propagating a `traceparent` whose `trace-id` is
all zeros** (W3C Trace Context §3.2.2.3 disallows it); the
extractor returns `nil` and the span starts a new trace rather
than poisoning the parent context.

### Parity items (must match TS)

- **Extension key.** Vendor-namespaced per spec §15: the carrier
  rides under `extensions["x-vendor.opentelemetry.tracecontext"]`,
  the exact string used in
  `../typescript-sdk/packages/middleware/otel/src/index.ts:48`.
  Diverging from this string breaks cross-language trace
  continuation.
- **Span name shape.** `arcp.send <type>` and `arcp.recv <type>`,
  matching TS `index.ts:73,107`.
- **Span kind.** `PRODUCER` outbound, `CONSUMER` inbound (TS
  `index.ts:76,112`).
- **Per-envelope attributes** — names mirror TS
  `extractAttributes` (`index.ts:139–183`):
  - `arcp.direction` — `"in" | "out"`.
  - `arcp.type`, `arcp.id`, `arcp.session_id`, `arcp.job_id`,
    `arcp.trace_id`, `arcp.event_seq`.
  - `arcp.agent` (when payload carries one).
  - `arcp.lease.capabilities` — comma-joined capability keys.
  - **v1.1 (§11):** `arcp.lease.expires_at` — string, populated
    from `payload.lease_constraints.expires_at`.
  - **v1.1 (§11):** `arcp.budget.remaining` — `JSON.dump`-encoded
    object preserving per-currency totals, sourced from
    `payload.budget`. `BigDecimal` amounts serialize via
    `BigDecimal#to_s('F')` to avoid scientific notation drift
    (per `03-libraries.md`'s `BigDecimal` pick for §9.6 cost
    math).
- **Tracer acquisition.** `OpenTelemetry.tracer_provider.tracer('arcp')`.
  When `opentelemetry-sdk` is not required by the host app, the
  `opentelemetry-api` default `tracer_provider` is a no-op — spans
  cost a hash allocation and nothing else. Verify with a unit
  test that no-op mode does not call `inject` / `extract` on a
  real propagator.
- **Error recording.** `span.record_exception(err)` plus
  `span.status = Status.error(err.message)` on rescue, matching
  TS `recordError` (`index.ts:213–222`). Re-raise after recording.

### Public API sketch

```
module Arcp
  module Otel
    # Wrap any Arcp::Transport so each send/recv produces a span and
    # W3C trace context propagates via extensions["x-vendor.opentelemetry.tracecontext"].
    #
    # @param inner            [Arcp::Transport]
    # @param tracer           [OpenTelemetry::Trace::Tracer]
    # @param send_span_name   [#call, nil]
    # @param recv_span_name   [#call, nil]
    # @return                 [Arcp::Transport]
    def self.with_tracing(inner, tracer: OpenTelemetry.tracer_provider.tracer('arcp'),
                          send_span_name: nil, recv_span_name: nil); end
  end
end
```

Wire it on either side, mirroring TS:

```
traced = Arcp::Otel.with_tracing(raw_transport)
runtime.accept(traced)   # or client.connect(traced)
```

---

## 5. Explicit rejections

Each is a single-sentence reason — they exist so reviewers don't
re-litigate them.

### 5.1. `arcp-sinatra`

Sinatra has no native WebSocket primitive; its WS story is
`sinatra-websocket` (EventMachine-based, rejected §5.4) or
mounting Rack middleware, which `arcp-rack` already covers.
A separate gem would be a one-line `require 'arcp/rack'` wrapper.

### 5.2. `arcp-roda`

Same as Sinatra: Roda is Rack middleware all the way down, so
`arcp-rack` covers it without a vanity wrapper.

### 5.3. `arcp-puma` (standalone)

Puma's WebSocket support is `rack.hijack`-based, requires the
consumer to proxy frames manually between a blocking IO and the
SDK's `Async::Task`, and is documented by Puma's own maintainers
as fragile under load. Puma stays a **client-side** host (a Rails
app on Puma talking to an ARCP runtime is fine — the runtime
itself must be Falcon-hosted per `02-current-audit.md` §7).

### 5.4. `em-websocket` / any EventMachine-backed gem

EventMachine runs its own reactor that does not compose with the
Ruby 3.x Fiber scheduler `async` installs, so any frame received
by EM has to cross a thread boundary to reach an `Async::Queue`.

### 5.5. `faye-websocket`

Carries an `eventmachine` dep by default, and the SDK already
standardized on `async-websocket` in `03-libraries.md` —
introducing a second WS stack doubles the attack surface for no
feature gain.

### 5.6. `websocket-driver` (raw)

Lower-level than `async-websocket`; the SDK would re-implement
handshake parsing and frame masking with no headroom for it.
`async-websocket` already wraps `websocket-driver` underneath when
needed.

---

## 6. Cross-adapter invariants

- Every adapter that owns an upgrade endpoint validates `Host`
  against an explicit allowlist (per §14 security envelope) and
  requires `Sec-WebSocket-Protocol` to include `arcp.v1` exactly.
- Every adapter exposes a `runtime:` keyword arg, not a class
  method or singleton — multiple `Arcp::Runtime::Runtime`
  instances in one process is a supported deployment (per
  `04-architecture.md`'s public API sketch).
- No adapter parses ARCP envelopes itself — decoding is
  `Arcp::Envelope.from_json` per `04-architecture.md`. Adapters
  carry **frames**, not message types.
- `frozen_string_literal: true` on every `.rb` in every gem
  (`STYLE.md`, `02-current-audit.md` §3).
- Each gem has its own `.gemspec` with `required_ruby_version
  '>= 3.4.0'` matching core, and lists `arcp` as a runtime dep
  pinned to the same minor (`'~> 1.1.0'`).
