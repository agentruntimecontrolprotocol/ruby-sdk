# frozen_string_literal: true

require_relative '../_harness'

module AckBackpressureSample
  module Client
    def self.run(client)
      handle = client.submit_job(agent: 'producer')
      events = []
      handle.subscribe(client: client).each_with_index do |e, idx|
        events << e
        client.ack(idx) if (idx % 5).zero?
      end
      [handle, events]
    end
  end
end
