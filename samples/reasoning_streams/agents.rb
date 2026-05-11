# frozen_string_literal: true

# Primary + critic LLM stand-ins.
module Agents
  # One reasoning step. Real version: an Anthropic call that folds the
  # critique into the prompt when present.
  def self.primary_step(_request, _prior_critique)
    raise NotImplementedError
  end

  # Critic LLM. Returns [severity, summary, suggestion, tokens_consumed].
  # Severity is one of "nudge", "warn", "halt".
  def self.critique_thought(_thought)
    raise NotImplementedError
  end
end
