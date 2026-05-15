# frozen_string_literal: true

require 'time'
require_relative '../_harness'

module LeaseExpiresAtSample
  module Client
    def self.run(client)
      deadline = (Time.now.utc + 60).iso8601
      handle = client.submit_job(
        agent: 'auditor',
        lease_request: Arcp::Lease::LeaseRequest.new(capabilities: ['audit'], budget: nil, expires_at: deadline),
        lease_constraints: Arcp::Lease::LeaseConstraints.new(expires_at: deadline, max_budget: nil)
      )
      handle.subscribe(client: client).to_a
      error = begin
        handle.get_result(client: client)
        nil
      rescue Arcp::Errors::LeaseExpired => e
        e
      end
      [handle, deadline, error]
    end
  end
end
