# frozen_string_literal: true

module Arcp
  module Job
    Submit = Data.define(
      :agent, :input, :lease_request, :lease_constraints,
      :idempotency_key, :max_runtime_sec
    ) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(
          agent: h.fetch('agent'),
          input: h['input'],
          lease_request: Arcp::Lease::LeaseRequest.from_h(h['lease_request']),
          lease_constraints: Arcp::Lease::LeaseConstraints.from_h(h['lease_constraints']),
          idempotency_key: h['idempotency_key'],
          max_runtime_sec: h['max_runtime_sec']
        )
      end

      def to_h
        out = { 'agent' => agent }
        out['input'] = input if input
        out['lease_request']     = lease_request.to_h if lease_request
        out['lease_constraints'] = lease_constraints.to_h if lease_constraints
        out['idempotency_key']   = idempotency_key if idempotency_key
        out['max_runtime_sec']   = max_runtime_sec if max_runtime_sec
        out
      end
    end
  end
end
