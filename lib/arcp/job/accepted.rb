# frozen_string_literal: true

require_relative '../credential'

module Arcp
  module Job
    Accepted = Data.define(:job_id, :agent, :accepted_at, :lease, :credentials) do
      def initialize(job_id:, agent:, accepted_at:, lease: nil, credentials: nil)
        super
      end

      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(
          job_id: h.fetch('job_id'),
          agent: h.fetch('agent'),
          accepted_at: h['accepted_at'],
          lease: h['lease'] ? Arcp::Lease::Lease.from_h(h['lease']) : nil,
          credentials: credentials_from(h)
        )
      end

      def to_h
        out = { 'job_id' => job_id, 'agent' => agent, 'accepted_at' => accepted_at }
        out['lease'] = lease.to_h if lease
        out['credentials'] = credentials.map(&:to_h) if credentials && !credentials.empty?
        out
      end

      def self.credentials_from(h)
        return nil unless h['credentials']

        Array(h['credentials']).map { |credential| Arcp::Credential.from_h(credential) }.freeze
      end
    end
  end
end
