# frozen_string_literal: true

module Arcp
  module Job
    Unsubscribe = Data.define(:job_id) do
      def self.from_h(h) = new(job_id: h.transform_keys(&:to_s).fetch('job_id'))
      def to_h = { 'job_id' => job_id }
    end
  end
end
