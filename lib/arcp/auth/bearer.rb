# frozen_string_literal: true

require 'arcp/auth/auth_scheme'

module Arcp
  module Auth
    # Bearer token scheme (§8.2).
    #
    # @example
    #   bearer = Arcp::Auth::Bearer.new(
    #     tokens: { 'tok_alice' => 'alice@example.com' }
    #   )
    class Bearer
      include Scheme

      # @param tokens [Hash{String=>String}] mapping token => principal
      # @param accept_any [Boolean] if true, any non-empty token is
      #   accepted with the token itself as the principal. Useful in
      #   tests; should be false in production.
      def initialize(tokens: {}, accept_any: false)
        @tokens = tokens.dup.freeze
        @accept_any = accept_any
      end

      def scheme_name
        'bearer'
      end

      def authenticate(auth, _client)
        token = auth_token(auth)
        principal = lookup_principal(token)
        Identity.new(scheme: 'bearer', principal: principal, attributes: { token_prefix: token[0, 4] }.freeze)
      end

      private

      def auth_token(auth)
        token = auth['token'] || auth[:token]
        raise Arcp::Error::Unauthenticated, 'bearer token missing' if token.nil? || token.empty?

        token
      end

      def lookup_principal(token)
        return @tokens.fetch(token) if @tokens.key?(token)
        return token if @accept_any

        raise Arcp::Error::Unauthenticated, 'bearer token not recognized'
      end
    end
  end
end
