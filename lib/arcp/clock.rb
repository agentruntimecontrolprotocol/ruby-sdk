# frozen_string_literal: true

require 'time'

module Arcp
  module Clock
    module_function

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    def now = Time.now.utc
  end

  class SystemClock
    def now = Time.now.utc
    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  class FakeClock
    attr_accessor :now_value, :monotonic_value

    def initialize(now: Time.utc(2026, 1, 1))
      @now_value = now.utc
      @monotonic_value = 0.0
    end

    def now = @now_value
    def monotonic = @monotonic_value

    def advance(seconds)
      @now_value += seconds
      @monotonic_value += seconds
      self
    end
  end
end
