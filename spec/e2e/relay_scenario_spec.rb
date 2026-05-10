# frozen_string_literal: true

require 'spec_helper'
require 'async'

# End-to-end relay scenario from §25 of the RFC: a tool that requests
# human input, requests a scoped permission, and produces a result.
# This spec runs the same scenario over both the Memory transport and
# (smoke) the Stdio transport.

RSpec.shared_examples 'agent relay scenario' do |build_pair|
  let(:bearer) { Arcp::Auth::Bearer.new(accept_any: true) }
  let(:client_identity) { { kind: 'rspec-e2e', version: '1.0', fingerprint: 'sha256:e2e' } }

  it 'completes a refund-with-permission scenario' do
    Sync do
      client_transport, runtime_transport = build_pair.call
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      runtime.register_tool('relay-refund') do |ctx, _args|
        confirm = ctx.request_human_input(
          prompt: 'confirm?',
          response_schema: { 'type' => 'object',
                             'properties' => { 'confirm' => { 'type' => 'boolean' } },
                             'required' => ['confirm'] }
        )
        raise Arcp::Error::Cancelled, 'declined' unless confirm['confirm']

        lease = ctx.request_permission(
          permission: 'payment.refund.create', resource: 'order:1',
          operation: 'refund', requested_lease_seconds: 30
        )
        { ok: true, lease_id: lease.lease_id.value }
      end
      Async { runtime.serve(runtime_transport) }

      client = Arcp::Client::Client.new(transport: client_transport)
      client.open(auth: { scheme: 'bearer', token: 'tok' }, client: client_identity)
      client.on_human_input { |_env| { 'confirm' => true } }
      client.on_permission_request { |_env| :grant }

      result = client.invoke(tool: 'relay-refund')
      expect(result).to be_successful
      expect(result.value).to include(ok: true).or include('ok' => true)
      expect(result.events.map { |e| e.payload.class }).to include(
        Arcp::Messages::Human::InputRequest,
        Arcp::Messages::Permissions::PermissionRequest,
        Arcp::Messages::Permissions::LeaseGranted,
        Arcp::Messages::Execution::JobCompleted
      )
      client.close
    end
  end
end

RSpec.describe 'relay scenario over memory transport', :integration do
  it_behaves_like 'agent relay scenario', -> { Arcp::Transport::Memory.pair }
end

RSpec.describe 'relay scenario over stdio transport', :integration do
  it_behaves_like 'agent relay scenario', lambda {
    c2r_r, c2r_w = IO.pipe
    r2c_r, r2c_w = IO.pipe
    [Arcp::Transport::Stdio.new(input: r2c_r, output: c2r_w),
     Arcp::Transport::Stdio.new(input: c2r_r, output: r2c_w)]
  }
end
