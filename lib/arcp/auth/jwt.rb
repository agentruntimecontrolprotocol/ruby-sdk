# frozen_string_literal: true

require 'jwt'

require 'arcp/auth/auth_scheme'

module Arcp
  module Auth
    # JWT scheme (§8.2: `signed_jwt`).
    #
    # The runtime never trusts the `alg` header from the token; the
    # caller passes a list of acceptable algorithms.
    #
    # @example
    #   Arcp::Auth::Jwt.new(secret: 'shh', algorithms: ['HS256'])
    class Jwt
      include Scheme

      # @param secret [String, OpenSSL::PKey::PKey] HMAC key or public key
      # @param algorithms [Array<String>] e.g. ['HS256']
      # @param audience [String, nil] required `aud` claim
      def initialize(secret:, algorithms: ['HS256'], audience: nil)
        @secret = secret
        @algorithms = algorithms.dup.freeze
        @audience = audience
      end

      def scheme_name
        'signed_jwt'
      end

      def authenticate(auth, _client)
        token = auth['token'] || auth[:token]
        raise Arcp::Error::Unauthenticated, 'signed_jwt token missing' if token.nil? || token.empty?

        decode_options = { algorithms: @algorithms, verify_aud: !@audience.nil?, aud: @audience }
        claims, _header = ::JWT.decode(token, @secret, true, decode_options)
        Identity.new(
          scheme: 'signed_jwt',
          principal: claims['sub'] || claims[:sub] || 'anonymous',
          attributes: claims.freeze
        )
      rescue ::JWT::DecodeError => e
        raise Arcp::Error::Unauthenticated, "signed_jwt invalid: #{e.message}"
      end
    end
  end
end
