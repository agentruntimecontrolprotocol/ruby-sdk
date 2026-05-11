# frozen_string_literal: true

# Generator + reviewer stand-ins. Real version: AutoGen-style agents.
module Agents
  Patch = Data.define(:diff)
  ReviewVerdict = Data.define(:grant, :reason)

  def self.propose(ticket:, prior_denial:)
    raise NotImplementedError
  end

  # Reviewer parses the patch out of `request.payload.resource` or
  # by looking it up by fingerprint, then runs the LLM.
  def self.review(ticket:, request:)
    raise NotImplementedError
  end
end
