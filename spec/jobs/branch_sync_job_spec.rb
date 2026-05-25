require 'rails_helper'

RSpec.describe BranchSyncJob, type: :job do
  include ActiveJob::TestHelper

  # The minimum payload shape the job needs; mirrors what the webhook
  # controller slices out of the full GitHub push payload.
  def payload(overrides = {})
    {
      'ref'     => 'refs/heads/main',
      'before'  => 'a' * 40,
      'after'   => 'b' * 40,
      'created' => false,
      'deleted' => false,
      'forced'  => false,
      'commits' => []
    }.merge(overrides.stringify_keys)
  end

  # Shape commit hashes the way Octokit returns them from api.compare.
  def gh_commit(sha:, parent_shas: [])
    time = Time.zone.parse('2026-01-01T12:00:00Z')
    {
      sha: sha,
      commit: {
        author:    { name: 'Bot', email: 'bot@example.com', date: time },
        committer: { name: 'Bot', email: 'bot@example.com', date: time },
        message: 'msg'
      },
      html_url: "https://github.com/MESAHub/mesa/commit/#{sha}",
      parents: parent_shas.map { |s| { sha: s } }
    }
  end

  def sha40(prefix)
    prefix.to_s.ljust(40, '0')
  end

  let(:branch) { create(:branch, name: 'main') }

  it 'is queued on the default queue' do
    expect { described_class.perform_later(payload) }
      .to have_enqueued_job(described_class).on_queue('default')
  end

  it 'ignores refs that are not branch heads' do
    # Tag pushes, PR refs, etc. shouldn't trigger any work
    expect(Commit).not_to receive(:api)

    described_class.new.perform(payload('ref' => 'refs/tags/v1.0'))
  end

  describe 'normal push (existing branch)' do
    let(:before_commit) do
      create(:commit, sha: sha40('before'),
                      short_sha: sha40('before')[0, 7])
    end

    before do
      branch
      before_commit
      branch.update!(head_id: before_commit.id)
      branch.absorb_commits([before_commit.id])
    end

    it 'fetches via api.compare, ingests commits, edges, and memberships' do
      new_sha = sha40('newone')
      compare_response = {
        commits: [
          gh_commit(sha: new_sha, parent_shas: [before_commit.sha])
        ]
      }
      mock_client = double('octokit')
      allow(Commit).to receive(:api).and_return(mock_client)
      allow(mock_client).to receive(:compare)
        .with(Commit.repo_path, before_commit.sha, new_sha)
        .and_return(compare_response)

      expect {
        described_class.new.perform(
          payload('before' => before_commit.sha, 'after' => new_sha)
        )
      }.to change(Commit, :count).by(1)
        .and change(CommitRelation, :count).by(1)
        .and change { branch.branch_memberships.count }.by(1)

      new_commit = Commit.find_by(sha: new_sha)
      expect(branch.reload.head_id).to eq(new_commit.id)
      expect(new_commit.parents).to eq([before_commit])
    end

    it 'is a no-op when compare returns no commits (e.g., reset to same SHA)' do
      mock_client = double('octokit')
      allow(Commit).to receive(:api).and_return(mock_client)
      allow(mock_client).to receive(:compare).and_return({ commits: [] })

      expect {
        described_class.new.perform(payload)
      }.not_to change(Commit, :count)
    end

    it 'walks back through commit_relations for merge commits' do
      # Pre-existing side branch (3 commits ahead of where it forked).
      side_commits = (0..2).map do |i|
        create(:commit, sha: Digest::SHA1.hexdigest("side-#{i}"),
                        short_sha: Digest::SHA1.hexdigest("side-#{i}")[0, 7])
      end
      side_commits.each_cons(2) do |parent, child|
        CommitRelation.create!(parent: parent, child: child, parent_index: 0)
      end

      # The merge commit being pushed: parents are [main_tip, side_tip].
      merge_sha = sha40('merge')
      merge_hash = gh_commit(
        sha: merge_sha,
        parent_shas: [before_commit.sha, side_commits.last.sha]
      )

      mock_client = double('octokit')
      allow(Commit).to receive(:api).and_return(mock_client)
      allow(mock_client).to receive(:compare).and_return(commits: [merge_hash])

      expect {
        described_class.new.perform(
          payload('before' => before_commit.sha, 'after' => merge_sha)
        )
      }.to change { branch.branch_memberships.count }
        # 1 for merge + 3 walked back from side branch
        .by(4)

      expect(branch.commits).to include(*side_commits)
    end
  end

  describe 'branch deletion' do
    let!(:doomed) do
      b = create(:branch, name: 'doomed')
      c = create(:commit)
      BranchMembership.create!(branch: b, commit: c)
      b
    end

    it 'deletes the branch and its memberships when payload[:deleted] is true' do
      delete_payload = payload(
        'ref' => 'refs/heads/doomed',
        'deleted' => true,
        'after' => '0' * 40
      )

      expect {
        described_class.new.perform(delete_payload)
      }.to change(Branch, :count).by(-1)
        .and change(BranchMembership, :count).by(-1)
    end

    it 'leaves the underlying commits in place (orphan cleanup is separate)' do
      commit_sha = doomed.commits.first.sha
      delete_payload = payload(
        'ref' => 'refs/heads/doomed',
        'deleted' => true,
        'after' => '0' * 40
      )

      described_class.new.perform(delete_payload)

      expect(Commit.exists?(sha: commit_sha)).to be true
    end

    it 'is a no-op when the branch is already gone' do
      delete_payload = payload(
        'ref' => 'refs/heads/never-existed',
        'deleted' => true
      )

      expect {
        described_class.new.perform(delete_payload)
      }.not_to change(Branch, :count)
    end
  end

  describe 'branch creation' do
    it 'defers to BranchBackfillJob to populate edges and memberships' do
      create_payload = payload(
        'ref' => 'refs/heads/feature-x',
        'before' => '0' * 40,
        'after' => sha40('newhead'),
        'created' => true
      )

      # Stub the backfill so we don't actually try to hit GitHub
      allow(BranchBackfillJob).to receive(:perform_now)

      expect {
        described_class.new.perform(create_payload)
      }.to change(Branch, :count).by(1)

      created = Branch.find_by(name: 'feature-x')
      expect(BranchBackfillJob).to have_received(:perform_now).with(created.id)
    end

    it 'sets head_id once the backfill has materialized the head commit' do
      new_head_sha = sha40('newhead')
      create_payload = payload(
        'ref' => 'refs/heads/feature-y',
        'before' => '0' * 40,
        'after' => new_head_sha,
        'created' => true
      )

      # Simulate the backfill creating the head commit
      allow(BranchBackfillJob).to receive(:perform_now) do
        create(:commit, sha: new_head_sha, short_sha: new_head_sha[0, 7])
      end

      described_class.new.perform(create_payload)

      branch = Branch.find_by(name: 'feature-y')
      expect(branch.head&.sha).to eq(new_head_sha)
    end

    it 'leaves head_id nil only if the backfill genuinely could not find ' \
       'the head commit (defense-in-depth — should not happen with the ' \
       'real BranchBackfillJob, which upserts commit metadata)' do
      # If the backfill no-ops (e.g., stubbed in a test, or api.commits
      # returns nothing for a branch whose head is unreachable), we must
      # not crash. head_id stays nil and the operator can investigate.
      create_payload = payload(
        'ref' => 'refs/heads/feature-z',
        'before' => '0' * 40,
        'after' => sha40('mystery'),
        'created' => true
      )

      allow(BranchBackfillJob).to receive(:perform_now)  # no-op

      expect {
        described_class.new.perform(create_payload)
      }.not_to raise_error

      expect(Branch.find_by(name: 'feature-z').head_id).to be_nil
    end
  end

  describe 'push to a branch we never saw created' do
    it 'falls back to creation handling' do
      mystery_payload = payload(
        'ref' => 'refs/heads/never-saw',
        'before' => sha40('unknown'),
        'after' => sha40('newhead'),
        'created' => false
      )

      allow(BranchBackfillJob).to receive(:perform_now)
      allow(Rails.logger).to receive(:warn)

      described_class.new.perform(mystery_payload)

      expect(Branch.exists?(name: 'never-saw')).to be true
      expect(BranchBackfillJob).to have_received(:perform_now)
      expect(Rails.logger).to have_received(:warn).with(/never-saw/)
    end
  end
end
