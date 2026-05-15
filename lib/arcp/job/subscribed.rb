# frozen_string_literal: true

module Arcp
  module Job
    Subscribed = Data.define(:job_id, :subscribed_from) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(job_id: h.fetch('job_id'), subscribed_from: h.fetch('subscribed_from'))
      end

      def to_h = { 'job_id' => job_id, 'subscribed_from' => subscribed_from }
    end
  end
end
