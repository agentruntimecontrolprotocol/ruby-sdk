# frozen_string_literal: true

# MemoryTransport variant that decodes Hash frames through Envelope.from_h,
# so tests can inject a malformed wire envelope (e.g. an unsupported arcp
# version) the same way a JSON-backed transport would surface it inside the
# runtime's inbound loop.
class DecodingMemoryTransport < Arcp::Transport::MemoryTransport
  def receive
    value = @incoming.dequeue
    return nil if value.equal?(:__arcp_close__)

    value.is_a?(Hash) ? Arcp::Envelope.from_h(value) : value
  end
end
