# frozen_string_literal: true

require 'arcp/messages/base'

module Arcp
  module Messages
    # Streaming payloads (§11).
    module Streaming
      KIND_TEXT    = 'text'
      KIND_BINARY  = 'binary'
      KIND_EVENT   = 'event'
      KIND_LOG     = 'log'
      KIND_METRIC  = 'metric'
      KIND_THOUGHT = 'thought'

      KNOWN_KINDS = [KIND_TEXT, KIND_BINARY, KIND_EVENT, KIND_LOG, KIND_METRIC, KIND_THOUGHT].freeze

      StreamOpen  = Arcp::Messages.define('stream.open',
                                          required: %i[kind],
                                          optional: {
                                            content_type: nil,
                                            encoding: nil,
                                            sidecar: false
                                          })
      StreamChunk = Arcp::Messages.define('stream.chunk',
                                          required: %i[sequence],
                                          optional: {
                                            content: nil,
                                            data: nil,
                                            content_type: nil,
                                            sha256: nil,
                                            role: nil,
                                            redacted: false
                                          })
      StreamClose = Arcp::Messages.define('stream.close', optional: { reason: nil })
      StreamError = Arcp::Messages.define('stream.error',
                                          required: %i[code message],
                                          optional: { retryable: false, details: nil })
    end
  end
end
