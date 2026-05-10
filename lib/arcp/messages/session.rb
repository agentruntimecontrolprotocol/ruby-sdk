# frozen_string_literal: true

require 'arcp/messages/base'

module Arcp
  module Messages
    # Identity & authentication payloads (§8).
    module Session
      Open          = Arcp::Messages.define('session.open',
                                            required: %i[auth client capabilities])
      Challenge     = Arcp::Messages.define('session.challenge',
                                            required: %i[scheme nonce],
                                            optional: { detail: nil })
      Authenticate  = Arcp::Messages.define('session.authenticate',
                                            required: %i[scheme proof],
                                            optional: { detail: nil })
      Accepted      = Arcp::Messages.define('session.accepted',
                                            required: %i[session_id runtime capabilities],
                                            optional: { lease: nil })
      Unauthenticated = Arcp::Messages.define('session.unauthenticated',
                                              required: %i[code message],
                                              optional: { details: nil })
      Rejected      = Arcp::Messages.define('session.rejected',
                                            required: %i[code message],
                                            optional: { details: nil })
      Refresh       = Arcp::Messages.define('session.refresh',
                                            required: %i[scheme],
                                            optional: { deadline_ms: 30_000, nonce: nil })
      Evicted       = Arcp::Messages.define('session.evicted',
                                            required: %i[code reason],
                                            optional: { details: nil })
      Close         = Arcp::Messages.define('session.close',
                                            optional: { reason: nil, detach: false })
    end
  end
end
