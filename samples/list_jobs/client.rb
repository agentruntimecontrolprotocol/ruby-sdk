# frozen_string_literal: true

require_relative '../_harness'

module ListJobsSample
  module Client
    def self.run(client, count:)
      handles = count.times.map { client.submit_job(agent: 'echo') }
      handles.each do |h|
        h.subscribe(client: client).to_a
        h.get_result(client: client)
      end
      pages = client.list_jobs(limit: 2).first(count)
      [handles, pages]
    end
  end
end
