# frozen_string_literal: true

# Cheap-tier inference. Real version: anthropic-ruby call with a
# system prompt asking for a `Confidence: X.XX` line, then heuristics
# on top to derive the final score.
module Cheap
  def self.attempt(_prompt)
    raise NotImplementedError
  end
end
