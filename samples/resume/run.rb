# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

# Resume in this in-process demo is a token rotation check; a full
# resume across separate processes lives in spec/integration/.
code = Harness.run_or_exit('resume') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = ResumeSample.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'resume')

  handle, _result, token = ResumeSample::Client.run(client)
  emit.call(
    'job_id' => handle.job_id,
    'resume_token_present' => !token.nil?,
    'resume_window_sec' => client.session.resume_window_sec
  )
  client.close
  task.stop
end
exit code
