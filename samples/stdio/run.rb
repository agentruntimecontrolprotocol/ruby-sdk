# frozen_string_literal: true

require_relative 'client'

code = Harness.run_or_exit('stdio') do |emit|
  stdin_r, stdin_w = IO.pipe
  stdout_r, stdout_w = IO.pipe

  server_path = File.expand_path('server.rb', __dir__)
  pid = Process.spawn('ruby', '-Ilib', server_path,
                      in: stdin_r, out: stdout_w, err: $stderr)
  stdin_r.close
  stdout_w.close

  handle, result = StdioSample::Client.run(stdin_w, stdout_r)

  begin
    Process.kill('TERM', pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  emit.call(
    'job_id' => handle.job_id,
    'result' => result.result
  )
end
exit code
