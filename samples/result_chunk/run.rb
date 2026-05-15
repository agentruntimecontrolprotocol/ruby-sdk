# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('result_chunk') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = ResultChunkSample.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'result-chunk')

  handle, chunks, assembled, result = ResultChunkSample::Client.run(client)

  emit.call(
    'job_id' => handle.job_id,
    'chunk_count' => chunks.size,
    'assembled_bytes' => assembled.bytesize,
    'result_id' => result.result_id,
    'result_size' => result.result_size,
    'sizes_match' => (result.result_size == assembled.bytesize)
  )
  client.close
  task.stop
end
exit code
