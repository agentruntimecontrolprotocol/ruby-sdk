# frozen_string_literal: true

require 'json_schemer'

require 'arcp/envelope'
require 'arcp/error'
require 'arcp/error_code'
require 'arcp/ids'
require 'arcp/messages/human'
require 'arcp/messages/permissions'

module Arcp
  module Runtime
    # Per-session helper exposing high-level operations to tools:
    # human input requests, permission challenges, and lease use.
    class SessionHelper
      def initialize(runtime:, ctx:)
        @runtime = runtime
        @ctx = ctx
      end

      # Ask the human (via the client) for structured input.
      #
      # Validates the response against `response_schema`. If the
      # request expires before a response, falls back to `default`
      # when set; otherwise raises `Arcp::Error::DeadlineExceeded`.
      #
      # @param prompt [String]
      # @param response_schema [Hash, nil] JSON Schema
      # @param default [Object, nil]
      # @param expires_in_seconds [Numeric, nil]
      # @param job_id [Arcp::JobId, nil]
      # @return [Object] the validated value
      def request_human_input(prompt:, response_schema: nil, default: nil,
                              expires_in_seconds: nil, job_id: nil)
        request_id = MessageId.random
        expires_at = expires_in_seconds && (Time.now + expires_in_seconds).utc.iso8601(6)
        request = Messages::Human::InputRequest.new(
          prompt: prompt, response_schema: response_schema,
          default: default, expires_at: expires_at, destinations: nil
        )
        @runtime.emit_session_envelope(@ctx,
                                       envelope_for(request, request_id, job_id))
        await_input_response(request_id, response_schema, default, expires_in_seconds)
      end

      # Request a scoped permission. Blocks until the client responds
      # with `permission.grant` (returning a freshly-issued lease record)
      # or `permission.deny` (raising `Arcp::Error::PermissionDenied`).
      def request_permission(permission:, resource:, operation:,
                             requested_lease_seconds: 300, reason: nil,
                             expires_in_seconds: nil, job_id: nil)
        request_id = MessageId.random
        request = Messages::Permissions::PermissionRequest.new(
          permission: permission, resource: resource, operation: operation,
          reason: reason, requested_lease_seconds: requested_lease_seconds
        )
        @runtime.emit_session_envelope(@ctx,
                                       envelope_for(request, request_id, job_id))
        decision = @ctx.pending.await(request_id.value, timeout_seconds: expires_in_seconds)
        case decision
        when Messages::Permissions::PermissionGrant
          @ctx.lease_manager.grant(
            session_id: @ctx.session_id, permission: permission,
            resource: resource, operation: operation,
            lease_seconds: decision.lease_seconds || requested_lease_seconds
          )
        when Messages::Permissions::PermissionDeny
          raise Arcp::Error::PermissionDenied.new(decision.reason || 'denied',
                                                  permission: permission, resource: resource)
        else
          raise Arcp::Error::Internal, "unexpected permission decision: #{decision.class}"
        end
      end

      private

      def await_input_response(request_id, response_schema, default, expires_in_seconds)
        response = @ctx.pending.await(request_id.value, timeout_seconds: expires_in_seconds)
        validate_input_value!(response.value, response_schema)
        response.value
      rescue Arcp::Error::DeadlineExceeded
        return default unless default.nil?

        cancelled = Messages::Human::InputCancelled.new(
          code: ErrorCode::DEADLINE_EXCEEDED, reason: 'expired', details: nil
        )
        @runtime.emit_session_envelope(@ctx,
                                       envelope_for(cancelled, MessageId.random, nil,
                                                    correlation_id: request_id))
        raise
      end

      def validate_input_value!(value, response_schema)
        return if response_schema.nil?

        schemer = JSONSchemer.schema(stringify(response_schema))
        errors = schemer.validate(stringify(value)).to_a
        return if errors.empty?

        raise Arcp::Error::InvalidArgument, "human.input.response failed schema: #{errors.first['error']}"
      end

      def envelope_for(payload, request_id, job_id, correlation_id: nil)
        Envelope.new(
          arcp: Arcp::PROTOCOL_VERSION,
          id: request_id,
          type: payload.class.type_name,
          timestamp: Time.now.utc,
          payload: payload,
          session_id: @ctx.session_id,
          job_id: job_id,
          correlation_id: correlation_id
        )
      end

      def stringify(obj)
        case obj
        when Hash then obj.transform_keys(&:to_s).transform_values { |v| stringify(v) }
        when Array then obj.map { |v| stringify(v) }
        else obj
        end
      end
    end
  end
end
