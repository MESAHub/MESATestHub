require 'rails_helper'

RSpec.describe BranchBackfillJob, type: :job do
  include ActiveJob::TestHelper

  # Shape the GitHub API response the same way Octokit does (the keys we
  # read are :sha and :parents, each parent having a :sha). Plain
  # symbol-keyed hashes are enough — the production Sawyer::Resource
  # supports `[:foo]` lookup the same way.
  def fake_commit(sha:, parent_shas: [])
    {
      sha: sha,
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

    it 'stops paginating once a page produces no new edges' do
      # Build two pages worth of commits. Pre-record the edges for page 2
      # (the "older" half) so it'll be all-known when the job sees it.
      tip_first = chain_of(per_page * 2 + 5)

      # Tip-first: index 0 is newest. parent of i is i+1.
      tip_first.each_cons(2) do |child, parent|
        # nothing yet — we'll record SOME of these below
      end

      # Pre-record edges for everything from page 2 onward (older commits).
      # That's commits at indices [per_page, per_page*2+4].
      older = tip_first[per_page..]
      older.each_cons(2) do |child, parent|
        CommitRelation.create!(parent: parent, child: child, parent_index: 0)
      end

      pages = tip_first.each_slice(per_page).map do |slice|
        slice.each_with_index.map do |c, i_in_page|
          # Find this commit's parent in the chain
          idx_in_chain = tip_first.index(c)
          parent = tip_first[idx_in_chain + 1]
          fake_commit(sha: c.sha, parent_shas: parent ? [parent.sha] : [])
        end
      end

      client = stub_pages(pages)
      described_class.new.perform(branch.id)

      # Page 1 was fetched. Page 2 was fetched (and found to be all-known).
      # Page 3 should NOT have been fetched.
      expect(client).to have_received(:commits)
        .with(Commit.repo_path, sha: 'main', per_page: per_page, page: 1).once
      expect(client).to have_received(:commits)
        .with(Commit.repo_path, sha: 'main', per_page: per_page, page: 2).once
      expect(client).not_to have_received(:commits)
        .with(Commit.repo_path, sha: 'main', per_page: per_page, page: 3)
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
