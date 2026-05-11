#!/usr/bin/env ruby
# frozen_string_literal: true

# SDR domain via custom `arcpx.sdr.*.v1` extension messages.
#
# Tune to 145.500 MHz (2 m FM calling), capture 5 s of IQ at 2.048 MS/s,
# NBFM-demodulate to 48 kHz PCM. Exercises §21 naming, capability
# advertisement, and unknown-message handling.

require 'arcp'
require 'async'
require 'securerandom'

EXT_TUNE = 'arcpx.sdr.tune.v1'
EXT_GAIN = 'arcpx.sdr.gain.v1'
EXT_CAPTURE = 'arcpx.sdr.capture.v1'
EXT_DEMODULATE = 'arcpx.sdr.demodulate.v1'
ALL_EXTENSIONS = [EXT_TUNE, EXT_GAIN, EXT_CAPTURE, EXT_DEMODULATE].freeze

def request_response(client, type:, payload:, extensions: nil)
  env = Arcp::Envelope.build(
    type: type, payload: payload, extensions: extensions,
    session_id: client.session_id
  )
  client.send_envelope(env)
  client.receive_envelope
end

Sync do
  # capabilities.extensions=ALL_EXTENSIONS on the open call.
  client = nil # ARCPClient(...)
  accepted = client.open

  # If the runtime didn't advertise our required extension set,
  # refuse the session — RFC §7 / §21.2.
  advertised = (accepted[:capabilities][:extensions] || []).to_set
  unless ALL_EXTENSIONS.to_set.subset?(advertised)
    raise Arcp::Error::Unimplemented.new(
      section: '§21.2', detail: "runtime missing SDR extensions: #{advertised.to_a.inspect}"
    )
  end

  handle = SecureRandom.hex(4)

  request_response(client, type: EXT_TUNE, payload: {
                     center_freq_hz: 145_500_000.0,
                     sample_rate_hz: 2_048_000.0,
                     ppm_correction: 1
                   })
  request_response(client, type: EXT_GAIN, payload: {
                     stages: [{ name: 'TUNER', value_db: 28.0 }]
                   })

  # Capture returns an artifact.ref pointing at the IQ buffer.
  # The buffer never travels inline — demodulate references it.
  cap = request_response(client, type: EXT_CAPTURE, payload: {
                           seconds: 5.0, capture_handle: handle, decimate: 1
                         })
  iq_artifact = cap.payload[:artifact_id] || cap.payload['artifact_id']
  puts "captured IQ -> #{iq_artifact}"

  audio = request_response(client, type: EXT_DEMODULATE, payload: {
                             iq_artifact_id: iq_artifact, mode: 'NBFM',
                             audio_rate_hz: 48_000
                           })
  puts "demod  PCM -> #{audio.payload[:artifact_id] || audio.payload['artifact_id']}"

  # §21.3 demonstration: unadvertised extension marked optional.
  # Runtime SHOULD ack (silent drop) rather than nack.
  optional = request_response(
    client, type: 'arcpx.sdr.experimental_doppler.v1',
            extensions: { 'optional' => true }, payload: { velocity_mps: 7.4 }
  )
  puts "optional unknown -> #{optional.type}"

  client.close
end
