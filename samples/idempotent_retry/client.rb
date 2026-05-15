# frozen_string_literal: true

require_relative '../_harness'

module IdempotentRetrySample
  module Client
    def self.run(client)
      first = client.submit_job(agent: 'echo', idempotency_key: 'KEY-1', input: { 'a' => 1 })
      second = client.submit_job(agent: 'echo', idempotency_key: 'KEY-1', input: { 'a' => 1 })
      conflict = begin
        client.submit_job(agent: 'other', idempotency_key: 'KEY-1', input: { 'a' => 1 })
        nil
      rescue Arcp::Errors::DuplicateKey => e
        e
      end
      [first, second, conflict]
    end
  end
end
