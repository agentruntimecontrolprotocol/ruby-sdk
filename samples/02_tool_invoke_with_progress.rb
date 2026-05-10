#!/usr/bin/env ruby
# frozen_string_literal: true

# Sample 02 — Tool invocation with streamed progress.
#
# Registers a `summarize` tool that emits progress events and a text stream
# of partial output, then invokes it from the client and prints each event.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'arcp'
require 'async'

CLIENT_IDENTITY = {
  kind: 'arcp-sample-02',
  version: Arcp::IMPL_VERSION,
  fingerprint: 'sha256:dev'
}.freeze

Sync do
  client_side, runtime_side = Arcp::Transport::Memory.pair
  bearer = Arcp::Auth::Bearer.new(accept_any: true)
  runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
  runtime.register_tool('summarize') do |ctx, args|
    text = args[:text] || 'hello world'
    stream_id = ctx.streams.open(session_id: ctx.session_id, kind: 'text', content_type: 'text/plain')
    text.split.each_with_index do |word, idx|
      ctx.progress(percent: ((idx + 1) * 100 / text.split.size), message: word)
      ctx.streams.chunk(stream_id, content: "#{word} ")
    end
    ctx.streams.close(stream_id, reason: 'eos')
    { length: text.length, words: text.split.size }
  end
  Async { runtime.serve(runtime_side) }

  client = Arcp::Client::Client.new(transport: client_side)
  client.open(auth: { scheme: 'bearer', token: 'tok' }, client: CLIENT_IDENTITY)
  result = client.invoke(tool: 'summarize', arguments: { text: 'the quick brown fox jumps' })
  result.events.each do |env|
    puts "  #{env.type}: #{env.payload.to_h.inspect}"
  end
  puts "value=#{result.value.inspect}"
  client.close
end
