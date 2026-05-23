# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('email_vendor_leases') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = EmailVendorLeasesRecipe.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'email-vendor-leases')

  handle, events, result = EmailVendorLeasesRecipe::Client.run(client)
  denied = events.select { |e| e.kind == Arcp::Job::EventKind::TOOL_RESULT && e.body.error }
  parsed = events.select { |e| e.kind.to_s.start_with?('x-vendor.acme.email.parsed') }

  emit.call(
    'job_id' => handle.job_id,
    'final_status' => result.final_status,
    'denied_tool_calls' => denied.map { |e| e.body.error['code'] },
    'parsed_emails' => parsed.size,
    'drafted_reply_present' => !result.result.dig('drafted_reply').to_s.empty?,
    'sent' => result.result.dig('sent')
  )
  client.close
  task.stop
end
exit code
