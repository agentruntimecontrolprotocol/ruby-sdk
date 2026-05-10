# frozen_string_literal: true

require 'arcp/capabilities'
require 'arcp/error'
require 'arcp/error_code'
require 'arcp/extensions'
require 'arcp/ids'
require 'arcp/messages/session'

module Arcp
  module Runtime
    # Server-side session record produced by a successful handshake (§8, §9).
    SessionRecord = Data.define(
      :session_id, :principal, :auth_scheme, :client, :capabilities,
      :runtime_identity, :extension_registry, :state
    ) do
      def authenticated? = state == :authenticated
      def closed?        = state == :closed
    end

    # Drives the four-step session handshake.
    #
    # The negotiator is a pure state machine: it consumes incoming
    # envelopes, returns a list of envelopes to send, and produces a
    # final `SessionRecord` when the handshake completes.
    class SessionNegotiator
      attr_reader :state

      # @param session_id [Arcp::SessionId]
      # @param runtime_identity [Hash] runtime identity block
      # @param runtime_capabilities [Hash]
      # @param schemes [Hash{String => #authenticate}] keyed by scheme name
      def initialize(session_id:, runtime_identity:, runtime_capabilities:, schemes:)
        @session_id = session_id
        @runtime_identity = runtime_identity
        @runtime_capabilities = Capabilities.normalize(runtime_capabilities)
        @schemes = schemes
        @state = :unauthenticated
        @open_payload = nil
        @result = nil
      end

      # Process an inbound envelope. Returns a Hash with:
      #   :outbound — Array of payloads to wrap in envelopes and send
      #   :record   — the SessionRecord (only when state becomes :authenticated)
      #
      # @param envelope [Arcp::Envelope]
      # @return [Hash{Symbol=>Object}]
      def receive(envelope)
        case envelope.payload
        in Messages::Session::Open => open
          handle_open(open)
        in Messages::Session::Authenticate => authn
          handle_authenticate(authn)
        in Messages::Session::Close
          handle_close
        else
          raise Arcp::Error::FailedPrecondition, "unexpected message during handshake: #{envelope.type}"
        end
      end

      private

      def handle_open(open)
        @open_payload = open
        @state = :authenticating
        scheme_name = (open.auth['scheme'] || open.auth[:scheme]).to_s

        if scheme_name == 'none'
          handle_none_scheme(open)
        elsif @schemes.key?(scheme_name)
          authenticate_inline(scheme_name, open)
        else
          { outbound: [unimplemented_scheme_rejection(scheme_name)] }
        end
      end

      def handle_none_scheme(open)
        client_caps = Capabilities.normalize(open.capabilities)
        if client_caps[:anonymous] && @runtime_capabilities[:anonymous]
          accept(Auth::Identity.new(scheme: 'none', principal: 'anonymous', attributes: {}.freeze), open)
        else
          { outbound: [reject(ErrorCode::UNAUTHENTICATED, 'anonymous access not negotiated')] }
        end
      end

      def authenticate_inline(scheme_name, open)
        identity = @schemes.fetch(scheme_name).authenticate(open.auth, open.client)
        accept(identity, open)
      rescue Arcp::Error::Unauthenticated => e
        { outbound: [reject(ErrorCode::UNAUTHENTICATED, e.message)] }
      end

      def handle_authenticate(_authn)
        # Phase 0.1: challenge-response is not used by current schemes.
        # Inline `session.open` carries the proof. If a future scheme
        # needs a challenge, it slots in here.
        { outbound: [reject(ErrorCode::FAILED_PRECONDITION, 'unexpected session.authenticate')] }
      end

      def handle_close
        @state = :closed
        { outbound: [] }
      end

      def accept(identity, open)
        negotiated = Capabilities.negotiate(open.capabilities, @runtime_capabilities)
        ext_registry = ExtensionRegistry.new(advertised: negotiated[:extensions])
        @result = SessionRecord.new(
          session_id: @session_id,
          principal: identity.principal,
          auth_scheme: identity.scheme,
          client: open.client,
          capabilities: negotiated,
          runtime_identity: @runtime_identity,
          extension_registry: ext_registry,
          state: :authenticated
        )
        @state = :authenticated
        { outbound: [accepted_payload(negotiated)], record: @result }
      end

      def accepted_payload(capabilities)
        Messages::Session::Accepted.new(
          session_id: @session_id.value,
          runtime: @runtime_identity,
          capabilities: capabilities.to_h,
          lease: nil
        )
      end

      def reject(code, message)
        @state = :closed
        Messages::Session::Rejected.new(code: code, message: message, details: nil)
      end

      def unimplemented_scheme_rejection(scheme_name)
        Messages::Session::Rejected.new(
          code: ErrorCode::UNIMPLEMENTED,
          message: "auth scheme not implemented: #{scheme_name}",
          details: { section: '§8.2', scheme: scheme_name }
        )
      end
    end
  end
end
