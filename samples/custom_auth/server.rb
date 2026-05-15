# frozen_string_literal: true

require 'openssl'
require_relative '../_harness'

module CustomAuthSample
  SECRET = 'shhh'

  class HmacAuth
    include Arcp::Auth::AuthScheme

    def verify(token)
      return nil if token.nil?

      principal, signature = token.split(':', 2)
      return nil if principal.nil? || signature.nil?

      expected = OpenSSL::HMAC.hexdigest('SHA256', SECRET, principal)
      return nil unless secure_compare(expected, signature)

      Arcp::Auth::Principal.new(id: principal, name: principal, scopes: [].freeze)
    end

    private

    def secure_compare(a, b)
      return false unless a.bytesize == b.bytesize

      a.bytes.zip(b.bytes).reduce(0) { |acc, (x, y)| acc | (x ^ y) }.zero?
    end
  end

  HANDLER = ->(ctx) { ctx.finish(result: { 'principal' => 'authenticated' }) }

  def self.runtime
    r = Arcp::Runtime::Runtime.new(
      auth_verifier: HmacAuth.new, heartbeat_interval_sec: nil
    )
    r.register_agent(name: 'echo', versions: ['1.0.0'], default: '1.0.0', handler: HANDLER)
    r
  end

  def self.signed_token(principal)
    sig = OpenSSL::HMAC.hexdigest('SHA256', SECRET, principal)
    "#{principal}:#{sig}"
  end
end
