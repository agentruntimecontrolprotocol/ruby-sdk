# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp::Job::Event do
  it 'decodes the progress kind into a typed body' do
    event = described_class.from_h(
      'kind' => 'progress',
      'body' => { 'current' => 3, 'total' => 5, 'units' => 'files', 'message' => 'indexing' }
    )
    expect(event.body).to be_a(Arcp::Job::EventBody::Progress)
    expect(event.body.current).to eq(3)
  end

  it 'decodes result_chunk and validates encoding' do
    body = { 'result_id' => 'res_1', 'chunk_seq' => 0, 'data' => 'hi', 'encoding' => 'utf8', 'more' => true }
    event = described_class.from_h('kind' => 'result_chunk', 'body' => body)
    expect(event.body.decoded).to eq('hi')

    expect do
      described_class.from_h('kind' => 'result_chunk', 'body' => body.merge('encoding' => 'binary'))
    end.to raise_error(Arcp::Errors::InvalidRequest)
  end

  it 'leaves unknown kinds as a frozen hash body' do
    event = described_class.from_h('kind' => 'x-vendor.acme.thing', 'body' => { 'k' => 1 })
    expect(event.known?).to be(false)
    expect(event.body).to be_a(Hash)
    expect(event.body).to be_frozen
  end

  it 'covers all reserved kinds' do
    expect(Arcp::Job::EventKind::ALL.size).to eq(10)
    expect(Arcp::Job::BODY_CLASSES.keys).to match_array(Arcp::Job::EventKind::ALL)
  end
end
