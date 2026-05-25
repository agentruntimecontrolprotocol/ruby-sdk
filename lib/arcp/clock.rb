# frozen_string_literal: true

require 'time'

module Arcp
  # Clock abstraction used by the runtime and tests.
  module Clock
    module_function

    # Current monotonic time in seconds.
    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    # Current wall-clock time in UTC.
    def now = Time.now.utc
  end

  # Real clock wrapper for components that need an object.
  class SystemClock
    # Current wall-clock time in UTC.
    def now = Time.now.utc
    # Current monotonic time in seconds.
    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Deterministic clock used in tests.
  class FakeClock
    attr_accessor :now_value, :monotonic_value

    # Start at a specific UTC instant and advance manually in tests.
    def initialize(now: Time.utc(2026, 1, 1))
      @now_value = now.utc
      @monotonic_value = 0.0
    end

    # Current wall-clock time in UTC.
    def now = @now_value
    # Current monotonic time in seconds.
    def monotonic = @monotonic_value

    # Advance both wall-clock and monotonic time by `seconds`.
    def advance(seconds)
      @now_value += seconds
      @monotonic_value += seconds
      self
    end
  end
end
