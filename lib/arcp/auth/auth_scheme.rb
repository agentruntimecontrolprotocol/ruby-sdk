# frozen_string_literal: true

require 'arcp/error'

module Arcp
  module Auth
    # Identity verified by an auth scheme.
    Identity = Data.define(:scheme, :principal, :attributes)

    # Abstract auth scheme.
    #
    # Implementations validate the auth block and either return an
    # `Identity` or raise an `Arcp::Error::Unauthenticated`.
    module Scheme
      def self.included(base)
        base.extend(ClassMethods)
      end

      # @return [String] the wire scheme name (`bearer`, `signed_jwt`, ...)
      def scheme_name
        raise NotImplementedError
      end

      # @param auth [Hash] the auth payload from session.open
      # @param client [Hash] the client identity block from session.open
      # @return [Arcp::Auth::Identity]
      # @raise [Arcp::Error::Unauthenticated]
      def authenticate(auth, client)
        raise NotImplementedError
      end

      module ClassMethods
        def scheme_name
          name.split('::').last.downcase
        end
      end
    end
  end
end
