# frozen_string_literal: true

require 'arcp/messages/base'

module Arcp
  module Messages
    # Subscription payloads (§13).
    module Subscriptions
      Subscribe = Arcp::Messages.define('subscribe',
                                        optional: { filter: {}, since: nil })
      SubscribeAccepted = Arcp::Messages.define('subscribe.accepted',
                                                required: %i[subscription_id],
                                                optional: { detail: nil })
      SubscribeEvent   = Arcp::Messages.define('subscribe.event',
                                               required: %i[event],
                                               optional: { sequence: nil })
      Unsubscribe      = Arcp::Messages.define('unsubscribe',
                                               optional: { reason: nil })
      SubscribeClosed  = Arcp::Messages.define('subscribe.closed',
                                               required: %i[code],
                                               optional: { reason: nil })
    end
  end
end
