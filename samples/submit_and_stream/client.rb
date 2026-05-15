# frozen_string_literal: true

require_relative '../_harness'

module SubmitAndStream
  module Client
    def self.run(client)
      handle = client.submit_job(agent: 'echo', input: { 'msg' => 'hi' })
      events = handle.subscribe(client: client).to_a
      result = handle.get_result(client: client)
      [handle, events, result]
    end
  end
end
