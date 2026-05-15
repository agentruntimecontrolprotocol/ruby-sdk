# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'session.list_jobs', type: :integration do
  it 'paginates and isolates jobs per principal' do
    Sync do
      runtime = build_runtime(
        agents: { echo: ->(ctx) { ctx.finish(result: nil) } },
        tokens: { 'alice-tok' => 'alice', 'bob-tok' => 'bob' }
      )
      alice_client, alice_task = open_pair(runtime, auth: { 'token' => 'alice-tok' })
      bob_client, bob_task = open_pair(runtime, auth: { 'token' => 'bob-tok' })

      5.times.map { alice_client.submit_job(agent: 'echo') }.each do |h|
        h.subscribe(client: alice_client).to_a
        h.get_result(client: alice_client)
      end

      alice_jobs = alice_client.list_jobs(limit: 2).first(5)
      expect(alice_jobs.size).to eq(5)

      bob_jobs = bob_client.list_jobs.to_a
      expect(bob_jobs).to be_empty

      alice_client.close
      bob_client.close
      alice_task.stop
      bob_task.stop
    end
  end
end
