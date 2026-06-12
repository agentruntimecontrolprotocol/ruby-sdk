# frozen_string_literal: true

require 'bigdecimal'
require 'time'

require_relative 'errors'
require_relative 'credential'

module Arcp
  module Lease
    # Immutable lease bounds attached to a job request or granted lease.
    # `max_budget` is a {CostBudget} expressing the maximum per-currency
    # amount that a requested lease budget may declare for this job; it
    # accepts the same shape as `cost.budget` (a list of `"CCY:amount"`
    # entries) or a pre-parsed {CostBudget}.
    LeaseConstraints = Data.define(:expires_at, :max_budget) do
      def initialize(expires_at: nil, max_budget: nil)
        super(expires_at: expires_at, max_budget: self.class.parse_max_budget(max_budget))
      end

      def self.from_h(h)
        return nil if h.nil?

        h = h.transform_keys(&:to_s)
        new(expires_at: h['expires_at'], max_budget: h['max_budget'])
      end

      def self.parse_max_budget(value)
        case value
        when nil then nil
        when CostBudget then value
        when Array then CostBudget.parse(value)
        when Hash
          h = value.transform_keys(&:to_s)
          CostBudget.parse(h['cost.budget'] || h.values_at(*h.keys).flatten)
        else
          raise Arcp::Errors::InvalidRequest,
                "max_budget must be a list of 'CCY:amount' entries or a CostBudget"
        end
      end

      def to_h
        out = {}
        out['expires_at'] = expires_at if expires_at
        out['max_budget'] = max_budget.to_a if max_budget
        out
      end

      def validate!
        unless expires_at.nil?
          t = Time.iso8601(expires_at)
          raise Arcp::Errors::InvalidRequest, "expires_at must be UTC (use 'Z'): #{expires_at}" unless t.utc?
        end

        validate_max_budget!
      end

      # Raises {Arcp::Errors::LeaseSubsetViolation} if a requested lease
      # budget exceeds the per-currency caps declared in `max_budget`.
      # A request that omits a currency declared in `max_budget` is allowed.
      def enforce_max_budget!(requested_budget)
        return if max_budget.nil?
        return if requested_budget.nil?

        offending = requested_budget.per_currency.filter_map do |ccy, amt|
          cap = max_budget.per_currency[ccy]
          ccy if cap.nil? || amt > cap
        end
        return if offending.empty?

        raise Arcp::Errors::LeaseSubsetViolation.new(
          "lease budget exceeds lease_constraints max_budget for: #{offending.inspect}",
          details: { 'currencies' => offending }
        )
      end

      private

      def validate_max_budget!
        return if max_budget.nil?
        return if max_budget.is_a?(CostBudget)

        raise Arcp::Errors::InvalidRequest,
              'max_budget must be a CostBudget after parsing'
      end
    end

    # A currency-indexed budget that round-trips on the wire as strings.
    CostBudget = Data.define(:per_currency) do
      def self.parse(entries)
        h = {}
        Array(entries).each do |entry|
          ccy, amount = entry.to_s.split(':', 2)
          if ccy.nil? || amount.nil?
            raise Arcp::Errors::InvalidRequest,
                  "malformed budget entry: #{entry.inspect}"
          end

          h[ccy] = BigDecimal(amount)
        end
        new(per_currency: h.freeze)
      end

      def to_a = per_currency.map { |ccy, amt| "#{ccy}:#{amt.to_s('F')}" }
      def to_h = { 'cost.budget' => to_a }

      def remaining(currency) = per_currency[currency] || BigDecimal('0')
      def currencies = per_currency.keys
    end

    # Mutable counter used to track spent budget for a live job.
    class BudgetCounter
      attr_reader :remaining

      def initialize(initial:)
        @remaining = initial.dup
      end

      def try_decrement(currency, amount)
        return false if amount.nil? || amount.negative?

        balance = @remaining[currency]
        return false if balance.nil?
        return false if balance < amount

        @remaining[currency] = balance - amount
        true
      end

      def get(currency) = @remaining[currency] || BigDecimal('0')
      def negative?(currency) = (@remaining[currency] || BigDecimal('0')).negative?

      def snapshot
        @remaining.transform_values(&:dup).freeze
      end
    end

    # Lease request supplied when submitting a job.
    LeaseRequest = Data.define(:capabilities, :budget, :model_use, :expires_at) do
      def initialize(capabilities:, budget: nil, model_use: nil, expires_at: nil)
        super(
          capabilities: Array(capabilities).freeze,
          budget: budget,
          model_use: model_use ? Array(model_use).freeze : nil,
          expires_at: expires_at
        )
      end

      def self.from_h(h)
        return nil if h.nil?

        h = h.transform_keys(&:to_s)
        new(
          capabilities: Array(h['capabilities']).freeze,
          budget: h['cost.budget'] ? CostBudget.parse(h['cost.budget']) : nil,
          model_use: h['model.use'] ? Array(h['model.use']).freeze : nil,
          expires_at: h['expires_at']
        )
      end

      def to_h
        out = { 'capabilities' => capabilities }
        out['cost.budget'] = budget.to_a if budget
        out['model.use'] = model_use if model_use
        out['expires_at'] = expires_at if expires_at
        out
      end
    end

    # Lease granted to a job after submission is accepted.
    Lease = Data.define(:id, :capabilities, :budget, :model_use, :expires_at, :issued_at) do
      def initialize(id:, capabilities:, issued_at:, budget: nil, model_use: nil, expires_at: nil)
        super(
          id: id,
          capabilities: Array(capabilities).freeze,
          budget: budget,
          model_use: model_use ? Array(model_use).freeze : nil,
          expires_at: expires_at,
          issued_at: issued_at
        )
      end

      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(
          id: h.fetch('id'),
          capabilities: Array(h['capabilities']).freeze,
          budget: h['cost.budget'] ? CostBudget.parse(h['cost.budget']) : nil,
          model_use: h['model.use'] ? Array(h['model.use']).freeze : nil,
          expires_at: h['expires_at'],
          issued_at: h['issued_at']
        )
      end

      def to_h
        out = { 'id' => id, 'capabilities' => capabilities, 'issued_at' => issued_at }
        out['cost.budget'] = budget.to_a if budget
        out['model.use'] = model_use if model_use
        out['expires_at'] = expires_at if expires_at
        out
      end

      def expired?(now)
        return false if expires_at.nil?

        Time.iso8601(expires_at) <= now
      end
    end

    module Subsetting
      module_function

      # Compute a delegate lease bounded by the parent. Raises
      # `LeaseSubsetViolation` if requested capabilities exceed parent,
      # requested expires_at is beyond parent, or remaining budget can't
      # cover the requested amount.
      def bound(parent:, request:, parent_remaining: nil)
        excess = request.capabilities - parent.capabilities
        unless excess.empty?
          raise Arcp::Errors::LeaseSubsetViolation,
                "child lease capabilities not in parent: #{excess.inspect}"
        end

        if request.expires_at && parent.expires_at
          parent_t = Time.iso8601(parent.expires_at)
          req_t = Time.iso8601(request.expires_at)
          if req_t > parent_t
            raise Arcp::Errors::LeaseSubsetViolation,
                  "child expires_at #{request.expires_at} exceeds parent #{parent.expires_at}"
          end
        end

        budget = nil
        if request.budget
          parent_pc = parent_remaining || (parent.budget&.per_currency || {})
          missing = request.budget.per_currency.filter_map do |ccy, amt|
            available = parent_pc[ccy] || BigDecimal('0')
            (ccy if amt > available)
          end
          unless missing.empty?
            raise Arcp::Errors::LeaseSubsetViolation,
                  "child budget exceeds parent remaining for: #{missing.inspect}"
          end

          budget = request.budget
        end

        model_use = bound_model_use(parent: parent, request: request)

        Lease.new(
          id: Arcp::Ids.session_id.sub(/^ses_/, 'lse_'),
          capabilities: request.capabilities,
          budget: budget,
          model_use: model_use,
          expires_at: request.expires_at || parent.expires_at,
          issued_at: Time.now.utc.iso8601
        )
      end

      def bound_model_use(parent:, request:)
        return nil unless request.model_use

        unless request.model_use.all? { |pattern| Arcp::ModelPattern.implied_by?(parent.model_use, pattern) }
          raise Arcp::Errors::LeaseSubsetViolation,
                "child model.use expands beyond parent: #{request.model_use.inspect}"
        end

        request.model_use
      end
    end
  end
end
