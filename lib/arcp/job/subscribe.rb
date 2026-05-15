# frozen_string_literal: true

module Arcp
  module Job
    Subscribe = Data.define(:job_id, :from_event_seq, :history) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(
          job_id: h.fetch('job_id'),
          from_event_seq: h['from_event_seq'],
          history: h.fetch('history', false)
        )
      end

      def to_h
        out = { 'job_id' => job_id, 'history' => history }
        out['from_event_seq'] = from_event_seq if from_event_seq
        out
      end
    end
  end
end
