# frozen_string_literal: true

require_relative '../_harness'

module CustomAuthSample
  module Client
    def self.try_open(transport, token:)
      Arcp::Client.open(
        transport: transport,
        auth: { 'scheme' => 'hmac', 'token' => token },
        client_name: 'custom-auth'
      )
    end
  end
end
