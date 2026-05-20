require 'rails_helper'

RSpec.describe BranchBackfillJob, type: :job do
  include ActiveJob::TestHelper

  # Shape the GitHub API response the same way Octokit's api.commits
  # does. Plain symbol-keyed hashes work — Sawyer::Resource supports
  # `[:foo]` lookup identically. Need the full nested shape because
  # ingest_payload_commits passes it through hash_from_github.
  def fake_commit(sha:, parent_shas: [])
    {
      sha: sha,
      commit: {
        author: { name: 'Bot', email: 'bot@example.com',
                  date: Time.zone.parse('2026-01-01T12:00:00Z') },
        message: "msg #{sha[0, 7]}"
      },
      html_url: "https://github.com/MESAHub/mesa/commit/#{sha}",
      parents: parent_shas.map { |s| { sha: s } }
    }
  end

  def commit_with_sha(sha)
    create(:commit, sha: sha, short_sha: sha[0, 7])
  end

  # Stub `Commit.api(auto_paginate: false)` to return a client whose
  # `.commits(...)` returns the given `pages` in order. Pages past the
  # supplied list return [] (mirrors what GitHub does past the last page).
  # We use a single block-based stub so that ordering of `allow` calls
  # doesn't matter — RSpec stubs without `.with(...)` would otherwise
  # mask the specific ones.
  def stub_pages(pages)
    client = double('octokit_client')
    allow(client).to receive(:commits) do |_repo, **kwargs|
      pages[kwargs[:page] - 1] || []
    end
    allow(Commit).to receive(:api).with(auto_paginate: false)
                                  .and_return(client)
    client
  end

  let(:branch) { create(:branch, name: 'main') }

  it 'is queued on the default queue' do
    expect { described_class.perform_later(branch.id) }
      .to have_enqueued_job(described_class).on_queue('default')
  end

  it 'inserts a parent->child edge for a simple two-commit branch' do
    parent_commit = commit_with_sha('a' * 40)
    child_commit  = commit_with_sha('b' * 40)

    stub_pages([[
      fake_commit(sha: child_commit.sha, parent_shas: [parent_commit.sha]),
      fake_commit(sha: parent_commit.sha)
    ]])

    expect { described_class.new.perform(branch.id) }
      .to change(CommitRelation, :count).by(1)

    edge = CommitRelation.last
    expect(edge.parent).to eq(parent_commit)
    expect(edge.child).to eq(child_commit)
    expect(edge.parent_index).to eq(0)
  end

  it 'ingests commits that are not yet in the local DB' do
    # The branch-creation path through BranchSyncJob#handle_creation
    # depends on this — the head commit needs to exist after the job
    # runs so handle_creation can set branch.head_id from it.
    new_sha = 'a' * 40
    stub_pages([[fake_commit(sha: new_sha)]])

    expect { described_class.new.perform(branch.id) }
      .to change(Commit, :count).by(1)

    expect(Commit.exists?(sha: new_sha)).to be true
  end

  it 'is idempotent when rerun on the same branch' do
    p = commit_with_sha('a' * 40)
    c = commit_with_sha('b' * 40)
    stub_pages([[
      fake_commit(sha: c.sha, parent_shas: [p.sha]),
      fake_commit(sha: p.sha)
    ]])

    described_class.new.perform(branch.id)

    expect { described_class.new.perform(branch.id) }
      .not_to change(CommitRelation, :count)
  end

  it 'records every parent of a merge commit, tagging parent_index' do
    base  = commit_with_sha('a' * 40)
    side  = commit_with_sha('b' * 40)
    merge = commit_with_sha('c' * 40)

    stub_pages([[
      fake_commit(sha: merge.sha, parent_shas: [base.sha, side.sha]),
      fake_commit(sha: side.sha),
      fake_commit(sha: base.sha)
    ]])

    described_class.new.perform(branch.id)

    edges = CommitRelation.where(child_id: merge.id).order(:parent_index)
    expect(edges.size).to eq(2)
    expect(edges[0].parent).to eq(base)
    expect(edges[0].parent_index).to eq(0)
    expect(edges[1].parent).to eq(side)
    expect(edges[1].parent_index).to eq(1)
  end

  it 'skips edges whose parent SHA is not in the local DB' do
    child_commit = commit_with_sha('b' * 40)
    missing_sha  = 'a' * 40

    stub_pages([[
      fake_commit(sha: child_commit.sha, parent_shas: [missing_sha])
    ]])

    expect { described_class.new.perform(branch.id) }
      .not_to change(CommitRelation, :count)
  end

  it 'is a no-op when the API returns an empty first page' do
    stub_pages([[]])

    expect { described_class.new.perform(branch.id) }
      .not_to change(CommitRelation, :count)
  end

  describe 'pagination short-circuit' do
    let(:per_page) { BranchBackfillJob::PER_PAGE }

    # Build a chain of N commits A -> B -> C -> ... where each commit's
    # parent is the next one in the returned array. Uses SHA1 hashes
    # of unique strings so that both `sha` and `short_sha` stay unique
    # across the chain. Returns tip-first (newest first), mirroring the
    # order api.commits emits.
    def chain_of(n)
      (0...n).map do |i|
        commit_with_sha(Digest::SHA1.hexdigest("chain-#{branch.id}-#{i}"))
      end.reverse
    end

    it 'stops paginating once a page produces no new edges or memberships' do
      # Build two pages worth of commits. Pre-record both edges and
      # memberships for page 2 (the "older" half) so it's fully
      # saturated when the job sees it — both must be zero for the
      # short-circuit to fire.
      tip_first = chain_of(per_page * 2 + 5)

      older = tip_first[per_page..]
      older.each_cons(2) do |child, parent|
        CommitRelation.create!(parent: parent, child: child, parent_index: 0)
      end
      BranchMembership.insert_all(
        older.map { |c| { branch_id: branch.id, commit_id: c.id } }
      )

      pages = tip_first.each_slice(per_page).map do |slice|
        slice.map do |c|
          idx_in_chain = tip_first.index(c)
          parent = tip_first[idx_in_chain + 1]
          fake_commit(sha: c.sha, parent_shas: parent ? [parent.sha] : [])
        end
      end

      client = stub_pages(pages)
      described_class.new.perform(branch.id)

      # Page 1 was fetched. Page 2 was fetched and found fully saturated.
      # Page 3 should NOT have been fetched.
      expect(client).to have_received(:commits)
        .with(Commit.repo_path, sha: 'main', per_page: per_page, page: 1).once
      expect(client).to have_received(:commits)
        .with(Commit.repo_path, sha: 'main', per_page: per_page, page: 2).once
      expect(client).not_to have_received(:commits)
        .with(Commit.repo_path, sha: 'main', per_page: per_page, page: 3)
    end

    it 'keeps paginating when edges are saturated but memberships are not' do
      # This is the branch-creation case: edges are already in the DB
      # (because main's backfill covered them), but the new branch has
      # no memberships yet. The walk must continue to add memberships
      # for every commit reachable from the new branch's head.
      tip_first = chain_of(per_page * 2 + 5)

      # All edges already present
      tip_first.each_cons(2) do |child, parent|
        CommitRelation.create!(parent: parent, child: child, parent_index: 0)
      end
      # No memberships for `branch` yet — that's the point.

      pages = tip_first.each_slice(per_page).map do |slice|
        slice.map do |c|
          idx_in_chain = tip_first.index(c)
          parent = tip_first[idx_in_chain + 1]
          fake_commit(sha: c.sha, parent_shas: parent ? [parent.sha] : [])
        end
      end

      client = stub_pages(pages)

      expect { described_class.new.perform(branch.id) }
        .to change { branch.branch_memberships.count }
        .from(0).to(tip_first.size)

      # All three pages were fetched (2 full + 1 empty terminator).
      [1, 2, 3].each do |n|
        expect(client).to have_received(:commits)
          .with(Commit.repo_path, sha: 'main', per_page: per_page, page: n).once
      end
    end

    it 'stops paginating once a partial page signals the end of history' do
      # One short page (fewer than per_page commits) — no further pages
      # should be fetched.
      tip = commit_with_sha('a' * 40)

      pages = [[fake_commit(sha: tip.sha)]]
      client = stub_pages(pages)

      described_class.new.perform(branch.id)

      expect(client).to have_received(:commits)
        .with(Commit.repo_path, sha: 'main', per_page: per_page, page: 1).once
      expect(client).not_to have_received(:commits)
        .with(Commit.repo_path, sha: 'main', per_page: per_page, page: 2)
    end

    it 'keeps paginating while pages keep producing new edges' do
      # Build two full pages worth of commits, none pre-edged. The job
      # should fetch page 1, page 2, then page 3 (which is empty).
      tip_first = chain_of(per_page * 2)

      pages = tip_first.each_slice(per_page).map do |slice|
        slice.map do |c|
          idx_in_chain = tip_first.index(c)
          parent = tip_first[idx_in_chain + 1]
          fake_commit(sha: c.sha, parent_shas: parent ? [parent.sha] : [])
        end
      end

      client = stub_pages(pages)
      described_class.new.perform(branch.id)

      [1, 2].each do |n|
        expect(client).to have_received(:commits)
          .with(Commit.repo_path, sha: 'main', per_page: per_page, page: n).once
      end
      # Page 3 is the empty terminator.
      expect(client).to have_received(:commits)
        .with(Commit.repo_path, sha: 'main', per_page: per_page, page: 3).once
    end
  end
end
