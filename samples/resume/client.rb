# frozen_string_literal: true

require_relative '../_harness'

module ResumeSample
  module Client
    def self.run(client)
      handle = client.submit_job(agent: 'echo')
      handle.subscribe(client: client).to_a
      result = handle.get_result(client: client)
      token = client.session.resume_token
      [handle, result, token]
    end
  end
end
