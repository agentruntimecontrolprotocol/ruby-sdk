# frozen_string_literal: true

module Arcp
  module Session
    JobsResponse = Data.define(:jobs, :next_cursor) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(jobs: Array(h['jobs']).map(&:freeze).freeze, next_cursor: h['next_cursor'])
      end

      def to_h
        out = { 'jobs' => jobs }
        out['next_cursor'] = next_cursor if next_cursor
        out
      end
    end
  end
end
