# frozen_string_literal: true

require_relative '../_harness'

module StdioSample
  module Client
    def self.run(stdin_pipe, stdout_pipe)
      transport = Arcp::Transport::StdioTransport.new(input: stdout_pipe, output: stdin_pipe)
      client = Arcp::Client.open(transport: transport, auth: { 'token' => 'demo' }, client_name: 'stdio')
      handle = client.submit_job(agent: 'echo', input: { 'msg' => 'over stdio' })
      handle.subscribe(client: client).to_a
      result = handle.get_result(client: client)
      client.close
      [handle, result]
    end
  end
end
