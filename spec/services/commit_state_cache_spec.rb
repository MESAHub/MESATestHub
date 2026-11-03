require 'rails_helper'

# CommitStateCache keys each commit's state on a fingerprint of the rows
# commit_state reads, so every way those rows change has to change the
# key — including the bulk writes (insert_all / update_all) that claims
# go through, which skip callbacks.
RSpec.describe CommitStateCache do
  # The test env's cache is :null_store; nothing would ever hit.
  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  let(:user) { create(:user) }
  let(:computer) { create(:computer, user: user) }
  let(:other_computer) { create(:computer, user: user) }
  let(:test_case) { create(:test_case, name: 'pisn', module: 'star') }
  let(:commit) { create(:commit) }
  let!(:tcc) { create(:test_case_commit, commit: commit, test_case: test_case) }

  def result(computer:, passed: true)
    sub = create(:submission, commit: commit, computer: computer)
    create(:test_instance, commit: commit, computer: computer, test_case: test_case,
                           test_case_commit: tcc, submission: sub, passed: passed)
  end

  # A fresh instance each time, as a new request would load it, so
  # CommitState's per-instance memoization doesn't hide anything.
  def cached_state
    described_class.fetch([Commit.find(commit.id)])[commit.id]
  end

  def fresh_state
    Commit.find(commit.id).commit_state
  end

  it 'returns what commit_state computes' do
    result(computer: computer)
    expect(cached_state).to eq(fresh_state)
  end

  it 'serves a repeat fetch from the cache without recomputing' do
    result(computer: computer)
    cached_state
    expect_any_instance_of(Commit).not_to receive(:commit_state)
    expect(cached_state[:tests][:status]).to eq(:all_pass)
  end

  it 'recomputes after a new result lands' do
    result(computer: computer)
    expect(cached_state[:tests][:status]).to eq(:all_pass)
    result(computer: other_computer, passed: false)
    expect(cached_state[:tests][:status]).to eq(:mixed)
  end

  it 'recomputes after a submission is deleted' do
    result(computer: computer)
    result(computer: other_computer, passed: false)
    expect(cached_state[:tests][:status]).to eq(:mixed)
    Submission.where(computer: other_computer).destroy_all
    expect(cached_state[:tests][:status]).to eq(:all_pass)
  end

  it 'recomputes after claims are bulk-inserted and swept' do
    create(:submission, commit: commit, computer: computer, entire: false, empty: true)
    expect(cached_state[:tests][:pending_tests]).to eq(0)

    now = Time.current
    Claim.insert_all([{ computer_id: computer.id, commit_id: commit.id, test_case_commit_id: tcc.id,
                        scope: 'test', status: 'pending', expires_at: 1.minute.from_now,
                        created_at: now, updated_at: now }])
    expect(cached_state[:tests][:pending_tests]).to eq(1)

    Claim.sweep_expired!(now: 2.minutes.from_now)
    expect(cached_state[:tests][:pending_tests]).to eq(0)
  end

  it 'keeps commits apart when fetching a page of them' do
    other = create(:commit)
    result(computer: computer)
    states = described_class.fetch([Commit.find(commit.id), Commit.find(other.id)])
    expect(states[commit.id][:tests][:status]).to eq(:all_pass)
    expect(states[other.id][:tests][:status]).to eq(:not_run)
  end

  it 'reads only cached states with read_all' do
    other = create(:commit)
    described_class.fetch([Commit.find(commit.id)])
    cache = described_class.new([Commit.find(commit.id), Commit.find(other.id)])
    expect(cache.read_all.keys).to eq([commit.id])
  end
end
