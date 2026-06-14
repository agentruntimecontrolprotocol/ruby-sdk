# frozen_string_literal: true

module Arcp
  module Runtime
    # Tracks per-job leases and bound budget counters. The runtime asks
    # `#check!(job_id, capability:)` before every authority op.
    class LeaseManager
      def initialize(clock: Arcp::SystemClock.new, enforce_model_use: false)
        @clock = clock
        @enforce_model_use = enforce_model_use
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

      def check_model!(job_id, model_id:)
        lease = get(job_id)
        return true if lease.nil? && !@enforce_model_use

        return true if lease&.model_use && Arcp::ModelPattern.match?(lease.model_use, model_id)

        raise Arcp::Errors::PermissionDenied.new(
          "model #{model_id.inspect} not permitted by lease",
          details: { 'model' => model_id, 'lease_id' => lease&.id }
        )
      end

      # Try to decrement the bound budget. Returns true on success, raises
      # BudgetExhausted if the requested currency is absent from the budget
      # or has insufficient balance. Jobs with no lease or no budget at all
      # remain unrestricted. Straight-line — no scheduler-yielding calls
      # between read and write.
      def try_spend!(job_id, currency, amount)
        if amount.nil? || amount.negative?
          raise Arcp::Errors::InvalidRequest.new(
            "budget amount must be non-negative: #{amount.inspect}",
            details: { 'currency' => currency, 'amount' => amount&.to_s }
          )
        end

        counter = self.counter(job_id)
        return true if counter.nil?
        return true if counter.remaining.empty?

        unless counter.try_decrement(currency, amount)
          message = if counter.remaining.key?(currency)
                      "budget #{currency} exhausted"
                    else
                      "currency #{currency} not in budget"
                    end
          raise Arcp::Errors::BudgetExhausted.new(
            message,
            details: { 'currency' => currency, 'remaining' => counter.get(currency).to_s('F') }
          )
        end
        true
      end

      # Spec §9.6: decrement the budgeted currency by a reported cost.* metric
      # value. Negative values are rejected (no decrement). The counter clamps
      # at zero; subsequent operations see exhaustion via {#budget_exhausted!}.
      def record_cost(job_id, currency, amount)
        if amount.nil? || amount.negative?
          raise Arcp::Errors::InvalidRequest.new(
            "cost amount must be non-negative: #{amount.inspect}",
            details: { 'currency' => currency, 'amount' => amount&.to_s }
          )
        end

        counter = self.counter(job_id)
        counter&.spend(currency, amount)
      end

      # Spec §9.6 enforcement: raise BUDGET_EXHAUSTED if any of the job's
      # budget counters is depleted. Jobs with no lease/budget are unrestricted.
      def budget_exhausted!(job_id)
        counter = self.counter(job_id)
        return if counter.nil?

        exhausted = counter.exhausted_currencies
        return if exhausted.empty?

        raise Arcp::Errors::BudgetExhausted.new(
          "budget exhausted for: #{exhausted.inspect}",
          details: { 'currencies' => exhausted }
        )
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
