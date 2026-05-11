# frozen_string_literal: true

# Stand-in for the Anthropic tool-use loop. Real version: an
# `Anthropic::Client` with a system prompt, yielding one LLMStep per turn.
module Agent
  ToolCall = Data.define(:argv, :reason)
  LLMStep = Data.define(:thought, :tool_call, :final)

  def self.llm_loop(_user_request)
    raise NotImplementedError
  end
end
