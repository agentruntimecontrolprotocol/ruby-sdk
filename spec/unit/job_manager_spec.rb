# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp::Runtime::JobManager do
  let(:emitted) { [] }
  let(:emit) { ->(record, payload) { emitted << [record.job_id.value, payload] } }
  let(:fake_clock) do
    Class.new do
      class << self
        attr_accessor :now_value
      end

      def self.now
        now_value
      end
    end.tap { |c| c.now_value = Time.utc(2026, 5, 9, 12, 0, 0) }
  end

  it 'transitions accepted -> running on start, then completed' do
    manager = described_class.new(clock: fake_clock, emit: emit)
    Sync do |task|
      job_id = manager.accept(session_id: Arcp::SessionId.random, tool: 'noop', arguments: {})
      manager.start(task, job_id) { |_| 42 }.wait
    end

    types = emitted.map { |_, p| p.class }
    expect(types).to include(
      Arcp::Messages::Execution::JobAccepted,
      Arcp::Messages::Execution::JobStarted,
      Arcp::Messages::Execution::JobCompleted
    )
    completed = emitted.map { |_, p| p }.find { |p| p.is_a?(Arcp::Messages::Execution::JobCompleted) }
    expect(completed.value).to eq(42)
  end

  it 'fails the job on Arcp::Error and preserves the code' do
    manager = described_class.new(clock: fake_clock, emit: emit)
    Sync do |task|
      job_id = manager.accept(session_id: Arcp::SessionId.random, tool: 'noop', arguments: {})
      manager.start(task, job_id) do |_|
        raise Arcp::Error::PermissionDenied.new(permission: 'fs.read', resource: 'tmp')
      end.wait
    end

    failed = emitted.map { |_, p| p }.find { |p| p.is_a?(Arcp::Messages::Execution::JobFailed) }
    expect(failed).not_to be_nil
    expect(failed.code).to eq(Arcp::ErrorCode::PERMISSION_DENIED)
    expect(failed.message).to include('fs.read')
  end

  it 'rejects illegal transitions with FailedPrecondition' do
    manager = described_class.new(clock: fake_clock, emit: emit)
    job_id = manager.accept(session_id: Arcp::SessionId.random, tool: 'noop', arguments: {})
    manager.fail_job(job_id, code: 'INTERNAL', message: 'oops')
    expect { manager.complete(job_id, value: 1) }.not_to raise_error # idempotent on terminal
    expect do
      manager.lookup!(job_id).transition!(Arcp::Runtime::JobState::RUNNING)
    end.to raise_error(Arcp::Error::FailedPrecondition)
  end
end
