# frozen_string_literal: true

# Step bodies. Real version: a service-objects-style step pipeline
# (Anthropic call for plan / synth / critique / finalize, retriever
# for gather).
module Steps
  def self.run_step(_client, job_id:, step:, inputs:)
    raise NotImplementedError
  end
end
