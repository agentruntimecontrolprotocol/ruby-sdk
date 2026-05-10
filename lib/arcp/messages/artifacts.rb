# frozen_string_literal: true

require 'arcp/messages/base'

module Arcp
  module Messages
    # Artifact payloads (§16).
    module Artifacts
      ArtifactPut     = Arcp::Messages.define('artifact.put',
                                              required: %i[artifact_id media_type size data],
                                              optional: { sha256: nil, expires_at: nil })
      ArtifactFetch   = Arcp::Messages.define('artifact.fetch',
                                              required: %i[artifact_id],
                                              optional: { redirect_ok: true })
      ArtifactRef     = Arcp::Messages.define('artifact.ref',
                                              required: %i[artifact_id media_type size],
                                              optional: { uri: nil, sha256: nil, expires_at: nil, data: nil })
      ArtifactRelease = Arcp::Messages.define('artifact.release',
                                              required: %i[artifact_id])
    end
  end
end
