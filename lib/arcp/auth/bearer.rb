# frozen_string_literal: true

module Arcp
  module Auth
    # Static-token bearer verifier. Maps token strings to Principals.
    # For production, plug a custom verifier implementing
    # `#verify(token) -> Principal | nil`.
    class Bearer
      include AuthScheme

      def initialize(tokens: {})
        @tokens = tokens.dup.freeze
      end

      def verify(token)
        return nil if token.nil?

        principal = @tokens[token]
        return nil unless principal

        case principal
        when Principal then principal
        when String then Principal.new(id: principal, name: principal, scopes: [].freeze)
        when Hash
          Principal.new(
            id: principal[:id] || principal['id'],
            name: principal[:name] || principal['name'],
            scopes: Array(principal[:scopes] || principal['scopes']).freeze
          )
        end
      end

      def self.from_token(token, principal_id: 'anonymous', scopes: [])
        new(tokens: { token => Principal.new(id: principal_id, name: principal_id, scopes: scopes.freeze) })
      end
    end
  end
end
