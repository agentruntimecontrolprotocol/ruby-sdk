# frozen_string_literal: true

require_relative '../_harness'

module LeaseViolationSample
  module Client
    def self.run(client)
      handle = client.submit_job(
        agent: 'auditor',
        lease_request: Arcp::Lease::LeaseRequest.new(capabilities: ['fs.read'], budget: nil, expires_at: nil)
      )
      events = handle.subscribe(client: client).to_a
      result = handle.get_result(client: client)
      [handle, events, result]
    end
  end
end
