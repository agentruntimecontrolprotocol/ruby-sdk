# frozen_string_literal: true

require_relative '../_harness'

module ProgressSample
  module Client
    def self.run(client)
      handle = client.submit_job(agent: 'indexer')
      progress = handle.subscribe(client: client).select { _1.kind == Arcp::Job::EventKind::PROGRESS }
      [handle, progress.to_a]
    end
  end
end
