# frozen_string_literal: true

# StdioTransport server: reads NDJSON envelopes from stdin, writes
# replies to stdout. Spawned by run.rb as a child process.

require_relative '../_harness'

Sync do
  transport = Arcp::Transport::StdioTransport.new(input: $stdin, output: $stdout)
  runtime = Harness.runtime(agents: { 'echo' => ->(ctx) { ctx.finish(result: ctx.input) } })
  runtime.accept(transport).wait
end
