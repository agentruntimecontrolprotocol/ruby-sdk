# frozen_string_literal: true

require 'spec_helper'
require 'async'

RSpec.describe 'permissions and leases', :integration do
  let(:bearer) { Arcp::Auth::Bearer.new(tokens: { 'tok-alice' => 'alice@example.com' }) }
  let(:client_identity) { { 'kind' => 'rspec', 'version' => '1.0', 'fingerprint' => 'sha256:test' } }

  it 'grants a permission, materializes a lease, and emits lease.granted' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      runtime.register_tool('refund') do |ctx, _args|
        lease = ctx.request_permission(
          permission: 'payment.refund.create', resource: 'order:1',
          operation: 'refund', requested_lease_seconds: 60
        )
        { lease_id: lease.lease_id.value, expires_at: lease.expires_at.iso8601 }
      end
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)
      client.on_permission_request { |_env| :grant }

      result = client.invoke(tool: 'refund')
      expect(result).to be_successful
      lease_granted = result.events.find { |e| e.payload.is_a?(Arcp::Messages::Permissions::LeaseGranted) }
      expect(lease_granted).not_to be_nil
      expect(lease_granted.payload.permission).to eq('payment.refund.create')
      client.close
    end
  end

  it 'raises PermissionDenied when the client denies' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      runtime.register_tool('strict') do |ctx, _args|
        ctx.request_permission(
          permission: 'fs.write', resource: '/etc', operation: 'write'
        )
      end
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)
      client.on_permission_request { |_env| { decision: :deny, reason: 'not authorized' } }

      result = client.invoke(tool: 'strict')
      expect(result).not_to be_successful
      expect(result.terminal.payload.code).to eq(Arcp::ErrorCode::PERMISSION_DENIED)
      client.close
    end
  end
end

RSpec.describe Arcp::Runtime::LeaseManager do
  let(:emitted) { [] }
  let(:emit) { ->(rec, payload) { emitted << [rec.lease_id.value, payload] } }
  let(:fake_clock) do
    klass = Class.new do
      class << self
        attr_accessor :now_value
      end

      def self.now
        now_value
      end
    end
    klass.now_value = Time.utc(2026, 5, 9, 12, 0, 0)
    klass
  end

  it 'detects expiry via clock advancement' do
    manager = described_class.new(emit: emit, clock: fake_clock)
    lease = manager.grant(session_id: Arcp::SessionId.random, permission: 'fs.read',
                          resource: 'tmp', operation: 'read', lease_seconds: 60)
    expect { manager.validate!(lease.lease_id) }.not_to raise_error
    fake_clock.now_value = fake_clock.now_value + 120
    expect { manager.validate!(lease.lease_id) }.to raise_error(Arcp::Error::LeaseExpired)
  end

  it 'rejects validate after revoke' do
    manager = described_class.new(emit: emit, clock: fake_clock)
    lease = manager.grant(session_id: Arcp::SessionId.random, permission: 'fs.read',
                          resource: 'tmp', operation: 'read', lease_seconds: 600)
    manager.revoke(lease.lease_id, reason: 'admin')
    expect { manager.validate!(lease.lease_id) }.to raise_error(Arcp::Error::LeaseRevoked)
  end

  it 'extends a lease and emits lease.extended' do
    manager = described_class.new(emit: emit, clock: fake_clock)
    lease = manager.grant(session_id: Arcp::SessionId.random, permission: 'fs.read',
                          resource: 'tmp', operation: 'read', lease_seconds: 60)
    manager.extend_lease(lease.lease_id, extend_seconds: 600)
    extended = emitted.map { |_, p| p }.find { |p| p.is_a?(Arcp::Messages::Permissions::LeaseExtended) }
    expect(extended).not_to be_nil
  end
end
