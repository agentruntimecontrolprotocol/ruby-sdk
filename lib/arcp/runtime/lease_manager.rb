# frozen_string_literal: true

module Arcp
  module Runtime
    # Tracks per-job leases and bound budget counters. The runtime asks
    # `#check!(job_id, capability:)` before every authority op.
    class LeaseManager
      def initialize(clock: Arcp::SystemClock.new)
        @clock = clock
        @leases = {}
        @counters = {}
        @mutex = Mutex.new
      end

      def register(job_id, lease)
        @mutex.synchronize do
          @leases[job_id] = lease
          @counters[job_id] = Arcp::Lease::BudgetCounter.new(initial: lease.budget&.per_currency&.dup || {})
        end
        lease
      end

      def get(job_id) = @mutex.synchronize { @leases[job_id] }
      def counter(job_id) = @mutex.synchronize { @counters[job_id] }

      def check!(job_id, capability:)
        lease = get(job_id)
        return if lease.nil?

        if lease.expired?(@clock.now)
          raise Arcp::Errors::LeaseExpired.new(
            "lease #{lease.id} expired at #{lease.expires_at}",
            details: { 'lease_id' => lease.id }
          )
        end

        return if lease.capabilities.include?(capability)

        raise Arcp::Errors::PermissionDenied.new(
          "capability #{capability.inspect} not in lease #{lease.id}",
          details: { 'capability' => capability, 'lease_id' => lease.id }
        )
      end

      # Try to decrement the bound budget. Returns true on success, raises
      # BudgetExhausted if no balance covers the amount. Straight-line —
      # no scheduler-yielding calls between read and write.
      def try_spend!(job_id, currency, amount)
        counter = self.counter(job_id)
        return true if counter.nil?
        return true if counter.get(currency).zero? && !counter.remaining.key?(currency)

        unless counter.try_decrement(currency, amount)
          raise Arcp::Errors::BudgetExhausted.new(
            "budget #{currency} exhausted",
            details: { 'currency' => currency, 'remaining' => counter.get(currency).to_s('F') }
          )
        end
        true
      end

      def remaining(job_id)
        c = counter(job_id)
        c ? c.snapshot : {}
      end

      def revoke(job_id)
        @mutex.synchronize do
          @leases.delete(job_id)
          @counters.delete(job_id)
        end
      end
    end
  end
end
