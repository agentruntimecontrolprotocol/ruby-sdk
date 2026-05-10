# frozen_string_literal: true

module Arcp
  # Priority levels (§6.5).
  module Priority
    LOW      = 'low'
    NORMAL   = 'normal'
    HIGH     = 'high'
    CRITICAL = 'critical'

    ALL = [LOW, NORMAL, HIGH, CRITICAL].freeze

    RANK = { LOW => 0, NORMAL => 1, HIGH => 2, CRITICAL => 3 }.freeze

    # @param value [String]
    # @return [Boolean]
    def self.valid?(value)
      ALL.include?(value)
    end

    # @param left [String]
    # @param right [String]
    # @return [Integer] -1, 0, or 1
    def self.compare(left, right)
      RANK.fetch(left) <=> RANK.fetch(right)
    end

    # Whether `priority` meets `min_priority` per subscription filter (§13.2).
    #
    # @param priority [String]
    # @param min_priority [String]
    # @return [Boolean]
    def self.meets?(priority, min_priority)
      compare(priority, min_priority) >= 0
    end
  end
end
