# frozen_string_literal: true

require_relative '../_harness'

module CancelSample
  module Client
    def self.run(client)
      handle = client.submit_job(agent: 'sleepy')
      Async::Task.current.sleep(0.05)
      handle.cancel(client: client, reason: 'user requested stop')
      error =
        begin
          handle.get_result(client: client)
          nil
        rescue Arcp::Errors::Cancelled => e
          e
        end
      [handle, error]
    end
  end
end
