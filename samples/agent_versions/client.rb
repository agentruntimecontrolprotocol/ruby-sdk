# frozen_string_literal: true

require_relative '../_harness'

module AgentVersionsSample
  module Client
    def self.run(client)
      default = client.submit_job(agent: 'code-refactor')
      pinned  = client.submit_job(agent: 'code-refactor@1.0.0')

      missing = begin
        client.submit_job(agent: 'code-refactor@9.9.9')
        nil
      rescue Arcp::Errors::AgentVersionNotAvailable => e
        e
      end
      [default, pinned, missing]
    end
  end
end
