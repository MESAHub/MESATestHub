require 'rails_helper'

RSpec.describe BranchBackfillJob, type: :job do
  include ActiveJob::TestHelper

  # Shape the GitHub API response the same way Octokit does (the keys we
  # read are :sha and :parents, with each parent having a :sha). Plain
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

  let(:branch) { create(:branch, name: 'main') }

  it 'is queued on the default queue' do
    expect { described_class.perform_later(branch.id) }
      .to have_enqueued_job(described_class).on_queue('default')
  end

  it 'inserts a parent->child edge for a simple two-commit branch' do
    parent_commit = commit_with_sha('a' * 40)
    child_commit  = commit_with_sha('b' * 40)

    allow(Commit).to receive(:api_commits).with(sha: 'main').and_return([
      fake_commit(sha: child_commit.sha, parent_shas: [parent_commit.sha]),
      fake_commit(sha: parent_commit.sha)
    ])

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
    allow(Commit).to receive(:api_commits).with(sha: 'main').and_return([
      fake_commit(sha: c.sha, parent_shas: [p.sha]),
      fake_commit(sha: p.sha)
    ])

    described_class.new.perform(branch.id)

    expect { described_class.new.perform(branch.id) }
      .not_to change(CommitRelation, :count)
  end

  it 'records every parent of a merge commit, tagging parent_index' do
    base  = commit_with_sha('a' * 40)
    side  = commit_with_sha('b' * 40)
    merge = commit_with_sha('c' * 40)

    allow(Commit).to receive(:api_commits).with(sha: 'main').and_return([
      fake_commit(sha: merge.sha, parent_shas: [base.sha, side.sha]),
      fake_commit(sha: side.sha),
      fake_commit(sha: base.sha)
    ])

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

    allow(Commit).to receive(:api_commits).with(sha: 'main').and_return([
      fake_commit(sha: child_commit.sha, parent_shas: [missing_sha])
    ])

    expect { described_class.new.perform(branch.id) }
      .not_to change(CommitRelation, :count)
  end

  it 'is a no-op when the API returns nothing' do
    allow(Commit).to receive(:api_commits).with(sha: 'main').and_return([])

    expect { described_class.new.perform(branch.id) }
      .not_to change(CommitRelation, :count)
  end

  it 'is a no-op when the API returns nil (branch not found)' do
    allow(Commit).to receive(:api_commits).with(sha: 'main').and_return(nil)

    expect { described_class.new.perform(branch.id) }
      .not_to change(CommitRelation, :count)
  end
end
