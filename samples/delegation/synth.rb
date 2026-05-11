# frozen_string_literal: true

# Final-pass synthesizer. Real version: an Anthropic call that folds
# successful subagent outputs into prose, ignoring failed peers.
module Synth
  def self.synthesize(_request, _jobs)
    raise NotImplementedError
  end
end
