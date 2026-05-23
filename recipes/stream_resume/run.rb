# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

# Resume in this in-process demo is a token rotation + chunk reassembly check.
# A full mid-stream-resume across separate processes lives in
# spec/integration/. The recipe captures `resume_token` and the chunk dict
# so a follow-up `Arcp::Client.open(transport: t2, auth: ...,
# resume: Arcp::Session::Resume.new(session_id:, resume_token:,
# last_event_seq:))` could replay the tail past the cutoff.
code = Harness.run_or_exit('stream_resume') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = StreamResumeRecipe.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'stream-resume')

  handle, chunks, assembled, result = StreamResumeRecipe::Client.run(client)

  emit.call(
    'job_id' => handle.job_id,
    'final_status' => result.final_status,
    'chunk_count' => chunks.size,
    'assembled_bytes' => assembled.bytesize,
    'result_size' => result.result_size,
    'resume_token_present' => !client.session.resume_token.nil?,
    'resume_window_sec' => client.session.resume_window_sec
  )
  client.close
  task.stop
end
exit code
