# frozen_string_literal: true

require 'base64'
require 'digest'

require 'arcp/error'
require 'arcp/error_code'
require 'arcp/ids'
require 'arcp/messages/artifacts'

module Arcp
  module Runtime
    # In-memory artifact store with periodic expiry sweep (§16).
    class ArtifactStore
      DEFAULT_RETENTION_SECONDS = 60 * 60 # 1 hour

      def initialize(clock: Time, default_retention_seconds: DEFAULT_RETENTION_SECONDS)
        @clock = clock
        @default_retention_seconds = default_retention_seconds
        @artifacts = {}
        @mutex = Mutex.new
      end

      # @param session_id [Arcp::SessionId]
      # @param artifact_id [Arcp::ArtifactId]
      # @param media_type [String]
      # @param data [String] base64-encoded
      # @param sha256 [String, nil]
      # @param retention_seconds [Integer, nil]
      # @return [Arcp::Messages::Artifacts::ArtifactRef]
      def put(session_id:, artifact_id:, media_type:, data:, sha256: nil, retention_seconds: nil)
        bytes = decode_base64(data)
        actual_sha = Digest::SHA256.hexdigest(bytes)
        if sha256 && !sha256.casecmp(actual_sha).zero?
          raise Arcp::Error::InvalidArgument, "sha256 mismatch: expected #{sha256}, got #{actual_sha}"
        end

        retention = retention_seconds || @default_retention_seconds
        expires_at = @clock.now + retention
        @mutex.synchronize do
          @artifacts[artifact_id.value] = {
            session_id: session_id.value, media_type: media_type, bytes: bytes,
            sha256: actual_sha, expires_at: expires_at
          }
        end
        Messages::Artifacts::ArtifactRef.new(
          artifact_id: artifact_id.value,
          media_type: media_type,
          size: bytes.bytesize,
          uri: "arcp://session/#{session_id.value}/artifact/#{artifact_id.value}",
          sha256: actual_sha,
          expires_at: expires_at.utc.iso8601(6),
          data: nil
        )
      end

      # @return [Arcp::Messages::Artifacts::ArtifactRef]
      def fetch(artifact_id:, session_id:, include_data: true)
        record = @mutex.synchronize { @artifacts[id_value(artifact_id)] }
        raise Arcp::Error::NotFound, "artifact not found: #{artifact_id}" if record.nil?
        if record[:session_id] != session_id.value
          raise Arcp::Error::PermissionDenied.new(permission: 'artifact.fetch', resource: artifact_id)
        end

        if @clock.now >= record[:expires_at]
          @mutex.synchronize { @artifacts.delete(id_value(artifact_id)) }
          raise Arcp::Error::NotFound, "artifact expired: #{artifact_id}"
        end

        Messages::Artifacts::ArtifactRef.new(
          artifact_id: id_value(artifact_id),
          media_type: record[:media_type],
          size: record[:bytes].bytesize,
          uri: "arcp://session/#{session_id.value}/artifact/#{id_value(artifact_id)}",
          sha256: record[:sha256],
          expires_at: record[:expires_at].utc.iso8601(6),
          data: include_data ? Base64.strict_encode64(record[:bytes]) : nil
        )
      end

      def release(artifact_id:, session_id:)
        @mutex.synchronize do
          record = @artifacts[id_value(artifact_id)]
          return false if record.nil?
          if record[:session_id] != session_id.value
            raise Arcp::Error::PermissionDenied.new(permission: 'artifact.release', resource: artifact_id)
          end

          @artifacts.delete(id_value(artifact_id))
          true
        end
      end

      def sweep_expired
        now = @clock.now
        deleted = 0
        @mutex.synchronize do
          @artifacts.delete_if do |_, record|
            if now >= record[:expires_at]
              deleted += 1
              true
            else
              false
            end
          end
        end
        deleted
      end

      def size
        @mutex.synchronize { @artifacts.size }
      end

      private

      def id_value(artifact_id)
        artifact_id.respond_to?(:value) ? artifact_id.value : artifact_id
      end

      def decode_base64(data)
        Base64.strict_decode64(data)
      rescue ArgumentError
        raise Arcp::Error::InvalidArgument, 'artifact.put.data is not valid base64'
      end
    end
  end
end
