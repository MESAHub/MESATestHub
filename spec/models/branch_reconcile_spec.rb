require 'rails_helper'

# Specs for the Phase 3.5 catch-up path. Branch.reconcile_with_github
# diffs the local branch list against api.branches and dispatches
# synthetic webhook events through BranchSyncJob.
RSpec.describe Branch, '.reconcile_with_github' do
  # Sawyer::Resource gives both hash-style and method-style access; this
  # tiny stand-in does the same. Matches the helper in branch_api_update_spec.
  class FakeApiResource
    def initialize(data)
      @data = data.deep_symbolize_keys
    end

    def [](key)
      val = @data[key.to_sym]
      val.is_a?(Hash) ? FakeApiResource.new(val) : val
    end

    def name = @data[:name]
    def commit = FakeApiResource.new(@data[:commit])
    def sha = @data[:sha]
  end

  def stub_api_branches(branches)
    allow(Branch).to receive(:api_branches).and_return(
      branches.map { |b| FakeApiResource.new(b) }
    )
  end

  it 'enqueues a creation event for a branch new to local' do
    stub_api_branches([{ name: 'feature-x', commit: { sha: 'a' * 40 } }])
    allow(BranchSyncJob).to receive(:perform_now)

    stats = Branch.reconcile_with_github

    expect(BranchSyncJob).to have_received(:perform_now).with(
      a_hash_including(
        'ref' => 'refs/heads/feature-x',
        'before' => '0' * 40,
        'after' => 'a' * 40,
        'created' => true,
        'deleted' => false
      )
    )
    expect(stats[:created]).to eq(1)
  end

  it 'enqueues a push event for a branch whose head has moved' do
    branch = create(:branch, name: 'main')
    old_head = create(:commit, sha: 'o' * 40, short_sha: 'ooooooo')
    branch.update!(head: old_head)

    stub_api_branches([{ name: 'main', commit: { sha: 'n' * 40 } }])
    allow(BranchSyncJob).to receive(:perform_now)

    stats = Branch.reconcile_with_github

    expect(BranchSyncJob).to have_received(:perform_now).with(
      a_hash_including(
        'ref' => 'refs/heads/main',
        'before' => old_head.sha,
        'after' => 'n' * 40,
        'created' => false,
        'deleted' => false
      )
    )
    expect(stats[:moved]).to eq(1)
  end

  it 'skips a branch whose head matches GitHub' do
    branch = create(:branch, name: 'main')
    head = create(:commit, sha: 'h' * 40, short_sha: 'hhhhhhh')
    branch.update!(head: head)

    stub_api_branches([{ name: 'main', commit: { sha: head.sha } }])
    allow(BranchSyncJob).to receive(:perform_now)

    stats = Branch.reconcile_with_github

    expect(BranchSyncJob).not_to have_received(:perform_now)
    expect(stats[:unchanged]).to eq(1)
  end

  it 'enqueues a deletion event for a local branch absent from GitHub' do
    create(:branch, name: 'doomed')
    stub_api_branches([])
    allow(BranchSyncJob).to receive(:perform_now)

    stats = Branch.reconcile_with_github

    expect(BranchSyncJob).to have_received(:perform_now).with(
      a_hash_including(
        'ref' => 'refs/heads/doomed',
        'deleted' => true
      )
    )
    expect(stats[:deleted]).to eq(1)
  end

  it 'handles a mixed set: one new, one moved, one unchanged, one deleted' do
    # local state: main (head at 'old'), going-away, stable (head at 'stable')
    main = create(:branch, name: 'main')
    old_main_head = create(:commit, sha: 'o' * 40, short_sha: 'ooooooo')
    main.update!(head: old_main_head)

    create(:branch, name: 'going-away')

    stable = create(:branch, name: 'stable')
    stable_head = create(:commit, sha: 's' * 40, short_sha: 'sssssss')
    stable.update!(head: stable_head)

    # github state: main moved, stable unchanged, feature-new is new,
    # going-away is gone.
    stub_api_branches([
      { name: 'main',        commit: { sha: 'n' * 40 } },
      { name: 'stable',      commit: { sha: stable_head.sha } },
      { name: 'feature-new', commit: { sha: 'f' * 40 } }
    ])
    allow(BranchSyncJob).to receive(:perform_now)

    stats = Branch.reconcile_with_github

    expect(stats).to eq(created: 1, moved: 1, deleted: 1, unchanged: 1)
  end

  it 'treats a local branch with nil head as needing creation-style handling' do
    # This happens when an earlier sync partially populated the branch
    # row but never set its head. The reconcile should treat it as
    # "needs to be brought up to GitHub's current head".
    create(:branch, name: 'half-synced', head_id: nil)
    stub_api_branches([
      { name: 'half-synced', commit: { sha: 'a' * 40 } }
    ])
    allow(BranchSyncJob).to receive(:perform_now)

    Branch.reconcile_with_github

    expect(BranchSyncJob).to have_received(:perform_now).with(
      a_hash_including(
        'ref' => 'refs/heads/half-synced',
        'before' => '0' * 40,
        'after' => 'a' * 40,
        'created' => true
      )
    )
  end
end
