# frozen_string_literal: true

require 'spec_helper'
require 'bigdecimal'

RSpec.describe Arcp::Lease::CostBudget do
  it 'parses CCY:amount entries via BigDecimal' do
    budget = described_class.parse(['USD:1.50', 'EUR:0.25'])
    expect(budget.remaining('USD')).to eq(BigDecimal('1.50'))
    expect(budget.remaining('EUR')).to eq(BigDecimal('0.25'))
  end

  it 'rejects malformed entries' do
    expect { described_class.parse(['USD']) }.to raise_error(Arcp::Errors::InvalidRequest)
  end
end

RSpec.describe Arcp::Lease::BudgetCounter do
  it 'decrements safely and reports remaining' do
    counter = described_class.new(initial: { 'USD' => BigDecimal('1.00') })
    expect(counter.try_decrement('USD', BigDecimal('0.40'))).to be(true)
    expect(counter.try_decrement('USD', BigDecimal('0.60'))).to be(true)
    expect(counter.try_decrement('USD', BigDecimal('0.01'))).to be(false)
  end

  it 'snapshots immutably' do
    counter = described_class.new(initial: { 'USD' => BigDecimal('1') })
    snap = counter.snapshot
    counter.try_decrement('USD', BigDecimal('0.5'))
    expect(snap['USD']).to eq(BigDecimal('1'))
  end
end

RSpec.describe Arcp::Lease::LeaseConstraints do
  it 'rejects non-UTC expires_at' do
    constraints = described_class.new(expires_at: '2026-05-14T10:00:00+02:00', max_budget: nil)
    expect { constraints.validate! }.to raise_error(Arcp::Errors::InvalidRequest)
  end

  it 'accepts a future Z-suffixed UTC' do
    constraints = described_class.new(expires_at: '2099-05-14T10:00:00Z', max_budget: nil)
    expect { constraints.validate! }.not_to raise_error
  end

  it 'rejects a past expires_at as INVALID_REQUEST (§9.5)' do
    constraints = described_class.new(expires_at: '2020-01-01T00:00:00Z', max_budget: nil)
    expect { constraints.validate! }.to raise_error(Arcp::Errors::InvalidRequest, /future/)
  end
end

RSpec.describe Arcp::Lease::LeaseRequest do
  it 'round-trips model.use patterns' do
    request = described_class.from_h(
      'capabilities' => ['cost.spend'],
      'model.use' => ['tier-fast/*']
    )

    expect(request.model_use).to eq(['tier-fast/*'])
    expect(request.to_h['model.use']).to eq(['tier-fast/*'])
  end
end

RSpec.describe Arcp::Lease::Subsetting do
  let(:parent) do
    Arcp::Lease::Lease.new(
      id: 'lse_p', capabilities: %w[fs.read net.fetch],
      budget: Arcp::Lease::CostBudget.parse(['USD:5.00']),
      model_use: ['tier-fast/*'],
      expires_at: '2026-05-14T12:00:00Z', issued_at: '2026-05-14T10:00:00Z'
    )
  end

  it 'rejects capability expansion' do
    request = Arcp::Lease::LeaseRequest.new(capabilities: %w[fs.write], budget: nil, expires_at: nil)
    expect { described_class.bound(parent: parent, request: request) }
      .to raise_error(Arcp::Errors::LeaseSubsetViolation)
  end

  it 'rejects budget exceeding parent remaining' do
    request = Arcp::Lease::LeaseRequest.new(
      capabilities: %w[fs.read],
      budget: Arcp::Lease::CostBudget.parse(['USD:10.00']),
      expires_at: nil
    )
    expect { described_class.bound(parent: parent, request: request) }
      .to raise_error(Arcp::Errors::LeaseSubsetViolation)
  end

  it 'produces a child lease bounded by parent' do
    request = Arcp::Lease::LeaseRequest.new(
      capabilities: %w[fs.read],
      budget: Arcp::Lease::CostBudget.parse(['USD:2.00']),
      expires_at: '2026-05-14T11:30:00Z'
    )
    child = described_class.bound(parent: parent, request: request)
    expect(child.capabilities).to eq(%w[fs.read])
    expect(child.expires_at).to eq('2026-05-14T11:30:00Z')
    expect(child.budget.remaining('USD')).to eq(BigDecimal('2.00'))
  end

  it 'rejects model.use expansion' do
    request = Arcp::Lease::LeaseRequest.new(
      capabilities: %w[fs.read],
      model_use: ['anthropic/*']
    )

    expect { described_class.bound(parent: parent, request: request) }
      .to raise_error(Arcp::Errors::LeaseSubsetViolation)
  end

  it 'allows a child model literal inside a parent model glob' do
    request = Arcp::Lease::LeaseRequest.new(
      capabilities: %w[fs.read],
      model_use: ['tier-fast/gpt-4o']
    )

    child = described_class.bound(parent: parent, request: request)
    expect(child.model_use).to eq(['tier-fast/gpt-4o'])
  end
end
