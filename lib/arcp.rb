# frozen_string_literal: true

require 'arcp/version'
require 'arcp/error_code'
require 'arcp/error'
require 'arcp/priority'
require 'arcp/ids'
require 'arcp/extensions'
require 'arcp/message_type'
require 'arcp/envelope'
require 'arcp/json'
require 'arcp/trace'
require 'arcp/capabilities'

require 'arcp/messages/base'
require 'arcp/messages/session'
require 'arcp/messages/control'
require 'arcp/messages/execution'
require 'arcp/messages/streaming'
require 'arcp/messages/human'
require 'arcp/messages/permissions'
require 'arcp/messages/subscriptions'
require 'arcp/messages/artifacts'
require 'arcp/messages/telemetry'

require 'arcp/auth/auth_scheme'
require 'arcp/auth/bearer'
require 'arcp/auth/jwt'

require 'arcp/transport/transport'
require 'arcp/transport/memory'

require 'arcp/runtime/session'
require 'arcp/runtime/runtime'
require 'arcp/client/client'

require 'arcp/store/event_log'

# Top-level namespace for the ARCP Ruby SDK.
module Arcp
end
