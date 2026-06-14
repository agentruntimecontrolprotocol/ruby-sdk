# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp::MessageTypes do
  it 'closes the wire-type catalog at 19 entries' do
    expect(described_class::ALL.size).to eq(19)
  end

  it 'includes every session and job envelope name' do
    %w[session.hello session.welcome session.bye session.error session.ping
       session.pong session.ack session.list_jobs session.jobs
       job.submit job.accepted job.event job.result job.error
       job.cancel job.cancelled job.subscribe job.subscribed job.unsubscribe].each do |t|
      expect(described_class.known?(t)).to be(true), "missing #{t}"
    end
  end

  it 'reports unknown wire types as not known' do
    expect(described_class.known?('vendor.x.foo')).to be(false)
  end
end
