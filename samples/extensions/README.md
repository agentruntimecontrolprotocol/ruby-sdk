# extensions

Reference for ARCP §21. Defines four extension messages
(`arcpx.sdr.tune.v1`, `arcpx.sdr.gain.v1`, `arcpx.sdr.capture.v1`,
`arcpx.sdr.demodulate.v1`) for software-defined radio. Capture and
demodulate return artifact refs. Demonstrates correct unknown-message
handling.

## Before ARCP

SDR control over a domain-specific RPC (gqrx remote, hamlib's
`rigctld`) that the rest of the agent stack doesn't speak. No trace
context, no typed errors, no observability story.

## With ARCP

```ruby
# tune -> gain -> capture -> demodulate, all over one envelope shape
request_response(client, type: EXT_TUNE, payload: { ... })
request_response(client, type: EXT_GAIN, payload: { ... })
capture = request_response(client, type: EXT_CAPTURE, payload: { ... })
audio   = request_response(client, type: EXT_DEMODULATE, payload: {
  iq_artifact_id: capture.payload[:artifact_id], ...
})
```

The IQ buffer never travels inline — it lives at an `artifact_id`
the demodulate call references. The runtime advertises which
extension messages it accepts; clients refuse the session if the
required set isn't covered.

## ARCP primitives

- Extension naming `arcpx.<domain>.<name>.v<n>` — RFC §21.1.
- Capability advertisement — §7, §21.2.
- Unknown-message handling, optional vs required — §21.3.
- Artifacts for IQ + PCM — §16.
- `UNIMPLEMENTED` / `NOT_FOUND` — §18.2.

## File tour

- `main.rb` — client side: tune, gain, capture, demodulate, then one
  optional unknown for §21.3.

## Variations

- `arcpx.sdr.spectrum.v1` returning a windowed FFT artifact for
  panadapter UIs.
- Stream demodulated audio as `kind: binary` chunks (sidecar frames,
  §11.3) instead of returning a single artifact.
- Promote `arcpx.sdr.*` to `arcpx.radio.v2` once stabilized; keep the
  v1 namespace working per §21.4.

## Spec ambiguity

§21.3 prescribes optional-vs-required behavior in prose but the
envelope schema does not reserve `extensions.optional`. This example
uses `extensions['optional'] = true` as the marker.
