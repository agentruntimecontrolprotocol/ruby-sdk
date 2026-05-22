# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('provisioned_credentials') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = ProvisionedCredentialsSample.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'provisioned-credentials')

  handle, result = ProvisionedCredentialsSample::Client.run(client)
  emit.call(
    'job_id' => handle.job_id,
    'result' => result.result,
    'credentials' => handle.credentials.map(&:to_redacted_h),
    'revoked' => ProvisionedCredentialsSample.provisioner.revoked
  )
  client.close
  task.stop
end
exit code
