# frozen_string_literal: true

require_relative '../_harness'

module ProvisionedCredentialsSample
  HANDLER = lambda do |ctx|
    ctx.status(phase: 'using_gateway')
    ctx.finish(result: { 'credential_count' => 1 })
  end

  def self.provisioner
    @provisioner ||= Arcp::Credentials::InMemoryProvisioner.new(
      endpoint: 'https://llm-gateway.example/v1',
      profile: 'openai'
    )
  end

  def self.runtime
    Harness.runtime(
      agents: { 'gateway-caller' => HANDLER },
      credential_provisioner: provisioner,
      credential_store: Arcp::Credentials::InMemoryStore.new
    )
  end
end
