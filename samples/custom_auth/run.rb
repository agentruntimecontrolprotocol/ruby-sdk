# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('custom_auth') do |emit|
  runtime = CustomAuthSample.runtime

  ok_server, ok_client = Harness.pair_memory
  ok_task = Async { runtime.accept(ok_server) }
  good_client = CustomAuthSample::Client.try_open(ok_client, token: CustomAuthSample.signed_token('alice'))

  bad_server, bad_client = Harness.pair_memory
  bad_task = Async { runtime.accept(bad_server) }
  bad_error = begin
    CustomAuthSample::Client.try_open(bad_client, token: 'mallory:wrongsig')
    nil
  rescue Arcp::Errors::Unauthenticated => e
    e
  end

  emit.call(
    'good_session' => good_client.session.id,
    'bad_rejected' => !bad_error.nil?,
    'bad_code' => bad_error&.code
  )
  good_client.close
  ok_task.stop
  bad_task.stop
end
exit code
