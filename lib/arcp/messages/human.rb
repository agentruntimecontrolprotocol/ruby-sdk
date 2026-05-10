# frozen_string_literal: true

require 'arcp/messages/base'

module Arcp
  module Messages
    # Human-in-the-loop payloads (§12).
    module Human
      InputRequest   = Arcp::Messages.define('human.input.request',
                                             required: %i[prompt],
                                             optional: {
                                               response_schema: nil,
                                               default: nil,
                                               expires_at: nil,
                                               destinations: nil
                                             })
      InputResponse  = Arcp::Messages.define('human.input.response',
                                             required: %i[value],
                                             optional: { responded_by: nil, responded_at: nil })
      InputCancelled = Arcp::Messages.define('human.input.cancelled',
                                             required: %i[code],
                                             optional: { reason: nil, details: nil })
      ChoiceRequest  = Arcp::Messages.define('human.choice.request',
                                             required: %i[prompt options],
                                             optional: { expires_at: nil, default_choice_id: nil })
      ChoiceResponse = Arcp::Messages.define('human.choice.response',
                                             required: %i[choice_id],
                                             optional: { responded_by: nil, responded_at: nil })
    end
  end
end
