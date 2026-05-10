# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp::Error do
  describe Arcp::ErrorCode do
    it 'exposes all canonical codes' do
      expect(described_class::ALL).to include(
        described_class::OK, described_class::CANCELLED, described_class::UNKNOWN,
        described_class::INVALID_ARGUMENT, described_class::DEADLINE_EXCEEDED,
        described_class::NOT_FOUND, described_class::ALREADY_EXISTS,
        described_class::PERMISSION_DENIED, described_class::RESOURCE_EXHAUSTED,
        described_class::FAILED_PRECONDITION, described_class::ABORTED,
        described_class::OUT_OF_RANGE, described_class::UNIMPLEMENTED,
        described_class::INTERNAL, described_class::UNAVAILABLE,
        described_class::DATA_LOSS, described_class::UNAUTHENTICATED,
        described_class::HEARTBEAT_LOST, described_class::LEASE_EXPIRED,
        described_class::LEASE_REVOKED, described_class::BACKPRESSURE_OVERFLOW
      )
    end

    it 'classifies retryable defaults per §18.3' do
      expect(described_class.retryable?(described_class::UNAVAILABLE)).to be(true)
      expect(described_class.retryable?(described_class::DEADLINE_EXCEEDED)).to be(true)
      expect(described_class.retryable?(described_class::INVALID_ARGUMENT)).to be(false)
      expect(described_class.retryable?(described_class::NOT_FOUND)).to be(false)
    end
  end

  it 'maps subclasses to canonical codes' do
    {
      Arcp::Error::Cancelled => Arcp::ErrorCode::CANCELLED,
      Arcp::Error::InvalidArgument => Arcp::ErrorCode::INVALID_ARGUMENT,
      Arcp::Error::DeadlineExceeded => Arcp::ErrorCode::DEADLINE_EXCEEDED,
      Arcp::Error::NotFound => Arcp::ErrorCode::NOT_FOUND,
      Arcp::Error::AlreadyExists => Arcp::ErrorCode::ALREADY_EXISTS,
      Arcp::Error::FailedPrecondition => Arcp::ErrorCode::FAILED_PRECONDITION,
      Arcp::Error::Aborted => Arcp::ErrorCode::ABORTED,
      Arcp::Error::OutOfRange => Arcp::ErrorCode::OUT_OF_RANGE,
      Arcp::Error::Internal => Arcp::ErrorCode::INTERNAL,
      Arcp::Error::Unavailable => Arcp::ErrorCode::UNAVAILABLE,
      Arcp::Error::DataLoss => Arcp::ErrorCode::DATA_LOSS,
      Arcp::Error::Unauthenticated => Arcp::ErrorCode::UNAUTHENTICATED,
      Arcp::Error::HeartbeatLost => Arcp::ErrorCode::HEARTBEAT_LOST,
      Arcp::Error::BackpressureOverflow => Arcp::ErrorCode::BACKPRESSURE_OVERFLOW,
      Arcp::Error::ParseError => Arcp::ErrorCode::INVALID_ARGUMENT
    }.each do |klass, code|
      err = klass.new('boom')
      expect(err.code).to eq(code), "expected #{klass} to have code #{code}, got #{err.code}"
    end
  end

  it 'PermissionDenied carries permission and resource' do
    err = Arcp::Error::PermissionDenied.new(permission: 'fs.read', resource: 'foo')
    expect(err.code).to eq(Arcp::ErrorCode::PERMISSION_DENIED)
    expect(err.details).to eq(permission: 'fs.read', resource: 'foo')
    expect(err.retryable?).to be(false)
  end

  it 'LeaseExpired carries lease_id and expired_at' do
    expired = Time.utc(2026, 1, 1)
    err = Arcp::Error::LeaseExpired.new(lease_id: Arcp::LeaseId.new(value: 'lease_x'), expired_at: expired)
    expect(err.code).to eq(Arcp::ErrorCode::LEASE_EXPIRED)
    expect(err.details).to eq(lease_id: 'lease_x', expired_at: expired.iso8601)
  end

  it 'LeaseRevoked carries lease_id and reason' do
    err = Arcp::Error::LeaseRevoked.new(lease_id: Arcp::LeaseId.new(value: 'lease_y'), reason: 'admin')
    expect(err.code).to eq(Arcp::ErrorCode::LEASE_REVOKED)
    expect(err.details).to eq(lease_id: 'lease_y', reason: 'admin')
  end

  it 'Unimplemented carries section and detail' do
    err = Arcp::Error::Unimplemented.new(section: '§14', detail: 'agent.delegate')
    expect(err.code).to eq(Arcp::ErrorCode::UNIMPLEMENTED)
    expect(err.details).to eq(section: '§14', detail: 'agent.delegate')
    expect(err.message).to include('§14').and include('agent.delegate')
  end

  it 'ResourceExhausted serializes retry_after_seconds' do
    err = Arcp::Error::ResourceExhausted.new('rate limited', retry_after_seconds: 30)
    expect(err.details).to eq(retry_after_seconds: 30)
    expect(err.retryable?).to be(true)
  end

  it 'serializes to a tool.error payload' do
    err = Arcp::Error::PermissionDenied.new(permission: 'fs.write', resource: 'tmp')
    payload = err.to_payload(trace_id: 'trace_1')
    expect(payload).to include(
      code: Arcp::ErrorCode::PERMISSION_DENIED,
      message: 'permission denied: fs.write on tmp',
      retryable: false,
      details: { permission: 'fs.write', resource: 'tmp' },
      trace_id: 'trace_1'
    )
  end
end
