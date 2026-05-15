# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('vendor_extensions') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = VendorExtensionsSample.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'vendor-extensions')

  handle, vendor = VendorExtensionsSample::Client.run(client)
  emit.call(
    'job_id' => handle.job_id,
    'vendor_events' => vendor
  )
  client.close
  task.stop
end
exit code
