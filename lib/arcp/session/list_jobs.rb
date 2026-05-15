# frozen_string_literal: true

module Arcp
  module Session
    ListJobs = Data.define(:filter, :limit, :cursor) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(filter: h['filter'] || {}, limit: h['limit'], cursor: h['cursor'])
      end

      def to_h
        out = { 'filter' => filter || {} }
        out['limit'] = limit if limit
        out['cursor'] = cursor if cursor
        out
      end
    end
  end
end
