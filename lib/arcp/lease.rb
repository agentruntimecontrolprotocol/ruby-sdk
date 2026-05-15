# frozen_string_literal: true

require 'bigdecimal'
require 'time'

require_relative 'errors'

module Arcp
  module Lease
    LeaseConstraints = Data.define(:expires_at, :max_budget) do
      def self.from_h(h)
        return nil if h.nil?

        h = h.transform_keys(&:to_s)
        new(expires_at: h['expires_at'], max_budget: h['max_budget'])
      end

      def to_h
        out = {}
        out['expires_at'] = expires_at if expires_at
        out['max_budget'] = max_budget if max_budget
        out
      end

      def validate!
        return if expires_at.nil?

        t = Time.iso8601(expires_at)
        raise Arcp::Errors::InvalidRequest, "expires_at must be UTC (use 'Z'): #{expires_at}" unless t.utc?
      end
    end

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

    class BudgetCounter
      attr_reader :remaining

      def initialize(initial:)
        @remaining = initial.dup
      end

      def try_decrement(currency, amount)
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

    LeaseRequest = Data.define(:capabilities, :budget, :expires_at) do
      def self.from_h(h)
        return nil if h.nil?

        h = h.transform_keys(&:to_s)
        new(
          capabilities: Array(h['capabilities']).freeze,
          budget: h['cost.budget'] ? CostBudget.parse(h['cost.budget']) : nil,
          expires_at: h['expires_at']
        )
      end

      def to_h
        out = { 'capabilities' => capabilities }
        out['cost.budget'] = budget.to_a if budget
        out['expires_at']  = expires_at if expires_at
        out
      end
    end

    Lease = Data.define(:id, :capabilities, :budget, :expires_at, :issued_at) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(
          id: h.fetch('id'),
          capabilities: Array(h['capabilities']).freeze,
          budget: h['cost.budget'] ? CostBudget.parse(h['cost.budget']) : nil,
          expires_at: h['expires_at'],
          issued_at: h['issued_at']
        )
      end

      def to_h
        out = { 'id' => id, 'capabilities' => capabilities, 'issued_at' => issued_at }
        out['cost.budget'] = budget.to_a if budget
        out['expires_at']  = expires_at if expires_at
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

        Lease.new(
          id: Arcp::Ids.session_id.sub(/^ses_/, 'lse_'),
          capabilities: request.capabilities,
          budget: budget,
          expires_at: request.expires_at || parent.expires_at,
          issued_at: Time.now.utc.iso8601
        )
      end
    end
  end
end
