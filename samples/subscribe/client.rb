# frozen_string_literal: true

require_relative '../_harness'

module SubscribeSample
  module Client
    def self.run(client_a, client_b)
      handle = client_a.submit_job(agent: 'worker')
      observer = client_b.subscribe_job(job_id: handle.job_id, history: true, from_event_seq: 0).take(3)
      [handle, observer.to_a]
    end
  end
end
