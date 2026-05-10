# frozen_string_literal: true

require 'arcp/messages/base'

module Arcp
  module Messages
    # Control payloads (§6.2).
    module Control
      Ping     = Arcp::Messages.define('ping', optional: { sent_at: nil })
      Pong     = Arcp::Messages.define('pong', optional: { received_at: nil })
      Ack      = Arcp::Messages.define('ack', optional: { detail: nil })
      Nack     = Arcp::Messages.define('nack', required: %i[code message],
                                               optional: { details: nil, retryable: false })
      Cancel   = Arcp::Messages.define('cancel',
                                       required: %i[target target_id],
                                       optional: { reason: nil, deadline_ms: 5_000 })
      CancelAccepted = Arcp::Messages.define('cancel.accepted',
                                             required: %i[target target_id])
      CancelRefused  = Arcp::Messages.define('cancel.refused',
                                             required: %i[target target_id reason])
      Interrupt      = Arcp::Messages.define('interrupt',
                                             required: %i[target target_id],
                                             optional: { prompt: nil })
      Resume         = Arcp::Messages.define('resume',
                                             optional: {
                                               after_message_id: nil,
                                               checkpoint_id: nil,
                                               include_open_streams: false
                                             })
      Backpressure   = Arcp::Messages.define('backpressure',
                                             optional: {
                                               desired_rate_per_second: nil,
                                               buffer_remaining_bytes: nil,
                                               reason: nil
                                             })
    end
  end
end
