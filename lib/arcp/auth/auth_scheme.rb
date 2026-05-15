# frozen_string_literal: true

module Arcp
  module Auth
    Principal = Data.define(:id, :name, :scopes)

    # AuthScheme is an interface: implementations expose
    #   `#verify(token) -> Principal | nil`
    # Returning nil rejects the credential; raise to surface errors.
    module AuthScheme
      def verify(_token)
        raise NotImplementedError
      end
    end
  end
end
